//
//  SFTPService.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import Foundation
import Darwin
import CSSH2

enum SFTPService {

    struct Credentials: Sendable {
        let host: String
        let port: Int
        let username: String
        let password: String
    }

    enum SFTPError: LocalizedError {
        case invalidHost(details: String?)
        case invalidPort
        case invalidUsername
        case invalidRemotePath

        case invalidLocalFileURL
        case localFileNotReadable
        case localFileSizeUnknown

        case dnsFailed(details: String?)
        case connectFailed

        case sshInitFailed
        case sshHandshakeFailed
        case authFailed
        case sftpInitFailed
        case sftpOpenDirFailed
        case sftpReadDirFailed
        case sftpUnlinkFailed(filename: String)

        case sftpOpenRemoteFileFailed(filename: String)
        case sftpWriteFailed
        case sftpCloseFailed

        var errorDescription: String? {
            switch self {
            case .invalidHost(let details):
                if let details, details.isEmpty == false {
                    return "SFTP Host ist ungültig. \(details)"
                }
                return "SFTP Host ist ungültig."

            case .invalidPort:
                return "SFTP Port ist ungültig."
            case .invalidUsername:
                return "SFTP Benutzername ist ungültig."
            case .invalidRemotePath:
                return "Remote-Pfad ist ungültig."

            case .invalidLocalFileURL:
                return "Lokale Datei ist ungültig."
            case .localFileNotReadable:
                return "Lokale Datei kann nicht gelesen werden."
            case .localFileSizeUnknown:
                return "Dateigröße konnte nicht ermittelt werden."

            case .dnsFailed(let details):
                if let details, details.isEmpty == false {
                    return "SFTP Host konnte nicht aufgelöst werden. \(details)"
                }
                return "SFTP Host konnte nicht aufgelöst werden."

            case .connectFailed:
                return "Verbindung zum Server fehlgeschlagen."

            case .sshInitFailed:
                return "SSH Initialisierung fehlgeschlagen."
            case .sshHandshakeFailed:
                return "SSH Handshake fehlgeschlagen."
            case .authFailed:
                return "SFTP Anmeldung fehlgeschlagen."
            case .sftpInitFailed:
                return "SFTP Initialisierung fehlgeschlagen."
            case .sftpOpenDirFailed:
                return "Remote-Verzeichnis konnte nicht geöffnet werden."
            case .sftpReadDirFailed:
                return "Remote-Verzeichnis konnte nicht gelesen werden."
            case .sftpUnlinkFailed(let filename):
                return "Remote-Datei konnte nicht gelöscht werden: \(filename)"

            case .sftpOpenRemoteFileFailed(let filename):
                return "Remote-Datei konnte nicht erstellt werden: \(filename)"
            case .sftpWriteFailed:
                return "Upload fehlgeschlagen. Schreiben auf dem Server nicht möglich."
            case .sftpCloseFailed:
                return "Upload abgeschlossen, aber Remote-Datei konnte nicht sauber geschlossen werden."
            }
        }
    }

    static func cleanupRemoteRoot(
        credentials: Credentials,
        remotePath: String = "/",
        onProgress: @escaping @Sendable (_ deleted: Int, _ total: Int) -> Void
    ) async throws {

        let normalizedHost = try normalizeHost(credentials.host)
        let username = normalizeSimple(credentials.username)

        guard credentials.port > 0 && credentials.port < 65536 else {
            throw SFTPError.invalidPort
        }
        guard username.isEmpty == false else {
            throw SFTPError.invalidUsername
        }
        guard remotePath == "/" else {
            throw SFTPError.invalidRemotePath
        }

        let task = Task.detached(priority: .userInitiated) { () async throws -> Void in
            try Task.checkCancellation()

            if libssh2_init(0) != 0 {
                throw SFTPError.sshInitFailed
            }
            defer { libssh2_exit() }

            let sock = try openTCPSocket(host: normalizedHost, port: credentials.port)
            defer { close(sock) }

            guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
                throw SFTPError.sshInitFailed
            }
            defer { libssh2_session_free(session) }

            libssh2_session_set_blocking(session, 1)

            if libssh2_session_handshake(session, sock) != 0 {
                throw SFTPError.sshHandshakeFailed
            }

            let authRc = username.withCString { userPtr in
                credentials.password.withCString { passPtr in
                    libssh2_userauth_password_ex(
                        session,
                        userPtr,
                        UInt32(strlen(userPtr)),
                        passPtr,
                        UInt32(strlen(passPtr)),
                        nil
                    )
                }
            }
            if authRc != 0 {
                throw SFTPError.authFailed
            }

            guard let sftp = libssh2_sftp_init(session) else {
                throw SFTPError.sftpInitFailed
            }
            defer { libssh2_sftp_shutdown(sftp) }

            guard let dirHandle = remotePath.withCString({ pathPtr in
                libssh2_sftp_open_ex(
                    sftp,
                    pathPtr,
                    UInt32(strlen(pathPtr)),
                    0,
                    0,
                    Int32(LIBSSH2_SFTP_OPENDIR)
                )
            }) else {
                throw SFTPError.sftpOpenDirFailed
            }
            defer { libssh2_sftp_close_handle(dirHandle) }

            var files: [String] = []
            try readDirectoryEntries(dirHandle: dirHandle, collectInto: &files)

            let total = files.count
            var deleted = 0
            onProgress(deleted, total)

            for name in files {
                try Task.checkCancellation()

                let fullPath = "/\(name)"
                let rc = fullPath.withCString { pathPtr in
                    libssh2_sftp_unlink_ex(sftp, pathPtr, UInt32(strlen(pathPtr)))
                }
                if rc != 0 {
                    throw SFTPError.sftpUnlinkFailed(filename: name)
                }

                deleted += 1
                onProgress(deleted, total)
            }
        }

        try await task.value
    }

    static func uploadFileToRemoteRoot(
        credentials: Credentials,
        localFileURL: URL,
        remoteFilename: String,
        onProgress: @escaping @Sendable (_ sentBytes: UInt64, _ totalBytes: UInt64) -> Void
    ) async throws {

        let normalizedHost = try normalizeHost(credentials.host)
        let username = normalizeSimple(credentials.username)

        guard credentials.port > 0 && credentials.port < 65536 else {
            throw SFTPError.invalidPort
        }
        guard username.isEmpty == false else {
            throw SFTPError.invalidUsername
        }

        guard localFileURL.isFileURL else {
            throw SFTPError.invalidLocalFileURL
        }

        let filePath = localFileURL.path
        guard FileManager.default.fileExists(atPath: filePath) else {
            throw SFTPError.invalidLocalFileURL
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: filePath)
        guard let fileSizeNumber = attrs[.size] as? NSNumber else {
            throw SFTPError.localFileSizeUnknown
        }

        let totalBytes = fileSizeNumber.uint64Value
        let safeName = sanitizeRemoteFilename(remoteFilename)
        let remotePath = "/\(safeName)"

        let task = Task.detached(priority: .userInitiated) { () async throws -> Void in
            try Task.checkCancellation()

            if libssh2_init(0) != 0 {
                throw SFTPError.sshInitFailed
            }
            defer { libssh2_exit() }

            let sock = try openTCPSocket(host: normalizedHost, port: credentials.port)
            defer { close(sock) }

            guard let session = libssh2_session_init_ex(nil, nil, nil, nil) else {
                throw SFTPError.sshInitFailed
            }
            defer { libssh2_session_free(session) }

            libssh2_session_set_blocking(session, 1)

            if libssh2_session_handshake(session, sock) != 0 {
                throw SFTPError.sshHandshakeFailed
            }

            let authRc = username.withCString { userPtr in
                credentials.password.withCString { passPtr in
                    libssh2_userauth_password_ex(
                        session,
                        userPtr,
                        UInt32(strlen(userPtr)),
                        passPtr,
                        UInt32(strlen(passPtr)),
                        nil
                    )
                }
            }
            if authRc != 0 {
                throw SFTPError.authFailed
            }

            guard let sftp = libssh2_sftp_init(session) else {
                throw SFTPError.sftpInitFailed
            }
            defer { libssh2_sftp_shutdown(sftp) }

            let flags = UInt(LIBSSH2_FXF_WRITE) | UInt(LIBSSH2_FXF_CREAT) | UInt(LIBSSH2_FXF_TRUNC)
            let mode: Int = Int(LIBSSH2_SFTP_S_IRUSR | LIBSSH2_SFTP_S_IWUSR | LIBSSH2_SFTP_S_IRGRP | LIBSSH2_SFTP_S_IROTH)

            guard let remoteHandle = remotePath.withCString({ pathPtr in
                libssh2_sftp_open_ex(
                    sftp,
                    pathPtr,
                    UInt32(strlen(pathPtr)),
                    flags,
                    mode,
                    Int32(LIBSSH2_SFTP_OPENFILE)
                )
            }) else {
                throw SFTPError.sftpOpenRemoteFileFailed(filename: safeName)
            }

            guard let fh = FileHandle(forReadingAtPath: filePath) else {
                libssh2_sftp_close_handle(remoteHandle)
                throw SFTPError.localFileNotReadable
            }
            defer { try? fh.close() }

            let bufferSize = 1024 * 1024
            var sent: UInt64 = 0
            onProgress(sent, totalBytes)

            while true {
                try Task.checkCancellation()

                let data = try fh.read(upToCount: bufferSize) ?? Data()
                if data.isEmpty { break }

                var offset = 0
                data.withUnsafeBytes { rawBuf in
                    let base = rawBuf.bindMemory(to: Int8.self).baseAddress

                    while offset < data.count {
                        if Task.isCancelled { return }

                        let remaining = data.count - offset
                        let ptr = base!.advanced(by: offset)

                        let written = libssh2_sftp_write(remoteHandle, ptr, remaining)
                        if written <= 0 {
                            return
                        }

                        offset += written
                        sent += UInt64(written)
                        onProgress(sent, totalBytes)
                    }
                }

                if offset < data.count {
                    libssh2_sftp_close_handle(remoteHandle)
                    throw SFTPError.sftpWriteFailed
                }
            }

            let closeRc = libssh2_sftp_close_handle(remoteHandle)
            if closeRc != 0 {
                throw SFTPError.sftpCloseFailed
            }

            onProgress(totalBytes, totalBytes)
        }

        try await task.value
    }

    // MARK: - Filename

    private static func sanitizeRemoteFilename(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "upload.bin" }

        var s = trimmed
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: ":", with: "_")
        s = s.replacingOccurrences(of: "\\", with: "_")

        while s.hasPrefix(".") { s.removeFirst() }
        if s.isEmpty { return "upload.bin" }

        return s
    }

    // MARK: - Host normalization

    private static func normalizeSimple(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeHost(_ raw: String) throws -> String {
        var s = raw

        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: s), url.scheme != nil {
            if let host = url.host, host.isEmpty == false {
                s = host
            } else {
                if let range = s.range(of: "://") {
                    s = String(s[range.upperBound...])
                }
            }
        }

        if let slash = s.firstIndex(of: "/") {
            s = String(s[..<slash])
        }

        while s.hasSuffix(".") {
            s.removeLast()
        }

        let cleanedScalars = s.unicodeScalars.filter { scalar in
            if scalar.properties.generalCategory == .format { return false }
            if scalar.properties.isWhitespace { return false }
            return true
        }
        s = String(String.UnicodeScalarView(cleanedScalars))

        let lower = s.lowercased()

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        let badScalars = lower.unicodeScalars.filter { allowed.contains($0) == false }
        if badScalars.isEmpty == false {
            let codes = badScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ", ")
            throw SFTPError.invalidHost(details: "Unerlaubte Zeichen im Host. \(codes)")
        }

        if lower.isEmpty {
            throw SFTPError.invalidHost(details: "Host ist leer.")
        }

        return lower
    }

    // MARK: - Directory read helpers

    nonisolated private static func readDirectoryEntries(dirHandle: OpaquePointer, collectInto out: inout [String]) throws {
        let nameBufSize = 512
        var nameBuf = [CChar](repeating: 0, count: nameBufSize)
        var longEntryBuf = [CChar](repeating: 0, count: 1024)

        while true {
            var attrs = LIBSSH2_SFTP_ATTRIBUTES()

            let rc = libssh2_sftp_readdir_ex(
                dirHandle,
                &nameBuf,
                nameBuf.count,
                &longEntryBuf,
                longEntryBuf.count,
                &attrs
            )

            if rc == 0 { return }
            if rc < 0 { throw SFTPError.sftpReadDirFailed }

            let filename = String(cString: nameBuf)
            if filename == "." || filename == ".." { continue }

            let flags = UInt32(attrs.flags)
            let isDir: Bool

            if (flags & UInt32(LIBSSH2_SFTP_ATTR_PERMISSIONS)) != 0 {
                let perms = UInt32(attrs.permissions)
                let typeMask = UInt32(LIBSSH2_SFTP_S_IFMT)
                let dirType = UInt32(LIBSSH2_SFTP_S_IFDIR)
                isDir = (perms & typeMask) == dirType
            } else {
                isDir = true
            }

            if isDir { continue }
            out.append(filename)
        }
    }

    // MARK: - Socket

    nonisolated private static func openTCPSocket(host: String, port: Int) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var res: UnsafeMutablePointer<addrinfo>?
        let portStr = String(port)

        let gai = host.withCString { hostPtr in
            portStr.withCString { portPtr in
                getaddrinfo(hostPtr, portPtr, &hints, &res)
            }
        }

        guard gai == 0, let first = res else {
            let details = String(cString: gai_strerror(gai))
            throw SFTPError.dnsFailed(details: details.isEmpty ? nil : details)
        }
        defer { freeaddrinfo(first) }

        var ptr: UnsafeMutablePointer<addrinfo>? = first
        while let ai = ptr {
            let sock = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
            if sock < 0 {
                ptr = ai.pointee.ai_next
                continue
            }

            let conn = connect(sock, ai.pointee.ai_addr, ai.pointee.ai_addrlen)
            if conn == 0 {
                return sock
            }

            close(sock)
            ptr = ai.pointee.ai_next
        }

        throw SFTPError.connectFailed
    }
}

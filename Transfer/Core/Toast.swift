//
//  Toast.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import SwiftUI

struct ToastModel: Equatable, Identifiable {
    let id = UUID()
    let message: String
}

private struct ToastViewModifier: ViewModifier {

    @Binding var toast: ToastModel?

    func body(content: Content) -> some View {
        ZStack {
            content

            if let toast {
                VStack {
                    Spacer()

                    Text(toast.message)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(radius: 10, y: 6)
                        .padding(.bottom, 16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                        withAnimation(.snappy) { self.toast = nil }
                    }
                }
            }
        }
        .animation(.snappy, value: toast)
    }
}

extension View {
    func toast(_ toast: Binding<ToastModel?>) -> some View {
        modifier(ToastViewModifier(toast: toast))
    }
}

# Transfer
Transfer is a small macOS app for private use.
You drag one file into the app.
The app uploads the file to a server.
Before the upload it removes all files in the remote folder.
After the upload it calls an API to start server processing.
The app then polls the API until processing is done.
At the end it shows a final link that you can open or copy.

## Key goals
- One action workflow
- Clear progress feedback
- No App Store release
- Works on macOS 15

## User flow
1. Start the app
2. Drop one file into the window or onto the dock icon
3. Wait for the progress ring to complete
4. Copy or open the final link

## Settings
- SFTP host and port
- SFTP username and password
- API base URL
- API token for authorization

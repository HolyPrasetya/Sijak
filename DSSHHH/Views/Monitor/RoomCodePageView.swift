import SwiftUI
import CoreImage.CIFilterBuiltins

/// Page 1 Monitor — tampil sebelum 3 wasit join: room code + QR saja.
struct RoomCodePageView: View {
    @ObservedObject var manager: MultipeerManager

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text("Room Code")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(manager.roomCode)
                .font(.system(size: 72, weight: .bold, design: .monospaced))
                .tracking(6)

            if let qrImage = qrCode(from: manager.roomCode) {
                Image(qrImage, scale: 1, label: Text("QR Room"))
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 280, height: 280)
            }

            Text("Waiting for judges to join… (\(manager.connectedPeers.count)/\(manager.requiredJudgeCount))")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let url = manager.webServerURL {
                VStack(spacing: 4) {
                    Text("Live scoreboard (view-only, any browser):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(url)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(.top, 4)
            }

            if let error = manager.lastError {
                Text(error).foregroundStyle(.red)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func qrCode(from string: String) -> CGImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        guard let outputImage = filter.outputImage else { return nil }
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return context.createCGImage(transformed, from: transformed.extent)
    }
}

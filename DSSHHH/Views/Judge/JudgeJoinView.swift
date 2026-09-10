import SwiftUI

/// Layar pertama yang dibuka wasit di iPhone: masukkan room code (atau scan QR),
/// lalu tunggu sampai connect & dapat slot (Wasit A/B/C) dari host.
struct JudgeJoinView: View {
    @StateObject private var manager = MultipeerManager(role: .judge)
    @State private var codeInput: String = ""
    @State private var showScanner = false
    @State private var joinStatus: JoinStatus = .idle
    @State private var joinTimeoutTask: DispatchWorkItem?

    private enum JoinStatus: Equatable {
        case idle
        case searching
        case timedOut
        case reconnecting
    }

    var body: some View {
        Group {
            if manager.isConnectedToRoom, let slot = manager.mySlot {
                JudgeScoringView(manager: manager, slot: slot)
            } else {
                joinForm
            }
        }
        .onChange(of: manager.isConnectedToRoom) { _, connected in
            if connected {
                joinStatus = .idle
                joinTimeoutTask?.cancel()
                return
            }
            // Kalau sebelumnya sempat connect lalu putus di tengah match, coba reconnect otomatis.
            guard joinStatus != .idle || !codeInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if joinStatus != .searching {
                joinStatus = .reconnecting
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    attemptJoin(code: codeInput)
                }
            }
        }
    }

    private var joinForm: some View {
        VStack(spacing: 20) {
            Text("Join Room")
                .font(.largeTitle.bold())

            TextField("Enter Room Code (e.g. HHH123)", text: $codeInput)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 40)
                .submitLabel(.join)
                .onSubmit {
                    attemptJoin(code: codeInput)
                }

            Button {
                attemptJoin(code: codeInput)
            } label: {
                Text("Join as Judge")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 40)
            .disabled(codeInput.trimmingCharacters(in: .whitespaces).isEmpty)

            statusView

            if let error = manager.lastError {
                Text(error).foregroundStyle(.red).font(.footnote)
            }

            #if os(iOS)
            Button {
                showScanner = true
            } label: {
                Label("Scan QR from Monitor", systemImage: "qrcode.viewfinder")
            }
            .padding(.top, 8)
            #endif
        }
        .padding()
        #if os(iOS)
        .sheet(isPresented: $showScanner) {
            QRScannerSheet { scannedCode in
                codeInput = scannedCode
                attemptJoin(code: scannedCode)
            }
        }
        #endif
    }

    @ViewBuilder
    private var statusView: some View {
        switch joinStatus {
        case .idle:
            EmptyView()
        case .searching:
            ProgressView("Searching for room \(codeInput.uppercased())...")
                .font(.footnote)
        case .reconnecting:
            Label("Connection lost — reconnecting...", systemImage: "wifi.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.orange)
        case .timedOut:
            Label("Room not found. Check: correct code, same WiFi, and Monitor is hosting.", systemImage: "exclamationmark.triangle")
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private func attemptJoin(code: String) {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        joinTimeoutTask?.cancel()
        joinStatus = .searching
        manager.joinRoom(code: trimmed)

        let task = DispatchWorkItem {
            if !manager.isConnectedToRoom {
                joinStatus = .timedOut
            }
        }
        joinTimeoutTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: task)
    }
}

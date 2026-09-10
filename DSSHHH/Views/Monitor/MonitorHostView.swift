import SwiftUI

/// Layar Monitor — role host (jembatan MultipeerConnectivity + serve website), bisa dijalankan
/// di Mac ATAU salah satu iPhone yang dipilih jadi "Host a Match". Router antara 2 halaman:
/// - Page 1 (`RoomCodePageView`): room code + QR (buat wasit join) + link website (buat siapa pun lihat live),
///   tampil selama wasit belum lengkap & match belum di-setup.
/// - Page 2 (`MatchPageView`): begitu wasit join — mulai dari form setup (Gap/Ceiling/Timer),
///   lalu pindah ke layar skor/round/waktu setelah operator mulai Round 1.
struct MonitorHostView: View {
    @StateObject private var manager: MultipeerManager
    @StateObject private var log = MatchLogService()

    init() {
        _manager = StateObject(wrappedValue: MultipeerManager(role: .monitor))
    }

    var body: some View {
        Group {
            // "Sticky": begitu match sudah lewat fase setup, tetap di Page 2 walau ada wasit
            // yang sempat putus-nyambung (WiFi flaky) — supaya skor yang sedang jalan tidak hilang dari layar.
            if manager.scoreState.phase == .setup && manager.connectedPeers.count < manager.requiredJudgeCount {
                RoomCodePageView(manager: manager)
            } else {
                MatchPageView(manager: manager, log: log)
            }
        }
        #if os(macOS)
        .frame(minWidth: 960, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
        .onAppear {
            manager.startHosting()
        }
    }
}

private struct MatchPageView: View {
    @ObservedObject var manager: MultipeerManager
    @ObservedObject var log: MatchLogService

    var body: some View {
        switch manager.scoreState.phase {
        case .setup:
            MatchSetupView(manager: manager)
        case .live, .roundEnded, .matchOver:
            ScoringPageView(manager: manager, log: log)
        }
    }
}

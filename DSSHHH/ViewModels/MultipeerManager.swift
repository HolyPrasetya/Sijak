import Foundation
import MultipeerConnectivity
import Combine

/// Satu manager dipakai di semua device (judge & monitor).
/// Perbedaan perilaku (siapa yang boleh hitung skor) ditentukan oleh `role`.
final class MultipeerManager: NSObject, ObservableObject {

    // MARK: Published state (dibaca oleh SwiftUI views)

    @Published var connectedPeers: [MCPeerID] = []
    @Published var isHosting: Bool = false
    @Published var isConnectedToRoom: Bool = false
    @Published var scoreState = ScoreState()
    @Published var lastError: String?

    /// Host-only, tidak di-broadcast: tiap kali ADA wasit menekan tombol poin, terlepas dari quorum tercapai
    /// atau tidak. Dipakai Monitor buat kasih sinyal "ada percobaan poin masuk" ke operator secara real-time.
    @Published var lastVoteAttempt: JudgeVote?

    /// Host-only: true selama ada 1 koreksi manual (adjustPoint/adjustGamJeom) yang bisa di-undo.
    @Published var canUndo: Bool = false

    /// Host-only: URL local network buat buka halaman scoreboard read-only di browser mana pun
    /// (laptop/HP tanpa perlu install app) — lihat MonitorWebServer. nil selagi belum hosting.
    @Published var webServerURL: String?
    private let webServer = MonitorWebServer()

    /// Diisi otomatis: wasit A/B/C berdasar urutan koneksi ke host.
    /// Di device judge, ini dipakai untuk tahu "aku wasit yang mana".
    @Published var mySlot: JudgeSlot?

    let role: DeviceRole
    let displayName: String
    private(set) var roomCode: String

    // MARK: Multipeer plumbing

    private let serviceType = "tkd-scoring" // max 15 char, huruf kecil & angka & dash

    private lazy var myPeerID = MCPeerID(displayName: displayName)
    private lazy var session: MCSession = {
        let s = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        s.delegate = self
        return s
    }()

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    // MARK: Voting window (host-only logic)

    /// Vote yang masuk dalam window waktu berjalan, menunggu quorum (>=2 wasit sama).
    private var pendingVotes: [JudgeVote] = []
    private let voteWindow: TimeInterval = 1.2 // detik — selaras dg PSS asli
    private var voteWindowTimer: Timer?

    /// Urutan slot untuk wasit yang connect ke host (assign otomatis).
    private var judgeAssignment: [MCPeerID: JudgeSlot] = [:]

    /// Snapshot sebelum adjustPoint/adjustGamJeom terakhir — dipulihkan oleh .undoLastAdjustment.
    private var previousScoreState: ScoreState?

    // MARK: Timer round (host-only)

    private var roundTimer: Timer?
    let totalRounds: Int = 3

    // TESTING: sementara diturunkan ke 1 wasit biar bisa dites sendirian pakai 1 device.
    // Ini cuma ngatur gerbang pindah halaman Monitor (Page 1 -> Page 2) & kapasitas room —
    // logic quorum vote (>=2 wasit setuju baru poin sah, lihat evaluatePendingVotes) TIDAK diubah,
    // jadi tetap butuh 2+ device kalau mau tes voting-nya beneran nanti.
    // Balikin ke 3 lagi kalau sudah siap tes/pakai dengan 3 wasit asli.
    let requiredJudgeCount: Int = 1

    // MARK: Init

    init(role: DeviceRole, displayName: String = UIDeviceName.current, roomCode: String? = nil) {
        self.role = role
        self.displayName = displayName
        self.roomCode = roomCode ?? Self.generateRoomCode()
        super.init()
    }

    // MARK: - Room code

    /// Format: 3 huruf + 3 angka, misal "HHH123" — gampang dibaca & diketik manual kalau QR gagal scan.
    static func generateRoomCode() -> String {
        let letters = "ABCDEFGHJKLMNPQRSTUVWXYZ" // tanpa huruf ambigu (I, O)
        let digits = "0123456789"
        let l = String((0..<3).map { _ in letters.randomElement()! })
        let d = String((0..<3).map { _ in digits.randomElement()! })
        return l + d
    }

    // MARK: - Host (Monitor) flow

    /// Dipanggil di Mac: mulai session sebagai host & mulai advertise room code ini.
    func startHosting() {
        isHosting = true
        let info = ["roomCode": roomCode, "role": DeviceRole.monitor.rawValue]
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()

        webServer.start()
        if let ip = localWiFiIPAddress() {
            webServerURL = "http://\(ip):8080"
        }
    }

    func stopHosting() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isHosting = false

        webServer.stop()
        webServerURL = nil
    }

    // MARK: - Judge flow

    /// Dipanggil di iPhone wasit: cari room dengan kode tertentu (dari input manual atau hasil scan QR) & connect.
    func joinRoom(code: String) {
        self.roomCode = code.uppercased()
        stopBrowsing() // hentikan browser lama dulu kalau ada, hindari numpuk instance
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    // MARK: - Kirim vote (dipanggil dari UI tombol wasit)

    func castVote(side: AthleteSide, point: PointValue) {
        guard role == .judge, let slot = mySlot else { return }
        let vote = JudgeVote(judge: slot, side: side, point: point)
        send(.judgeVote(vote))

        // Wasit sendiri juga ikut proses vote lokal kalau kebetulan dia jadi host suatu saat.
        // Tapi normalnya keputusan akhir tetap di Monitor lewat handleIncoming(vote:).
    }

    // MARK: - Kirim pesan generik

    private func send(_ message: RoomMessage) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            lastError = "Gagal kirim data: \(error.localizedDescription)"
        }
    }

    /// Broadcast, dipakai host untuk menyebarkan ScoreState / ControlAction terbaru.
    private func broadcast(_ message: RoomMessage) {
        send(message)
        // Host juga update state lokalnya sendiri supaya UI Mac langsung reflect.
        if case .scoreUpdate(let state) = message {
            DispatchQueue.main.async { self.scoreState = state }
            webServer.broadcast(scoreState: state) // dorong juga ke browser yang lagi buka halaman web
        }
    }

    // MARK: - Voting logic (HOST ONLY)

    private func handleIncoming(vote: JudgeVote) {
        guard role == .monitor else { return } // hanya host yang menghitung

        lastVoteAttempt = vote // sinyal ke UI Monitor: ada percobaan poin masuk (belum tentu sah)

        // Satu wasit cuma boleh punya satu vote aktif per window — double-tap wasit yang sama
        // tidak boleh dihitung sebagai 2 suara berbeda, harus dari wasit lain.
        pendingVotes.removeAll { $0.judge == vote.judge }
        pendingVotes.append(vote)
        restartVoteWindowTimerIfNeeded()
        evaluatePendingVotes()
    }

    private func restartVoteWindowTimerIfNeeded() {
        guard voteWindowTimer == nil else { return }
        voteWindowTimer = Timer.scheduledTimer(withTimeInterval: voteWindow, repeats: false) { [weak self] _ in
            self?.closeVoteWindow()
        }
    }

    private func closeVoteWindow() {
        voteWindowTimer = nil
        pendingVotes.removeAll() // vote yang tidak sempat quorum, dibuang
    }

    /// Cek apakah ada >=2 vote dengan side & point yang sama dalam window berjalan.
    /// Vote hanya berlaku selama round sedang live (bukan setup/roundEnded/matchOver).
    private func evaluatePendingVotes() {
        guard scoreState.phase == .live else {
            pendingVotes.removeAll()
            return
        }

        let grouped = Dictionary(grouping: pendingVotes) { "\($0.side.rawValue)-\($0.point.rawValue)" }
        guard let confirmed = grouped.first(where: { $0.value.count >= 2 })?.value.first else { return }

        // Quorum tercapai -> sahkan poin, reset window.
        voteWindowTimer?.invalidate()
        voteWindowTimer = nil
        pendingVotes.removeAll()

        var newState = scoreState
        switch confirmed.side {
        case .red: newState.redScore += confirmed.point.rawValue
        case .blue: newState.blueScore += confirmed.point.rawValue
        }
        newState.lastConfirmedVote = confirmed
        checkRoundEnd(&newState)
        scoreState = newState
        broadcast(.scoreUpdate(newState))
    }

    // MARK: - Kontrol timer & round (dipanggil dari UI Monitor / Mac)

    func send(control action: ControlAction) {
        guard role == .monitor else { return }
        applyControl(action) // host proses lokal juga
        send(.controlAction(action)) // beri tahu semua wasit (biar layar mereka ikut update status)
    }

    private func applyControl(_ action: ControlAction) {
        var state = scoreState
        switch action {
        case .configureMatch(let settings):
            guard state.phase == .setup else { break }
            state.matchSettings = settings
            state.timeRemaining = settings.roundDuration
            state.phase = .live

        case .startTimer:
            guard state.phase == .live else { break }
            state.isRunning = true
            startTicking()

        case .pauseTimer:
            state.isRunning = false
            roundTimer?.invalidate()
            roundTimer = nil

        case .resetTimer:
            state.isRunning = false
            state.timeRemaining = state.matchSettings.roundDuration
            roundTimer?.invalidate()
            roundTimer = nil

        case .resetMatch:
            let settings = state.matchSettings
            state = ScoreState()
            state.matchSettings = settings
            state.timeRemaining = settings.roundDuration
            roundTimer?.invalidate()
            roundTimer = nil
            previousScoreState = nil
            canUndo = false

        case .adjustPoint(let side, let delta):
            // Koreksi skor manual oleh operator (misal wasit salah pencet, atau ada insiden yang perlu dikoreksi).
            previousScoreState = state
            canUndo = true
            switch side {
            case .red: state.redScore = max(0, state.redScore + delta)
            case .blue: state.blueScore = max(0, state.blueScore + delta)
            }
            checkRoundEnd(&state)

        case .adjustGamJeom(let against, let delta):
            // Gam-jeom: pihak yang kena penalty dicatat, poin otomatis masuk/keluar dari lawan.
            // Diputuskan manual oleh operator Monitor (sesuai peran wasit tengah di lapangan asli),
            // bukan lewat voting 3 wasit seperti poin tendangan/pukulan.
            previousScoreState = state
            canUndo = true
            switch against {
            case .red:
                state.redPenalties = max(0, state.redPenalties + delta)
                state.blueScore = max(0, state.blueScore + delta)
            case .blue:
                state.bluePenalties = max(0, state.bluePenalties + delta)
                state.redScore = max(0, state.redScore + delta)
            }
            checkRoundEnd(&state)

        case .undoLastAdjustment:
            guard let previous = previousScoreState else { break }
            state = previous
            previousScoreState = nil
            canUndo = false

        case .confirmRoundWinner(let winner):
            guard state.phase == .roundEnded else { break }
            previousScoreState = nil
            canUndo = false
            state.roundHistory.append(winner)
            state.roundWinner = nil

            let redWins = state.roundHistory.filter { $0 == .red }.count
            let blueWins = state.roundHistory.filter { $0 == .blue }.count
            if redWins == 2 || blueWins == 2 {
                state.phase = .matchOver
                state.matchWinner = redWins == 2 ? .red : .blue
            } else {
                state.round = min(state.round + 1, totalRounds)
                state.redScore = 0
                state.blueScore = 0
                state.redPenalties = 0
                state.bluePenalties = 0
                state.timeRemaining = state.matchSettings.roundDuration
                state.isRunning = false
                state.phase = .live
            }
        }
        broadcast(.scoreUpdate(state))
    }

    // MARK: - Deteksi akhir round (HOST ONLY) — dipanggil tiap kali skor berubah / tiap detik timer jalan

    /// Round berakhir kalau: salah satu skor capai Ceiling Point, selisih skor capai Gap Point,
    /// atau waktu habis. Pemenang round langsung ditentukan dari skor akhir (seri -> nil, operator pilih manual).
    private func checkRoundEnd(_ state: inout ScoreState) {
        guard state.phase == .live else { return }
        let settings = state.matchSettings
        let total = state.redScore + state.blueScore
        let diff = abs(state.redScore - state.blueScore)

        let hitCeiling = state.redScore >= settings.ceilingPoint || state.blueScore >= settings.ceilingPoint
        let hitGap = settings.gapPoint > 0 && total > 0 && diff >= settings.gapPoint
        let timeUp = state.timeRemaining <= 0

        guard hitCeiling || hitGap || timeUp else { return }
        endRound(&state)
    }

    private func endRound(_ state: inout ScoreState) {
        guard state.phase == .live else { return }
        state.isRunning = false
        roundTimer?.invalidate()
        roundTimer = nil
        state.phase = .roundEnded
        if state.redScore != state.blueScore {
            state.roundWinner = state.redScore > state.blueScore ? .red : .blue
        } else {
            state.roundWinner = nil // seri — operator wajib pilih manual
        }
    }

    private func startTicking() {
        roundTimer?.invalidate()
        roundTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            var state = self.scoreState
            guard state.isRunning, state.phase == .live, state.timeRemaining > 0 else { return }

            state.timeRemaining -= 1
            self.checkRoundEnd(&state) // waktu habis -> phase .roundEnded, timer ikut di-invalidate di sini
            self.scoreState = state
            // Broadcast tiap detik supaya wasit lihat waktu juga. Kalau mau irit bandwidth,
            // bisa diubah broadcast tiap 5 detik saja + wasit hitung mundur sendiri secara lokal.
            self.broadcast(.scoreUpdate(state))
        }
    }

    // MARK: - Assign slot wasit (host only, saat peer baru connect)

    private func assignSlotIfNeeded(to peer: MCPeerID) {
        guard role == .monitor, judgeAssignment[peer] == nil else { return }
        let used = Set(judgeAssignment.values)
        guard let free = JudgeSlot.allCases.first(where: { !used.contains($0) }) else {
            lastError = "Room sudah penuh (maks 3 wasit)."
            return
        }
        judgeAssignment[peer] = free
        // Kirim slot assignment lewat pesan 'identify' balik ke peer itu (unicast).
        if let data = try? JSONEncoder().encode(RoomMessage.identify(role: .judge, displayName: free.rawValue)) {
            try? session.send(data, toPeers: [peer], with: .reliable)
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) { self.connectedPeers.append(peerID) }
                self.isConnectedToRoom = true
                self.assignSlotIfNeeded(to: peerID)
            case .notConnected:
                self.connectedPeers.removeAll { $0 == peerID }
                self.judgeAssignment.removeValue(forKey: peerID)
                if self.role == .judge {
                    // Device judge cuma connect ke 1 peer (host). Kalau itu putus, dianggap disconnected total.
                    self.isConnectedToRoom = false
                    self.mySlot = nil
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(RoomMessage.self, from: data) else { return }
        DispatchQueue.main.async {
            switch message {
            case .judgeVote(let vote):
                self.handleIncoming(vote: vote)
            case .scoreUpdate(let state):
                // Device judge menerima state resmi dari host -> sinkronkan UI (animasi "poin masuk").
                self.scoreState = state
            case .controlAction:
                break // ditangani di step berikutnya (timer/round control)
            case .identify(let role, let displayName):
                if role == .judge, self.role == .judge {
                    self.mySlot = JudgeSlot.allCases.first { $0.rawValue == displayName }
                }
            }
        }
    }

    // Tidak dipakai untuk fitur ini, tapi wajib diimplementasi oleh protokol.
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate (host / Monitor)

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Tolak kalau room sudah penuh (3 wasit).
        let accept = connectedPeers.count < requiredJudgeCount
        invitationHandler(accept, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate (judge)

extension MultipeerManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Hanya invite host yang room code-nya cocok dengan yang kita masukkan/scan.
        guard let foundCode = info?["roomCode"], foundCode == roomCode else { return }
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // no-op untuk MVP
    }
}

// MARK: - Helper nama device default

enum UIDeviceName {
    static var current: String {
        #if os(iOS)
        return UIDevice.current.name
        #else
        return Host.current().localizedName ?? "Mac"
        #endif
    }
}

#if os(iOS)
import UIKit
#endif

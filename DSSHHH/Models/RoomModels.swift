import Foundation

// MARK: - Role tiap device dalam room

enum DeviceRole: String, Codable {
    case judge   // wasit (iPhone) — kirim vote poin
    case monitor // host (Mac) — kumpulkan vote, hitung skor, jadi source of truth
}

// MARK: - Warna atlet (sisi merah / biru, standar taekwondo)

enum AthleteSide: String, Codable, CaseIterable {
    case red
    case blue
}

// MARK: - Nilai poin yang bisa ditekan wasit

enum PointValue: Int, Codable, CaseIterable {
    case one = 1     // pukulan badan
    case two = 2     // tendangan badan
    case three = 3   // tendangan kepala
    case five = 5    // tendangan kepala berputar
}

// MARK: - Identitas wasit (A, B, C) — ditentukan urutan join

enum JudgeSlot: String, Codable, CaseIterable {
    case a = "Judge A"
    case b = "Judge B"
    case c = "Judge C"
}

// MARK: - Pesan yang dikirim lewat Multipeer

enum RoomMessage: Codable {
    case judgeVote(JudgeVote)          // wasit -> semua (termasuk monitor)
    case scoreUpdate(ScoreState)       // monitor -> semua (broadcast state resmi)
    case controlAction(ControlAction)  // monitor -> semua (start/pause/next round dll)
    case identify(role: DeviceRole, displayName: String) // handshake awal saat connect
}

// Vote satu wasit untuk satu kejadian poin
struct JudgeVote: Codable, Identifiable {
    let id: UUID
    let judge: JudgeSlot
    let side: AthleteSide
    let point: PointValue
    let timestamp: TimeInterval // Date().timeIntervalSince1970 saat ditekan

    init(judge: JudgeSlot, side: AthleteSide, point: PointValue) {
        self.id = UUID()
        self.judge = judge
        self.side = side
        self.point = point
        self.timestamp = Date().timeIntervalSince1970
    }
}

// MARK: - Tahapan pertandingan (dipakai Monitor untuk pindah halaman/tampilan)

enum MatchPhase: Codable, Equatable {
    case setup       // sebelum Round 1 mulai, operator isi Gap/Ceiling/Timer
    case live        // round sedang berjalan
    case roundEnded  // round selesai (waktu habis/gap/ceiling), menunggu konfirmasi pemenang round
    case matchOver   // best-of-3 sudah punya pemenang match
}

// Pengaturan match yang diisi operator sekali sebelum Round 1, berlaku untuk Round 1-3
struct MatchSettings: Codable, Equatable {
    var gapPoint: Int = 12       // round langsung selesai kalau selisih skor capai angka ini
    var ceilingPoint: Int = 20   // round langsung selesai begitu salah satu skor capai angka ini
    var roundDuration: TimeInterval = 120 // detik per round
}

// State resmi pertandingan — dihitung & dibroadcast oleh Monitor (host)
struct ScoreState: Codable {
    var redScore: Int = 0
    var blueScore: Int = 0
    var redPenalties: Int = 0  // gam-jeom yang diterima Merah -> jadi poin buat Biru
    var bluePenalties: Int = 0 // gam-jeom yang diterima Biru -> jadi poin buat Merah
    var round: Int = 1
    var timeRemaining: TimeInterval = 120 // detik, default 2 menit/round
    var isRunning: Bool = false
    var lastConfirmedVote: JudgeVote? = nil // untuk animasi "poin masuk" di layar wasit

    var phase: MatchPhase = .setup
    var matchSettings: MatchSettings = MatchSettings()
    var roundWinner: AthleteSide? = nil   // hasil sementara saat phase == .roundEnded (nil kalau seri, nunggu pilihan manual)
    var roundHistory: [AthleteSide] = []  // pemenang tiap round yang sudah dikonfirmasi, urut Round 1..3 — sumber jumlah menang best-of-3
    var matchWinner: AthleteSide? = nil   // terisi begitu salah satu sisi menang 2 round
}

// Aksi kontrol dari Monitor (tombol timer/round/point/gam-jeom manual, dioperasikan operator di Mac)
enum ControlAction: Codable {
    case configureMatch(MatchSettings) // submit form setup, pindah phase .setup -> .live utk Round 1
    case startTimer
    case pauseTimer
    case resetTimer
    case resetMatch
    case adjustPoint(side: AthleteSide, delta: Int)      // koreksi skor manual oleh operator
    case adjustGamJeom(against: AthleteSide, delta: Int) // tambah/kurangi gam-jeom; otomatis geser skor lawan
    case undoLastAdjustment // batalkan adjustPoint/adjustGamJeom terakhir (1 level undo, buat nutup salah pencet)
    case confirmRoundWinner(AthleteSide) // operator konfirmasi pemenang round (auto-suggest atau override saat seri)
}

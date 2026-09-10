import Foundation
import Combine

/// Satu baris riwayat kejadian pertandingan — dipakai untuk review/protes setelah match selesai.
struct MatchLogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let description: String
    let scoreSnapshot: ScoreState

    init(description: String, scoreSnapshot: ScoreState) {
        self.id = UUID()
        self.timestamp = Date()
        self.description = description
        self.scoreSnapshot = scoreSnapshot
    }
}

/// Dipakai HANYA di device Monitor (host) — mencatat tiap kali skor berubah,
/// lalu bisa diekspor ke file JSON untuk dilihat/dibagikan setelah pertandingan.
final class MatchLogService: ObservableObject {
    @Published private(set) var entries: [MatchLogEntry] = []

    func log(_ description: String, score: ScoreState) {
        entries.append(MatchLogEntry(description: description, scoreSnapshot: score))
    }

    func reset() {
        entries.removeAll()
    }

    /// Simpan log saat ini ke Documents folder, nama file berdasar room code + waktu.
    /// Kembalikan URL file kalau berhasil, supaya bisa langsung di-share (AirDrop/Files) dari Mac.
    @discardableResult
    func exportToFile(roomCode: String) -> URL? {
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let filename = "match-\(roomCode)-\(formatter.string(from: Date())).json"

            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = dir.appendingPathComponent(filename)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: url)
            return url
        } catch {
            print("MatchLogService export error: \(error)")
            return nil
        }
    }
}

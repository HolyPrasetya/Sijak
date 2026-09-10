import SwiftUI

/// Sub-state pertama di Page 2 — muncul begitu 3 wasit sudah join, sebelum Round 1 mulai.
/// Operator wajib isi Gap Point, Ceiling Point, dan durasi timer di sini; nilainya berlaku
/// sama untuk Round 1-3 (tidak bisa diubah lagi per-round setelah match jalan).
struct MatchSetupView: View {
    @ObservedObject var manager: MultipeerManager

    @State private var gapPoint = MatchSettings().gapPoint
    @State private var ceilingPoint = MatchSettings().ceilingPoint
    @State private var roundMinutes = 2
    @State private var roundSeconds = 0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text("Match Settings")
                .font(.title.weight(.bold))

            Text("All judges are connected — configure these settings before Round 1 starts.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 20) {
                settingRow(title: "Gap Point", subtitle: "Round ends immediately once the score gap reaches this value") {
                    Stepper("\(gapPoint) pts", value: $gapPoint, in: 1...30)
                }
                settingRow(title: "Ceiling Point", subtitle: "Round ends immediately once either score reaches this value") {
                    Stepper("\(ceilingPoint) pts", value: $ceilingPoint, in: 1...50)
                }
                settingRow(title: "Timer Duration / Round", subtitle: "Applies equally to Round 1, 2, and 3") {
                    HStack(spacing: 8) {
                        Stepper("\(roundMinutes) min", value: $roundMinutes, in: 0...10)
                        Stepper("\(roundSeconds) sec", value: $roundSeconds, in: 0...55, step: 5)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 560)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))

            Button {
                let settings = MatchSettings(
                    gapPoint: gapPoint,
                    ceilingPoint: ceilingPoint,
                    roundDuration: TimeInterval(roundMinutes * 60 + roundSeconds)
                )
                manager.send(control: .configureMatch(settings))
            } label: {
                Text("Start Round 1")
                    .font(.title3.weight(.semibold))
                    .frame(width: 240, height: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(roundMinutes == 0 && roundSeconds == 0)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func settingRow(title: String, subtitle: String, @ViewBuilder control: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

import SwiftUI

/// Sub-state kedua di Page 2 — layar skor/round/waktu utama, aktif selama match berjalan
/// (live, roundEnded, matchOver). Berisi kontrol operator: play/pause timer, koreksi poin manual
/// (1-5, tambah/kurang), gam-jeom (tambah/kurang), dan konfirmasi pemenang tiap round.
struct ScoringPageView: View {
    @ObservedObject var manager: MultipeerManager
    @ObservedObject var log: MatchLogService
    @State private var exportedURL: URL?
    @State private var attemptFlash: JudgeVote?

    private var state: ScoreState { manager.scoreState }

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                header

                HStack(spacing: 0) {
                    sidePanel(side: .red, score: state.redScore, penalties: state.redPenalties, color: .red, label: "RED")
                    timerBlock
                    sidePanel(side: .blue, score: state.blueScore, penalties: state.bluePenalties, color: .blue, label: "BLUE")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(state.phase != .live)
            .opacity(state.phase == .live ? 1 : 0.35)

            if state.phase == .roundEnded {
                roundEndedOverlay
            } else if state.phase == .matchOver {
                matchOverOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: state.redScore) { _, _ in logCurrentScore() }
        .onChange(of: state.blueScore) { _, _ in logCurrentScore() }
        .onChange(of: state.round) { _, _ in logCurrentScore() }
        .onChange(of: manager.lastVoteAttempt?.id) { _, _ in
            guard let vote = manager.lastVoteAttempt else { return }
            attemptFlash = vote
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                if attemptFlash?.id == vote.id { attemptFlash = nil }
            }
        }
    }

    // MARK: - Header: Round X/3 + pip pemenang tiap round

    private var header: some View {
        VStack(spacing: 8) {
            Text("ROUND \(state.round) / \(manager.totalRounds)")
                .font(.title2.weight(.bold))
            HStack(spacing: 10) {
                ForEach(0..<manager.totalRounds, id: \.self) { i in
                    roundPip(index: i)
                }
            }
        }
    }

    private func roundPip(index: Int) -> some View {
        let winner = index < state.roundHistory.count ? state.roundHistory[index] : nil
        let color: Color = winner == .red ? .red : (winner == .blue ? .blue : Color.gray.opacity(0.3))
        return Circle().fill(color).frame(width: 14, height: 14)
    }

    // MARK: - Timer tengah

    private var timerBlock: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)

            Text(timeString(state.timeRemaining))
                .font(.system(size: 88, weight: .heavy, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .fixedSize(horizontal: true, vertical: false)

            Button {
                manager.send(control: state.isRunning ? .pauseTimer : .startTimer)
            } label: {
                Image(systemName: state.isRunning ? "pause.fill" : "play.fill")
                    .font(.title)
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.borderedProminent)

            Button("Reset Timer") {
                manager.send(control: .resetTimer)
            }
            .buttonStyle(.bordered)
            .font(.caption)

            Spacer(minLength: 0)
        }
        #if os(macOS)
        .frame(minWidth: 280, maxHeight: .infinity)
        #else
        .frame(minWidth: 130, maxHeight: .infinity)
        #endif
    }

    // MARK: - Panel per sisi (skor besar, gam-jeom, koreksi poin manual)

    private func sidePanel(side: AthleteSide, score: Int, penalties: Int, color: Color, label: String) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            Text(label)
                .font(.title3.weight(.bold))
                .foregroundStyle(color)
            Text("\(score)")
                .font(.system(size: 140, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .minimumScaleFactor(0.5)

            gamJeomControl(side: side, count: penalties)

            pointAdjustControl(side: side, color: color)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .top) {
            if let vote = attemptFlash, vote.side == side {
                Text("Vote in — \(vote.judge.rawValue): \(vote.point.rawValue) pts")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.95), in: Capsule())
                    .foregroundStyle(color)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeOut(duration: 0.2), value: attemptFlash?.id)
    }

    private func gamJeomControl(side: AthleteSide, count: Int) -> some View {
        HStack(spacing: 10) {
            Button {
                manager.send(control: .adjustGamJeom(against: side, delta: -1))
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .disabled(count <= 0)

            VStack(spacing: 0) {
                Text("\(count)").font(.title3.weight(.bold))
                Text("Gam-jeom").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 80)

            Button {
                manager.send(control: .adjustGamJeom(against: side, delta: 1))
            } label: {
                Image(systemName: "plus.circle.fill")
            }
        }
        .font(.title2)
        .buttonStyle(.plain)
    }

    private func pointAdjustControl(side: AthleteSide, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Adjust Points").font(.caption).foregroundStyle(.secondary)
                if manager.canUndo {
                    Button {
                        manager.send(control: .undoLastAdjustment)
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.caption2.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            HStack(spacing: 8) {
                ForEach([1, 2, 3, 4, 5], id: \.self) { value in
                    VStack(spacing: 4) {
                        Button("+\(value)") {
                            manager.send(control: .adjustPoint(side: side, delta: value))
                        }
                        Button("−\(value)") {
                            manager.send(control: .adjustPoint(side: side, delta: -value))
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.bordered)
            .tint(color)
        }
    }

    // MARK: - Footer: wasit terhubung + export

    private var footer: some View {
        VStack(spacing: 6) {
            Divider()
            Text("Judges connected: \(manager.connectedPeers.count)/\(manager.requiredJudgeCount)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let url = manager.webServerURL {
                Text("Live scoreboard: \(url)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Export Match History") {
                exportedURL = log.exportToFile(roomCode: manager.roomCode)
            }
            .buttonStyle(.bordered)
            .disabled(log.entries.isEmpty)

            if let url = exportedURL {
                Text("Saved: \(url.lastPathComponent)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Overlay akhir round

    private var roundEndedOverlay: some View {
        VStack(spacing: 24) {
            Text("ROUND \(state.round) COMPLETE")
                .font(.title.weight(.bold))

            if let winner = state.roundWinner {
                Text(winner == .red ? "RED WINS THE ROUND" : "BLUE WINS THE ROUND")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(winner == .red ? .red : .blue)
            } else {
                Text("SCORE TIED — pick the round winner manually")
                    .font(.title3.weight(.semibold))
            }

            HStack(spacing: 20) {
                confirmButton(side: .red, suggested: state.roundWinner == .red)
                confirmButton(side: .blue, suggested: state.roundWinner == .blue)
            }
        }
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 20)
    }

    private func confirmButton(side: AthleteSide, suggested: Bool) -> some View {
        Button {
            manager.send(control: .confirmRoundWinner(side))
        } label: {
            Text(side == .red ? "RED WINS" : "BLUE WINS")
                .font(.headline)
                .frame(width: 180, height: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(side == .red ? .red : .blue)
        .opacity(suggested ? 1 : 0.55)
    }

    // MARK: - Overlay akhir match

    private var matchOverOverlay: some View {
        let redWins = state.roundHistory.filter { $0 == .red }.count
        let blueWins = state.roundHistory.filter { $0 == .blue }.count
        return VStack(spacing: 24) {
            Text("MATCH COMPLETE")
                .font(.title.weight(.bold))

            if let winner = state.matchWinner {
                Text(winner == .red ? "RED WINS THE MATCH" : "BLUE WINS THE MATCH")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(winner == .red ? .red : .blue)
            }

            Text("\(redWins) - \(blueWins)")
                .font(.title2.monospacedDigit())
                .foregroundStyle(.secondary)

            Button("New Match") {
                manager.send(control: .resetMatch)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 20)
    }

    private func logCurrentScore() {
        let desc = "Score \(state.redScore) - \(state.blueScore) | Round \(state.round)"
        log.log(desc, score: state)
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        return String(format: "%02d:%02d", m, s)
    }
}

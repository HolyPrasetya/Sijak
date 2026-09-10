//
//  JudgeScoringView.swift
//  DSSHHH
//
//  Created by Ignasius Holy Prasetya on 24/07/26.
//


import SwiftUI

/// UI final layar wasit — dibelah 2 kolom warna, tiap kolom berisi tombol poin (5 besar / 3&2 sebaris / 1 kecil).
/// Menekan tombol cuma mengirim vote (lihat `MultipeerManager.castVote`) — skor di header BARU berubah
/// setelah Monitor mengesahkan quorum (>=2 dari 3 wasit), jadi satu tekanan sendiri tidak pernah langsung jadi poin.
/// Ada flash border tiap kali vote wasit ini ikut memicu poin sah.
struct JudgeScoringView: View {
    @ObservedObject var manager: MultipeerManager
    let slot: JudgeSlot

    @State private var flashSide: AthleteSide?
    @State private var showJoinedToast = true

    private let redGradient = LinearGradient(
        colors: [Color(hex: "D81919"), Color(hex: "9B0D0D")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private let blueGradient = LinearGradient(
        colors: [Color(hex: "1667FF"), Color(hex: "10368B")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                header
                HStack(spacing: 2) {
                    sidePanel(side: .red, gradient: redGradient, textColor: Color(hex: "D81919"))
                    Rectangle().fill(Color.black).frame(width: 2)
                    sidePanel(side: .blue, gradient: blueGradient, textColor: Color(hex: "1667FF"))
                }
            }

            if showJoinedToast {
                joinedToast
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(hex: "0F0F0F"))
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: manager.scoreState.lastConfirmedVote?.id) { _, _ in
            guard let vote = manager.scoreState.lastConfirmedVote else { return }
            flashSide = vote.side
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if flashSide == vote.side { flashSide = nil }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation { showJoinedToast = false }
            }
        }
    }

    /// Muncul sebentar begitu view ini kepasang (artinya baru berhasil connect & dapat slot) —
    /// konfirmasi eksplisit "kamu beneran connect", bukan cuma diam-diam masuk ke layar skor.
    private var joinedToast: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
            Text("Joined as \(slot.rawValue)")
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.92), in: Capsule())
        .padding(.top, 12)
    }

    private var header: some View {
        HStack {
            scoreBlock(value: manager.scoreState.redScore, title: "RED", color: Color(hex: "FF3B30"))
            Spacer()
            VStack(spacing: 4) {
                connectionPill
                Text(slot.rawValue.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.45))
                Text(timeString(manager.scoreState.timeRemaining))
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("ROUND \(manager.scoreState.round)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(white: 0.6))
            }
            Spacer()
            scoreBlock(value: manager.scoreState.blueScore, title: "BLUE", color: Color(hex: "2F80FF"))
        }
        .padding(.horizontal, 28)
        .frame(height: 92)
        .background(Color(hex: "151515"))
    }

    /// Selalu tampil selagi layar ini kepasang (view ini cuma dirender saat `isConnectedToRoom == true`,
    /// lihat JudgeJoinView) — begitu koneksi putus, JudgeJoinView otomatis balik ke layar
    /// "reconnecting" jadi wasit tidak pernah nekan tombol tanpa tahu statusnya.
    private var connectionPill: some View {
        HStack(spacing: 4) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Text("CONNECTED")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(Color.green)
    }

    private func scoreBlock(value: Int, title: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Text("\(value)")
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .tracking(1)
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func sidePanel(side: AthleteSide, gradient: LinearGradient, textColor: Color) -> some View {
        let isFlashing = flashSide == side
        return GeometryReader { geo in
            VStack(spacing: geo.size.height * 0.045) {
                pointButton(side: side, point: .five, textColor: textColor)
                    .frame(width: geo.size.width * 0.6, height: geo.size.height * 0.34)
                HStack(spacing: geo.size.width * 0.04) {
                    // Panel biru sengaja dicerminkan (2, 3) dari panel merah (3, 2) biar simetris visual.
                    ForEach(side == .blue ? [PointValue.two, .three] : [PointValue.three, .two], id: \.self) { point in
                        pointButton(side: side, point: point, textColor: textColor)
                            .frame(width: geo.size.width * 0.3, height: geo.size.height * 0.27)
                    }
                }
                pointButton(side: side, point: .one, textColor: textColor)
                    .frame(width: geo.size.width * 0.37, height: geo.size.height * 0.23)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(gradient)
        .overlay(
            Rectangle().stroke(Color.white, lineWidth: isFlashing ? 8 : 0)
        )
        .animation(.easeOut(duration: 0.15), value: isFlashing)
    }

    private func pointButton(side: AthleteSide, point: PointValue, textColor: Color) -> some View {
        Button {
            manager.castVote(side: side, point: point)
        } label: {
            Text("\(point.rawValue)")
                .font(.system(size: fontSize(for: point), weight: .heavy, design: .rounded))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 8)
        }
        .buttonStyle(PressScaleButtonStyle())
    }

    private func fontSize(for point: PointValue) -> CGFloat {
        switch point {
        case .five: return 56
        case .three, .two: return 42
        case .one: return 38
        }
    }
}

/// Efek tekan (scale-down saat ditahan) — padanan `:active{transform:scale(.95)}` di desain web.
private struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private extension Color {
    init(hex: String) {
        var rgb: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgb)
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

import SwiftUI

/// Layar pertama di iPhone: pilih mau jadi wasit (join room orang lain) atau host (bikin room baru,
/// jembatan MultipeerConnectivity + serve website scoreboard — lihat MonitorHostView/MonitorWebServer).
struct RoleSelectionView: View {
    private enum Route: Hashable {
        case judge
        case host
    }

    @State private var route: Route?

    var body: some View {
        Group {
            switch route {
            case .judge:
                JudgeJoinView()
            case .host:
                MonitorHostView()
            case nil:
                picker
            }
        }
    }

    private var picker: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("DSSHHH")
                .font(.largeTitle.bold())
            Text("Choose your role for this match")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 16) {
                Button {
                    route = .judge
                } label: {
                    Label("Join as Judge", systemImage: "hand.point.up.left.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)

                Button {
                    route = .host
                } label: {
                    VStack(spacing: 4) {
                        Label("Host a Match", systemImage: "antenna.radiowaves.left.and.right")
                        Text("Creates the room + live web scoreboard")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }
}

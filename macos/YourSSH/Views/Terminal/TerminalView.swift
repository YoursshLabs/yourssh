import SwiftUI

// Placeholder — will be replaced with SwiftTerm integration in Sprint 2
struct TerminalView: View {
    @ObservedObject var session: SSHSession

    var body: some View {
        ZStack {
            Color.black

            switch session.status {
            case .connecting:
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Connecting to \(session.host.host)...")
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.system(.body, design: .monospaced))
                }
            case .error(let msg):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(msg)
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.system(.body, design: .monospaced))
                }
            default:
                Text("Terminal ready")
                    .foregroundStyle(.green)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

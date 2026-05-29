import SwiftUI

struct TerminalTabsView: View {
    @EnvironmentObject var appState: AppState
    let sessions: [SSHSession]
    @State private var selectedSessionId: String?

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(sessions) { session in
                        TabItem(
                            session: session,
                            isSelected: session.id == selectedSessionId,
                            onSelect: { selectedSessionId = session.id },
                            onClose: { appState.closeSession(id: session.id) }
                        )
                    }
                }
            }
            .frame(height: 36)
            .background(.bar)

            Divider()

            // Terminal content
            if let id = selectedSessionId,
               let session = sessions.first(where: { $0.id == id }) {
                TerminalView(session: session)
            }
        }
        .onAppear {
            selectedSessionId = sessions.last?.id
        }
        .onChange(of: sessions.count) { _ in
            if selectedSessionId == nil || !sessions.contains(where: { $0.id == selectedSessionId }) {
                selectedSessionId = sessions.last?.id
            }
        }
    }
}

struct TabItem: View {
    @ObservedObject var session: SSHSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(session.title)
                .font(.system(size: 12))
                .lineLimit(1)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(isSelected ? Color.primary.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    var statusColor: Color {
        switch session.status {
        case .connected: .green
        case .connecting: .yellow
        case .disconnected: .gray
        case .error: .red
        }
    }
}

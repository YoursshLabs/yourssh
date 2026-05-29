import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            HostListView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let session = appState.activeSessions.last {
                TerminalTabsView(sessions: appState.activeSessions)
            } else {
                WelcomeView()
            }
        }
        .navigationTitle("")
    }
}

struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("YourSSH")
                .font(.largeTitle.bold())
            Text("Select a host to connect")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

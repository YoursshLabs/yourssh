import SwiftUI

struct HostListView: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddHost = false
    @State private var searchText = ""

    var filteredHosts: [Host] {
        guard !searchText.isEmpty else { return appState.hosts }
        return appState.hosts.filter {
            $0.label.localizedCaseInsensitiveContains(searchText) ||
            $0.host.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(filteredHosts, selection: $appState.selectedHostId) { host in
            HostRowView(host: host)
                .tag(host.id)
                .contextMenu {
                    Button("Connect") { appState.connect(to: host) }
                    Divider()
                    Button("Delete", role: .destructive) {
                        appState.deleteHost(id: host.id)
                    }
                }
                .onTapGesture(count: 2) {
                    appState.connect(to: host)
                }
        }
        .searchable(text: $searchText, prompt: "Search hosts")
        .navigationTitle("YourSSH")
        .toolbar {
            ToolbarItem {
                Button(action: { showAddHost = true }) {
                    Label("Add Host", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddHost) {
            AddHostView()
        }
    }
}

struct HostRowView: View {
    let host: Host

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(host.label)
                .fontWeight(.medium)
            Text("\(host.username)@\(host.host):\(host.port)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

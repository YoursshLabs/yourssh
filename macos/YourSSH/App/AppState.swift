import SwiftUI
import Combine

class AppState: ObservableObject {
    @Published var hosts: [Host] = []
    @Published var activeSessions: [SSHSession] = []
    @Published var selectedHostId: String?

    private let hostStore = HostStore()

    init() {
        hosts = hostStore.loadAll()
    }

    func addHost(_ host: Host) {
        hosts.append(host)
        hostStore.save(hosts)
    }

    func deleteHost(id: String) {
        hosts.removeAll { $0.id == id }
        hostStore.save(hosts)
    }

    func connect(to host: Host) {
        let session = SSHSession(host: host)
        activeSessions.append(session)
        selectedHostId = host.id
    }

    func closeSession(id: String) {
        activeSessions.removeAll { $0.id == id }
    }
}

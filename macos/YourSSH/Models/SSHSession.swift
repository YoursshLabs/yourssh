import Foundation
import Combine

enum SessionStatus {
    case connecting
    case connected
    case disconnected
    case error(String)
}

class SSHSession: ObservableObject, Identifiable {
    let id: String = UUID().uuidString
    let host: Host

    @Published var status: SessionStatus = .connecting
    @Published var title: String

    init(host: Host) {
        self.host = host
        self.title = "\(host.username)@\(host.host)"
    }

    func disconnect() {
        status = .disconnected
    }
}

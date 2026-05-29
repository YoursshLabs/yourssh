import Foundation

struct Host: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var label: String
    var host: String
    var port: Int = 22
    var username: String
    var authMethod: AuthMethodType
    var group: String = ""
    var tags: [String] = []
    var createdAt: Date = Date()
}

enum AuthMethodType: Codable, Hashable {
    case password(String)
    case privateKey(keyId: String)
    case agent
}

class HostStore {
    private let key = "yourssh.hosts"

    func loadAll() -> [Host] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let hosts = try? JSONDecoder().decode([Host].self, from: data)
        else { return [] }
        return hosts
    }

    func save(_ hosts: [Host]) {
        if let data = try? JSONEncoder().encode(hosts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

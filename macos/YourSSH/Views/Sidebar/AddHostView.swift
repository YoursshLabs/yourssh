import SwiftUI

struct AddHostView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authType: AuthType = .password
    @State private var password = ""

    enum AuthType: String, CaseIterable {
        case password = "Password"
        case privateKey = "Private Key"
        case agent = "SSH Agent"
    }

    var isValid: Bool {
        !label.isEmpty && !host.isEmpty && !username.isEmpty && Int(port) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Connection") {
                    TextField("Label", text: $label)
                    TextField("Host / IP", text: $host)
                    TextField("Port", text: $port)
                    TextField("Username", text: $username)
                }

                Section("Authentication") {
                    Picker("Method", selection: $authType) {
                        ForEach(AuthType.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    if authType == .password {
                        SecureField("Password", text: $password)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape)
                Spacer()
                Button("Add Host") { save() }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 420)
        .navigationTitle("Add Host")
    }

    private func save() {
        let auth: AuthMethodType = switch authType {
            case .password: .password(password)
            case .privateKey: .privateKey(keyId: "")
            case .agent: .agent
        }
        let newHost = Host(
            label: label,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            authMethod: auth
        )
        appState.addHost(newHost)
        dismiss()
    }
}

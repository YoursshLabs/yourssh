import SwiftUI

struct SettingsView: View {
    private enum Tab: String, CaseIterable {
        case general = "General"
        case appearance = "Appearance"
        case keys = "SSH Keys"
        case advanced = "Advanced"

        var icon: String {
            switch self {
            case .general: "gear"
            case .appearance: "paintbrush"
            case .keys: "key"
            case .advanced: "wrench.and.screwdriver"
            }
        }
    }

    var body: some View {
        TabView {
            ForEach(Tab.allCases, id: \.self) { tab in
                Group {
                    switch tab {
                    case .general: GeneralSettingsView()
                    case .appearance: AppearanceSettingsView()
                    case .keys: KeyManagerView()
                    case .advanced: AdvancedSettingsView()
                    }
                }
                .tabItem {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
            }
        }
        .frame(width: 520, height: 380)
    }
}

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            Section("Connection") {
                Toggle("Auto-reconnect on disconnect", isOn: .constant(true))
                Stepper("Reconnect attempts: 3", value: .constant(3), in: 1...10)
                Stepper("Connection timeout: 30s", value: .constant(30), in: 5...120)
            }
        }
        .formStyle(.grouped)
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("terminalTheme") private var theme = "One Dark"
    @AppStorage("terminalFontSize") private var fontSize = 13.0

    let themes = ["One Dark", "Dracula", "Tokyo Night", "Solarized Dark", "Nord"]

    var body: some View {
        Form {
            Section("Terminal") {
                Picker("Theme", selection: $theme) {
                    ForEach(themes, id: \.self) { Text($0) }
                }
                Slider(value: $fontSize, in: 10...24, step: 1) {
                    Text("Font size: \(Int(fontSize))pt")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct KeyManagerView: View {
    var body: some View {
        Text("SSH Key Manager — Sprint 2")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AdvancedSettingsView: View {
    var body: some View {
        Form {
            Section("Debug") {
                Toggle("Enable verbose SSH logging", isOn: .constant(false))
            }
        }
        .formStyle(.grouped)
    }
}

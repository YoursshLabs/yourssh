import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Connection...") {}
                .keyboardShortcut("n", modifiers: [.command])
        }
    }
}

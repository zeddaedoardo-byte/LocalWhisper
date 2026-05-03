import AppKit
import SwiftUI

struct PathPickerRow: View {
    let title: String
    @Binding var path: String
    let canChooseDirectories: Bool

    var body: some View {
        HStack {
            TextField(title, text: $path)
                .textFieldStyle(.roundedBorder)

            Button("Choose...") {
                choosePath()
            }
        }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.title = "Choose \(title)"
        panel.canChooseFiles = !canChooseDirectories
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

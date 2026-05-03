import AppKit
import SwiftUI

struct PathPickerRow: View {
    let title: String
    @Binding var path: String
    let canChooseDirectories: Bool

    var body: some View {
        HStack {
            TextField(LocalizedStringKey(title), text: $path)
                .textFieldStyle(.roundedBorder)

            Button("Choose...") {
                choosePath()
            }
        }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.title = L10n.format("Choose %@", L10n.string(title))
        panel.canChooseFiles = !canChooseDirectories
        panel.canChooseDirectories = canChooseDirectories
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

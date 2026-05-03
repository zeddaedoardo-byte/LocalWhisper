import AppKit
import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "mic.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .foregroundStyle(LinearGradient(
                    colors: [.indigo, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing))

            Text("LocalWhisperFlow")
                .font(.system(size: 22, weight: .semibold))

            Text("Versione \(version)")
                .foregroundStyle(.secondary)

            Text("Trascrizione vocale offline su Apple Silicon con Whisper Large V3.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            HStack(spacing: 14) {
                Button("GitHub") {
                    if let url = URL(string: "https://github.com/zeddaedoardo-byte/LocalWhisperFlow") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("whisper.cpp") {
                    if let url = URL(string: "https://github.com/ggerganov/whisper.cpp") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}

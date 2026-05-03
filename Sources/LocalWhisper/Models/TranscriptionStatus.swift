import Foundation
import SwiftUI

enum TranscriptionStatus: Equatable {
    case idle
    case recording
    case transcribing
    case completed
    case failed(String)

    var title: LocalizedStringKey {
        switch self {
        case .idle: "Ready"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .completed: "Ready"
        case .failed: "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "mic.fill"
        case .recording:
            "record.circle.fill"
        case .transcribing:
            "waveform"
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    var primaryActionTitle: LocalizedStringKey {
        switch self {
        case .recording: "Stop and Transcribe"
        case .transcribing: "Transcribing…"
        default: "Start Recording"
        }
    }

    var canToggleRecording: Bool {
        switch self {
        case .transcribing:
            false
        default:
            true
        }
    }
}

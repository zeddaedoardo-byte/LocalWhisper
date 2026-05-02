import Foundation

enum TranscriptionStatus: Equatable {
    case idle
    case recording
    case transcribing
    case completed
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            "Ready"
        case .recording:
            "Recording"
        case .transcribing:
            "Transcribing"
        case .completed:
            "Completed"
        case .failed:
            "Error"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            "mic"
        case .recording:
            "stop.circle.fill"
        case .transcribing:
            "waveform"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .recording:
            "Stop and Transcribe"
        case .transcribing:
            "Transcribing..."
        default:
            "Start Recording"
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

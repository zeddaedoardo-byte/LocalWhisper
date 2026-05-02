import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
    case microphonePermissionDenied
    case recordingDidNotStart
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone permission was denied."
        case .recordingDidNotStart:
            "Audio recording did not start."
        case .noActiveRecording:
            "There is no active recording to stop."
        }
    }
}

@MainActor
final class AudioRecorderService: NSObject {
    private var recorder: AVAudioRecorder?
    private var currentFileURL: URL?

    func startRecording() async throws -> URL {
        let isAuthorized = await requestMicrophoneAccess()
        guard isAuthorized else {
            throw AudioRecorderError.microphonePermissionDenied
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-whisperflow-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioRecorderError.recordingDidNotStart
        }

        self.recorder = recorder
        self.currentFileURL = fileURL
        return fileURL
    }

    func stopRecording() throws -> URL {
        guard let recorder, let currentFileURL else {
            throw AudioRecorderError.noActiveRecording
        }

        recorder.stop()
        self.recorder = nil
        self.currentFileURL = nil
        return currentFileURL
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

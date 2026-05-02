import AVFoundation
import Combine
import CoreAudio
import Foundation

enum AudioRecorderError: LocalizedError {
    case microphonePermissionDenied
    case recordingDidNotStart(String)
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "Microphone permission was denied."
        case .recordingDidNotStart(let detail):
            "Audio recording did not start: \(detail)"
        case .noActiveRecording:
            "There is no active recording to stop."
        }
    }
}

@MainActor
final class AudioRecorderService: NSObject, ObservableObject {
    @Published private(set) var levelDB: Float = -160

    var preferredDeviceUID: String?

    private var engine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var currentFileURL: URL?
    private var pcmTargetFormat: AVAudioFormat?

    func startRecording() async throws -> URL {
        let isAuthorized = await requestMicrophoneAccess()
        guard isAuthorized else {
            throw AudioRecorderError.microphonePermissionDenied
        }

        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-whisperflow-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode

        if let uid = preferredDeviceUID,
           let device = AudioDeviceCatalog.device(forUID: uid),
           let unit = inputNode.audioUnit {
            var deviceID = device.id
            let status = AudioUnitSetProperty(
                unit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout.size(ofValue: deviceID))
            )
            if status != noErr {
                throw AudioRecorderError.recordingDidNotStart("Could not bind input device (status \(status)).")
            }
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw AudioRecorderError.recordingDidNotStart("Selected input device produced an invalid format.")
        }

        let targetSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioRecorderError.recordingDidNotStart("Could not build target audio format.")
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forWriting: fileURL, settings: targetSettings,
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        } catch {
            throw AudioRecorderError.recordingDidNotStart(error.localizedDescription)
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.recordingDidNotStart("Could not build audio converter.")
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.process(buffer: buffer, converter: converter, targetFormat: targetFormat, file: file)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw AudioRecorderError.recordingDidNotStart(error.localizedDescription)
        }

        self.engine = engine
        self.audioFile = file
        self.converter = converter
        self.pcmTargetFormat = targetFormat
        self.currentFileURL = fileURL
        return fileURL
    }

    func stopRecording() throws -> URL {
        guard let engine, let currentFileURL else {
            throw AudioRecorderError.noActiveRecording
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        self.engine = nil
        self.audioFile = nil
        self.converter = nil
        self.pcmTargetFormat = nil
        self.currentFileURL = nil
        levelDB = -160
        return currentFileURL
    }

    func quickLevelTest(seconds: TimeInterval = 1.5) async throws -> Float {
        let url = try await startRecording()
        defer { try? FileManager.default.removeItem(at: url) }
        var peak: Float = -160
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
            peak = max(peak, levelDB)
        }
        _ = try? stopRecording()
        return peak
    }

    private func process(buffer: AVAudioPCMBuffer,
                         converter: AVAudioConverter,
                         targetFormat: AVAudioFormat,
                         file: AVAudioFile) {
        let inputFrames = AVAudioFrameCount(buffer.frameLength)
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outFrameCapacity = AVAudioFrameCount(Double(inputFrames) * ratio + 1024)

        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                               frameCapacity: outFrameCapacity) else { return }

        var fed = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }

        if outBuffer.frameLength > 0 {
            try? file.write(from: outBuffer)
        }

        let db = peakDB(buffer: buffer)
        Task { @MainActor [weak self] in
            self?.levelDB = db
        }
    }

    private func peakDB(buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return -160 }
        var maxAbs: Float = 0
        if let floatChannels = buffer.floatChannelData {
            let channels = Int(buffer.format.channelCount)
            for ch in 0..<channels {
                let p = floatChannels[ch]
                for i in 0..<frames {
                    let v = abs(p[i])
                    if v > maxAbs { maxAbs = v }
                }
            }
        } else if let intChannels = buffer.int16ChannelData {
            let channels = Int(buffer.format.channelCount)
            for ch in 0..<channels {
                let p = intChannels[ch]
                for i in 0..<frames {
                    let v = abs(Float(p[i])) / 32768.0
                    if v > maxAbs { maxAbs = v }
                }
            }
        }
        if maxAbs <= 0 { return -160 }
        return 20 * log10(maxAbs)
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

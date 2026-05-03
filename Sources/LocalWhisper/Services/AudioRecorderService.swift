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

    var preferredDeviceUID: String? {
        didSet {
            if oldValue != preferredDeviceUID {
                tearDownEngine()
            }
        }
    }

    private let pipelineLock = NSLock()
    nonisolated(unsafe) private var audioFile: AVAudioFile?
    nonisolated(unsafe) private var converter: AVAudioConverter?
    nonisolated(unsafe) private var targetFormat: AVAudioFormat?
    nonisolated(unsafe) private var isRecording: Bool = false

    private var engine: AVAudioEngine?
    private var inputFormat: AVAudioFormat?
    private var currentFileURL: URL?
    private var isPrepared: Bool = false
    private var deviceUIDApplied: String?
    private var idleTimer: Timer?

    func prewarm() async {
        do {
            try await prepareEngine()
        } catch {
            // Ignore. The first real recording will surface the error.
        }
    }

    func startRecording() async throws -> URL {
        if !isPrepared {
            try await prepareEngine()
        }
        guard let engine, let targetFormat else {
            throw AudioRecorderError.recordingDidNotStart("Engine not ready.")
        }

        idleTimer?.invalidate()
        idleTimer = nil

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
        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: fileURL,
                settings: settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true
            )
        } catch {
            throw AudioRecorderError.recordingDidNotStart(error.localizedDescription)
        }

        pipelineLock.lock()
        self.audioFile = file
        self.targetFormat = targetFormat
        self.isRecording = true
        pipelineLock.unlock()

        currentFileURL = fileURL

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                pipelineLock.lock()
                self.isRecording = false
                self.audioFile = nil
                pipelineLock.unlock()
                throw AudioRecorderError.recordingDidNotStart(error.localizedDescription)
            }
        }
        return fileURL
    }

    func stopRecording() throws -> URL {
        guard let url = currentFileURL else {
            throw AudioRecorderError.noActiveRecording
        }

        pipelineLock.lock()
        isRecording = false
        audioFile = nil
        pipelineLock.unlock()

        currentFileURL = nil
        levelDB = -160
        scheduleEngineIdleStop()
        return url
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

    private func prepareEngine() async throws {
        guard !isPrepared else { return }
        let isAuthorized = await requestMicrophoneAccess()
        guard isAuthorized else {
            throw AudioRecorderError.microphonePermissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        applyDevice(to: inputNode)

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw AudioRecorderError.recordingDidNotStart("Selected input device produced an invalid format.")
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioRecorderError.recordingDidNotStart("Could not build target audio format.")
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.recordingDidNotStart("Could not build audio converter.")
        }

        let lock = pipelineLock
        let weakSelf = WeakBox(self)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            AudioRecorderService.handleTap(
                buffer: buffer,
                weakService: weakSelf,
                lock: lock
            )
        }

        engine.prepare()

        self.engine = engine
        self.inputFormat = inputFormat
        self.targetFormat = targetFormat
        self.converter = converter
        self.deviceUIDApplied = preferredDeviceUID
        self.isPrepared = true
    }

    private func applyDevice(to inputNode: AVAudioInputNode) {
        guard let uid = preferredDeviceUID, !uid.isEmpty,
              let device = AudioDeviceCatalog.device(forUID: uid),
              let unit = inputNode.audioUnit else { return }
        var deviceID = device.id
        _ = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout.size(ofValue: deviceID))
        )
    }

    private func tearDownEngine() {
        idleTimer?.invalidate()
        idleTimer = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        engine = nil
        inputFormat = nil
        currentFileURL = nil

        pipelineLock.lock()
        audioFile = nil
        targetFormat = nil
        converter = nil
        isRecording = false
        pipelineLock.unlock()

        isPrepared = false
        deviceUIDApplied = nil
    }

    private func scheduleEngineIdleStop() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: 8.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard !self.isRecording else { return }
                if self.engine?.isRunning == true {
                    self.engine?.stop()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    nonisolated private static func handleTap(
        buffer: AVAudioPCMBuffer,
        weakService: WeakBox<AudioRecorderService>,
        lock: NSLock
    ) {
        let db = peakDB(buffer: buffer)
        if let service = weakService.value {
            Task { @MainActor in service.levelDB = db }
        }

        // Hold the lock for the whole convert+write so stopRecording cannot
        // return mid-write and let the consumer read a truncated WAV.
        lock.lock()
        defer { lock.unlock() }

        guard let service = weakService.value,
              service.isRecording,
              let file = service.audioFile,
              let converter = service.converter,
              let target = service.targetFormat else { return }

        let inputFrames = AVAudioFrameCount(buffer.frameLength)
        let ratio = target.sampleRate / buffer.format.sampleRate
        let outFrameCapacity = AVAudioFrameCount(Double(inputFrames) * ratio + 1024)
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrameCapacity) else {
            return
        }

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
    }

    nonisolated private static func peakDB(buffer: AVAudioPCMBuffer) -> Float {
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

private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T?) { self.value = value }
}

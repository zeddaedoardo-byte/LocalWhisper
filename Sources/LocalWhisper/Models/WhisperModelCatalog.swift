import Foundation

struct WhisperModelInfo: Identifiable, Hashable {
    let id: String           // e.g. "large-v3"
    let filename: String     // e.g. "ggml-large-v3.bin"
    let label: String
    let approxMB: Int
    let downloadURL: URL
    let multilingual: Bool
    let coreMLEncoderURL: URL?
    let coreMLEncoderApproxMB: Int?

    var coreMLDirectoryName: String {
        "ggml-\(id)-encoder.mlmodelc"
    }
}

enum WhisperModelCatalog {
    static let models: [WhisperModelInfo] = [
        .init(
            id: "large-v3",
            filename: "ggml-large-v3.bin",
            label: "Large V3 (3 GB, max accuracy)",
            approxMB: 3094,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin")!,
            multilingual: true,
            coreMLEncoderURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-encoder.mlmodelc.zip"),
            coreMLEncoderApproxMB: 180
        ),
        .init(
            id: "large-v3-turbo",
            filename: "ggml-large-v3-turbo.bin",
            label: "Large V3 Turbo (~1.5 GB, ~3× faster)",
            approxMB: 1574,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!,
            multilingual: true,
            coreMLEncoderURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-encoder.mlmodelc.zip"),
            coreMLEncoderApproxMB: 70
        ),
        .init(
            id: "large-v3-q5_0",
            filename: "ggml-large-v3-q5_0.bin",
            label: "Large V3 Q5_0 (~1.1 GB, quantized)",
            approxMB: 1080,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin")!,
            multilingual: true,
            coreMLEncoderURL: nil,
            coreMLEncoderApproxMB: nil
        ),
        .init(
            id: "medium",
            filename: "ggml-medium.bin",
            label: "Medium (~1.5 GB)",
            approxMB: 1462,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")!,
            multilingual: true,
            coreMLEncoderURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-encoder.mlmodelc.zip"),
            coreMLEncoderApproxMB: 75
        ),
        .init(
            id: "small",
            filename: "ggml-small.bin",
            label: "Small (488 MB)",
            approxMB: 488,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
            multilingual: true,
            coreMLEncoderURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-encoder.mlmodelc.zip"),
            coreMLEncoderApproxMB: 25
        ),
        .init(
            id: "base",
            filename: "ggml-base.bin",
            label: "Base (148 MB)",
            approxMB: 148,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
            multilingual: true,
            coreMLEncoderURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-encoder.mlmodelc.zip"),
            coreMLEncoderApproxMB: 12
        ),
        .init(
            id: "tiny",
            filename: "ggml-tiny.bin",
            label: "Tiny (78 MB, fastest)",
            approxMB: 78,
            downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,
            multilingual: true,
            coreMLEncoderURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-encoder.mlmodelc.zip"),
            coreMLEncoderApproxMB: 5
        )
    ]

    static func info(forID id: String) -> WhisperModelInfo? {
        models.first { $0.id == id }
    }

    static func info(forFilename filename: String) -> WhisperModelInfo? {
        models.first { $0.filename == filename }
    }
}

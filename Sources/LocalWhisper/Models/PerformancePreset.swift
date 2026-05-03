import Foundation

enum PerformancePreset: String, CaseIterable, Identifiable {
    case quality
    case balanced
    case speed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quality: "Qualità (più accurato)"
        case .balanced: "Bilanciato"
        case .speed: "Velocità (più rapido)"
        }
    }

    var description: String {
        switch self {
        case .quality:
            "Beam search ampio, miglior accuratezza. Consigliato su M2/M3/M4 con 16+ GB RAM."
        case .balanced:
            "Compromesso tra qualità e tempi di risposta. Default."
        case .speed:
            "Beam ridotto + audio context troncato. Ideale su Intel Mac o RAM ridotta."
        }
    }

    var beamSize: Int {
        switch self {
        case .quality: 5
        case .balanced: 2
        case .speed: 1
        }
    }

    var bestOf: Int {
        switch self {
        case .quality: 5
        case .balanced: 2
        case .speed: 1
        }
    }

    /// Audio context for the encoder. 0 means full (1500). Smaller = faster but
    /// risks truncating long utterances.
    var audioContext: Int {
        switch self {
        case .quality: 0
        case .balanced: 0
        case .speed: 768
        }
    }
}

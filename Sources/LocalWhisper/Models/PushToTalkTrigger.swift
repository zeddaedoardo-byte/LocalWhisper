import Foundation

struct PushToTalkTrigger: Identifiable, Hashable {
    enum Kind: Hashable {
        case modifierKey(keycode: Int, requiredFlags: UInt64)
        case modifierCombo(requiredFlags: UInt64)
    }

    let id: String
    let label: String
    let kind: Kind

    func evaluate(flagsRaw: UInt64, keycode: Int) -> Bool? {
        switch kind {
        case .modifierKey(let kc, let flags):
            guard keycode == kc else { return nil }
            return (flagsRaw & flags) == flags
        case .modifierCombo(let flags):
            return (flagsRaw & flags) == flags
        }
    }
}

extension PushToTalkTrigger {
    static let fn = PushToTalkTrigger(
        id: "fn", label: "fn",
        kind: .modifierKey(keycode: 63, requiredFlags: 0x800000)
    )
    static let leftControl = PushToTalkTrigger(
        id: "left_control", label: "Left ⌃ Control",
        kind: .modifierKey(keycode: 59, requiredFlags: 0x40000 | 0x000001)
    )
    static let rightControl = PushToTalkTrigger(
        id: "right_control", label: "Right ⌃ Control",
        kind: .modifierKey(keycode: 62, requiredFlags: 0x40000 | 0x002000)
    )
    static let leftCommand = PushToTalkTrigger(
        id: "left_command", label: "Left ⌘ Command",
        kind: .modifierKey(keycode: 55, requiredFlags: 0x100000 | 0x000008)
    )
    static let rightCommand = PushToTalkTrigger(
        id: "right_command", label: "Right ⌘ Command",
        kind: .modifierKey(keycode: 54, requiredFlags: 0x100000 | 0x000010)
    )
    static let leftOption = PushToTalkTrigger(
        id: "left_option", label: "Left ⌥ Option",
        kind: .modifierKey(keycode: 58, requiredFlags: 0x80000 | 0x000020)
    )
    static let rightOption = PushToTalkTrigger(
        id: "right_option", label: "Right ⌥ Option",
        kind: .modifierKey(keycode: 61, requiredFlags: 0x80000 | 0x000040)
    )
    static let leftShift = PushToTalkTrigger(
        id: "left_shift", label: "Left ⇧ Shift",
        kind: .modifierKey(keycode: 56, requiredFlags: 0x20000 | 0x000002)
    )
    static let rightShift = PushToTalkTrigger(
        id: "right_shift", label: "Right ⇧ Shift",
        kind: .modifierKey(keycode: 60, requiredFlags: 0x20000 | 0x000004)
    )
    static let cmdShift = PushToTalkTrigger(
        id: "cmd_shift", label: "⌘ + ⇧",
        kind: .modifierCombo(requiredFlags: 0x100000 | 0x20000)
    )
    static let cmdOption = PushToTalkTrigger(
        id: "cmd_option", label: "⌘ + ⌥",
        kind: .modifierCombo(requiredFlags: 0x100000 | 0x80000)
    )
    static let ctrlOption = PushToTalkTrigger(
        id: "ctrl_option", label: "⌃ + ⌥",
        kind: .modifierCombo(requiredFlags: 0x40000 | 0x80000)
    )

    static let all: [PushToTalkTrigger] = [
        .fn,
        .leftControl, .rightControl,
        .leftCommand, .rightCommand,
        .leftOption, .rightOption,
        .leftShift, .rightShift,
        .cmdShift, .cmdOption, .ctrlOption
    ]

    static func byID(_ id: String) -> PushToTalkTrigger {
        all.first { $0.id == id } ?? .fn
    }

    static func make(id: String, label: String, keycode: Int, flags: UInt64) -> PushToTalkTrigger {
        let modifierMask: UInt64 =
            0x800000 |   // fn
            0x100000 |   // command
            0x80000  |   // option
            0x40000  |   // control
            0x20000  |   // shift
            0x10000      // caps lock
        let modifierBits = flags & modifierMask
        let count = modifierBits.nonzeroBitCount
        if count > 1 {
            return PushToTalkTrigger(id: id, label: label, kind: .modifierCombo(requiredFlags: flags))
        }
        return PushToTalkTrigger(id: id, label: label, kind: .modifierKey(keycode: keycode, requiredFlags: flags))
    }

    static func describe(keycode: Int, flags: UInt64) -> String {
        var parts: [String] = []
        if flags & 0x800000 != 0 { parts.append("fn") }
        if flags & 0x10000 != 0 { parts.append("⇪") }
        if flags & 0x40000 != 0 { parts.append("⌃") }
        if flags & 0x80000 != 0 { parts.append("⌥") }
        if flags & 0x20000 != 0 { parts.append("⇧") }
        if flags & 0x100000 != 0 { parts.append("⌘") }
        if parts.isEmpty {
            parts.append("kc \(keycode)")
        } else if parts.count == 1, parts.first != "fn" {
            let side: String?
            if flags & 0x000010 != 0 || flags & 0x000040 != 0 || flags & 0x000004 != 0 || flags & 0x002000 != 0 {
                side = "Right"
            } else if flags & 0x000008 != 0 || flags & 0x000020 != 0 || flags & 0x000002 != 0 || flags & 0x000001 != 0 {
                side = "Left"
            } else {
                side = nil
            }
            if let side {
                parts[0] = "\(side) \(parts[0])"
            }
        }
        return parts.joined(separator: " + ")
    }
}

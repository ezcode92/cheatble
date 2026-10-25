import AppKit
import Carbon
import CheatbleCore

/// Receives only the registered chord; no input monitoring or event tap.
final class GlobalHotKey {
    private static var nextIdentity: UInt32 = 0
    var onPress: (() -> Void)?
    private var handler: EventHandlerRef?
    private var reference: EventHotKeyRef?
    private(set) var shortcut: ToggleShortcut?
    private(set) var identity = EventHotKeyID(signature: 0x4348424C, id: 0) // CHBL
    private var pressed = false

    func register(_ next: ToggleShortcut?) throws {
        precondition(Thread.isMainThread)
        guard let next else {
            if let reference { UnregisterEventHotKey(reference) }
            reference = nil; shortcut = nil; pressed = false
            return
        }
        if shortcut == next, reference != nil { return }
        let modifiers = Self.carbonModifiers(next.chord.modifiers)
        var systemKeys: Unmanaged<CFArray>?
        let systemStatus = CopySymbolicHotKeys(&systemKeys)
        guard systemStatus == noErr else { throw HotKeyError.systemCheck(systemStatus) }
        let systemEntries = systemKeys?.takeRetainedValue() as? [[String: Any]] ?? []
        if systemEntries.contains(where: {
            ($0[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true &&
            ($0[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == next.keyCode &&
            ($0[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == modifiers
        }) { throw HotKeyError.systemConflict }

        if handler == nil {
            var types = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            ]
            let callback: EventHandlerUPP = { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                var received = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &received)
                guard status == noErr, owner.reference != nil,
                      received.signature == owner.identity.signature, received.id == owner.identity.id
                else { return OSStatus(eventNotHandledErr) }
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) { owner.pressed = false }
                else if !owner.pressed { owner.pressed = true; owner.onPress?() }
                return noErr
            }
            let status = InstallEventHandler(GetApplicationEventTarget(), callback, types.count,
                &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { throw HotKeyError.registration(status) }
        }
        var replacement: EventHotKeyRef?
        // Every registration has its own ID, including other instances in this app.
        Self.nextIdentity &+= 1
        let nextID = EventHotKeyID(signature: identity.signature, id: Self.nextIdentity)
        let status = RegisterEventHotKey(next.keyCode, modifiers, nextID, GetApplicationEventTarget(),
                                        OptionBits(kEventHotKeyExclusive), &replacement)
        guard status == noErr, let replacement else { throw HotKeyError.registration(status) }
        // Keep the previous working registration until the replacement has succeeded.
        if let reference { UnregisterEventHotKey(reference) }
        reference = replacement; shortcut = next; identity = nextID; pressed = false
    }
    func stop() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil; handler = nil; shortcut = nil; pressed = false
    }
    deinit { stop() }
    static func carbonModifiers(_ modifiers: [Modifier]) -> UInt32 {
        modifiers.reduce(0) { mask, modifier in
            switch modifier {
            case .control: return mask | UInt32(controlKey)
            case .option: return mask | UInt32(optionKey)
            case .shift: return mask | UInt32(shiftKey)
            case .command: return mask | UInt32(cmdKey)
            case .function: return mask
            }
        }
    }
    enum HotKeyError: LocalizedError {
        case systemConflict, systemCheck(OSStatus), registration(OSStatus)
        var errorDescription: String? {
            switch self {
            case .systemConflict: return "macOS에서 이미 사용하는 키 조합입니다. 다른 조합을 선택해 주세요."
            case .systemCheck(let status): return "시스템 단축키를 확인하지 못했습니다 (\(status)). 다시 시도해 주세요."
            case .registration(let status) where status == eventHotKeyExistsErr:
                return "다른 앱이 이미 등록한 전역 단축키입니다. 다른 조합을 선택해 주세요."
            case .registration(let status): return "단축키를 등록하지 못했습니다 (\(status)). 다른 조합을 선택해 주세요."
            }
        }
    }
}

import AppKit
import Carbon.HIToolbox

/// Registers the application's global Command-Shift-Y shortcut.
///
/// Carbon's hot-key API observes virtual key codes (physical keys), so the
/// key code is resolved through the current keyboard layout. This keeps the
/// shortcut on the logical Y key for both QWERTY and QWERTZ layouts.
@MainActor
final class GlobalHotKey {
    private static let hotKeySignature: OSType = 0x4D54484B // "MTHK"
    private static let hotKeyID: UInt32 = 1

    private let action: @MainActor () -> Void
    private let onError: @MainActor (String?) -> Void
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var layoutObserver: NSObjectProtocol?
    private var isPressed = false
    private var wantsRegistration = false

    init(
        action: @escaping @MainActor () -> Void,
        onError: @escaping @MainActor (String?) -> Void
    ) {
        self.action = action
        self.onError = onError
    }

    /// The Carbon handler holds an unretained pointer back to this object, so
    /// the registration must not survive it even if no one calls `unregister()`.
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let layoutObserver { DistributedNotificationCenter.default().removeObserver(layoutObserver) }
    }

    func register() {
        guard hotKey == nil else { return }
        wantsRegistration = true

        if eventHandler == nil {
            var eventTypes = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
            ]
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                globalHotKeyEventHandler,
                eventTypes.count,
                &eventTypes,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandler
            )
            guard status == noErr else {
                onError(Self.errorMessage(for: status))
                return
            }
        }

        observeKeyboardLayoutChanges()

        guard let keyCode = Self.logicalYKeyCode() else {
            onError("Globaler Shortcut konnte wegen der Tastaturbelegung nicht eingerichtet werden.")
            return
        }

        let identifier = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(cmdKey | shiftKey),
            identifier,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &hotKey
        )
        guard status == noErr else {
            hotKey = nil
            onError(Self.errorMessage(for: status))
            return
        }

        onError(nil)
    }

    func unregister() {
        wantsRegistration = false
        if let hotKey {
            _ = UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        isPressed = false
        if let eventHandler {
            _ = RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        if let layoutObserver {
            DistributedNotificationCenter.default().removeObserver(layoutObserver)
            self.layoutObserver = nil
        }
    }

    private func observeKeyboardLayoutChanges() {
        guard layoutObserver == nil else { return }
        let name = Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: name,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.reregisterForCurrentKeyboardLayout() }
        }
    }

    private func reregisterForCurrentKeyboardLayout() {
        guard wantsRegistration else { return }
        if let hotKey {
            _ = UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        isPressed = false
        register()
    }

    fileprivate func handle(kind: UInt32, identifier: EventHotKeyID) {
        guard wantsRegistration, hotKey != nil else { return }
        guard identifier.signature == Self.hotKeySignature,
              identifier.id == Self.hotKeyID else { return }
        if kind == UInt32(kEventHotKeyPressed) {
            guard !isPressed else { return }
            isPressed = true
            action()
        } else if kind == UInt32(kEventHotKeyReleased) {
            isPressed = false
        }
    }

    private static func logicalYKeyCode() -> UInt32? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = unsafeBitCast(dataPointer, to: CFData.self)
        guard let layoutBytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(layoutBytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let keyboardType = UInt32(LMGetKbdType())

        for keyCode in UInt16(0)..<UInt16(128) {
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDown),
                0,
                keyboardType,
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { continue }
            let output = String(decoding: characters.prefix(Int(length)), as: UTF16.self)
            if output.lowercased() == "y" { return UInt32(keyCode) }
        }
        return nil
    }

    private static func errorMessage(for status: OSStatus) -> String {
        if status == OSStatus(eventHotKeyExistsErr) {
            return "Globaler Shortcut ⌘⇧Y ist bereits belegt."
        }
        return "Globaler Shortcut ⌘⇧Y konnte nicht eingerichtet werden (Fehler \(status))."
    }
}

private func globalHotKeyEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    var identifier = EventHotKeyID(signature: 0, id: 0)
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr else { return status }
    guard identifier.signature == 0x4D54484B, identifier.id == 1 else {
        return OSStatus(eventNotHandledErr)
    }
    let kind = GetEventKind(event)
    Task { @MainActor in
        hotKey.handle(kind: kind, identifier: identifier)
    }
    return noErr
}

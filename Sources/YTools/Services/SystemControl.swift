import AppKit
import AudioToolbox
import Carbon
import CoreAudio

/// Fixed, public-API system controls used by the system commands. Nothing
/// here accepts user text as a command, path or argument.
enum SystemAudio {
    private static func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private static func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    static func isMuted() -> Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = outputAddress(kAudioDevicePropertyMute)
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    @discardableResult
    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = outputAddress(kAudioDevicePropertyMute)
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    /// Sets the virtual main volume (0–100) and unmutes when raising it.
    @discardableResult
    static func setVolume(percent: Int) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        var address = outputAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var value = Float32(min(max(percent, 0), 100)) / 100
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        guard status == noErr else { return false }
        setMuted(percent == 0)
        return true
    }
}

enum PowerAction {
    case sleep
    case restart
    case shutDown

    // Apple Event codes from AERegistry.h (kCoreEventClass, kAESleep, kAERestart, kAEShutDown).
    private static let coreEventClass: AEEventClass = 0x61657674 // 'aevt'

    private var eventID: AEEventID {
        switch self {
        case .sleep: 0x736C6570 // 'slep'
        case .restart: 0x72657374 // 'rest'
        case .shutDown: 0x73687574 // 'shut'
        }
    }

    var title: String {
        switch self {
        case .sleep: "睡眠"
        case .restart: "重新启动"
        case .shutDown: "关机"
        }
    }

    /// Asks loginwindow to perform the action; applications get the usual
    /// chance to save and quit.
    func perform() throws {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow")
        let event = NSAppleEventDescriptor(
            eventClass: Self.coreEventClass,
            eventID: eventID,
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )
        _ = try event.sendEvent(options: [.noReply], timeout: 10)
    }
}

enum DiskEjector {
    struct Outcome: Sendable {
        let ejected: [String]
        let failed: [String]
    }

    /// Ejectable, non-internal volumes (USB disks, SD cards, mounted images).
    static func ejectableVolumes() -> [URL] {
        let keys: [URLResourceKey] = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return volumes.filter { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            if values.volumeIsRootFileSystem == true { return false }
            return values.volumeIsEjectable == true || (values.volumeIsRemovable == true && values.volumeIsInternal != true)
        }
    }

    static func ejectAll() async -> Outcome {
        let volumes = ejectableVolumes()
        var ejected: [String] = []
        var failed: [String] = []
        for volume in volumes {
            let name = volume.lastPathComponent
            do {
                try await FileManager.default.unmountVolume(at: volume, options: [.allPartitionsAndEjectDisk, .withoutUI])
                ejected.append(name)
            } catch {
                failed.append(name)
            }
        }
        return Outcome(ejected: ejected, failed: failed)
    }
}

enum ScreenLock {
    /// Sends the standard ⌃⌘Q lock shortcut. Needs the Accessibility permission.
    @MainActor
    static func lock() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        PasteService.postKeyStroke(CGKeyCode(kVK_ANSI_Q), flags: [.maskCommand, .maskControl])
        return true
    }
}

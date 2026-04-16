import CoreGraphics
import AppKit
import Observation

// MARK: - CGS Private API Type Aliases
typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64

let kCGSSpaceAll: UInt32 = 0x7

// MARK: - CGS Private API Declarations
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: CGSConnectionID) -> CGSSpaceID

@_silgen_name("CGSGetNumberOfWorkspaces")
func CGSGetNumberOfWorkspaces(_ cid: CGSConnectionID, _ count: UnsafeMutablePointer<Int>) -> CGError

@_silgen_name("CGSCopySpaces")
func CGSCopySpaces(_ cid: CGSConnectionID, _ options: UInt32) -> CFArray?

@_silgen_name("CGSGetWindowWorkspace")
func CGSGetWindowWorkspace(_ cid: CGSConnectionID, _ wid: CGWindowID, _ workspace: UnsafeMutablePointer<CGSSpaceID>) -> CGError

// MARK: - Data Models
struct SpaceInfo: Identifiable {
    let id: CGSSpaceID
    let index: Int
    var appIcons: [NSImage]
    var appNames: [String]
}

// MARK: - SpacesManager
@Observable
final class SpacesManager {
    var spaces: [SpaceInfo] = []
    var activeSpaceID: CGSSpaceID = 0

    private var spaceChangeObserver: Any?
    private var appActivationObserver: Any?
    private var appDeactivationObserver: Any?
    private let cid: CGSConnectionID
    private var refreshTask: Task<Void, Never>?

    init() {
        cid = CGSMainConnectionID()
        refresh()
        startObserving()
    }

    func refresh() {
        guard let rawSpaces = CGSCopySpaces(cid, kCGSSpaceAll) as? [NSNumber] else {
            spaces = []
            return
        }

        let spaceIDs = rawSpaces.map { CGSSpaceID($0.uint64Value) }
        activeSpaceID = CGSGetActiveSpace(cid)

        let windowList = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        spaces = spaceIDs.enumerated().map { (index, spaceID) in
            let (icons, names) = appsOnSpace(spaceID: spaceID, windowList: windowList)
            return SpaceInfo(id: spaceID, index: index, appIcons: icons, appNames: names)
        }
    }

    private func appsOnSpace(spaceID: CGSSpaceID, windowList: [[String: Any]]) -> ([NSImage], [String]) {
        var seenPIDs = Set<pid_t>()
        var icons: [NSImage] = []
        var names: [String] = []

        for info in windowList {
            guard
                let wid = info[kCGWindowNumber as String] as? CGWindowID,
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                !seenPIDs.contains(ownerPID)
            else { continue }

            var windowSpaceID: CGSSpaceID = 0
            let err = CGSGetWindowWorkspace(cid, wid, &windowSpaceID)
            guard err == .success, windowSpaceID == spaceID else { continue }

            seenPIDs.insert(ownerPID)

            if let app = NSRunningApplication(processIdentifier: ownerPID),
               let icon = app.icon {
                icons.append(icon)
                names.append(app.localizedName ?? "")
            }

            if icons.count >= 3 { break }
        }

        return (icons, names)
    }

    private func startObserving() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.debouncedRefresh()
        }

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.debouncedRefresh()
        }

        appDeactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.debouncedRefresh()
        }
    }

    private func debouncedRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !Task.isCancelled {
                refresh()
            }
        }
    }

    func switchToSpace(at index: Int) {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else {
            return
        }

        let keyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard index < keyCodes.count else { return }

        let keyCode = keyCodes[index]
        let src = CGEventSource(stateID: .hidSystemState)

        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)

        down?.flags = .maskControl
        up?.flags = .maskControl

        down?.post(tap: .cghidEventTap)
        usleep(50_000)
        up?.post(tap: .cghidEventTap)
    }

    deinit {
        refreshTask?.cancel()
        if let obs = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = appActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = appDeactivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }
}

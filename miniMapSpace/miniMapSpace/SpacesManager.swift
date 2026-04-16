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

@_silgen_name("CGSCopySpaces")
func CGSCopySpaces(_ cid: CGSConnectionID, _ options: UInt32) -> CFArray?

/// Returns per-window space memberships:
/// [ { "ManagedSpaceID": NSNumber, "WindowID": NSNumber }, … ]
@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: UInt32, _ windowIDs: CFArray) -> CFArray?

/// Returns per-display space metadata including type and fullscreen PIDs:
/// [ { "Spaces": [ { "id64": NSNumber, "type": Int, "pid": pid_t? } ] } ]
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

// MARK: - Data Models
struct SpaceInfo: Identifiable {
    let id: CGSSpaceID
    let index: Int
    var appIcons: [NSImage]
    var appNames: [String]
    var isFullscreen: Bool
    var mainAppPID: pid_t?
}

// MARK: - SpacesManager
@Observable
final class SpacesManager {
    var spaces: [SpaceInfo] = []
    var activeSpaceID: CGSSpaceID = 0

    private var spaceChangeObserver: Any?
    private var appActivationObserver: Any?
    private var appLaunchObserver: Any?
    private var appTerminateObserver: Any?
    private let cid: CGSConnectionID
    private var refreshTask: Task<Void, Never>?

    init() {
        cid = CGSMainConnectionID()
        refresh()
        startObserving()
    }

    func refresh() {
        activeSpaceID = CGSGetActiveSpace(cid)

        // --- Step 1: parse CGSCopyManagedDisplaySpaces for type + fullscreen PIDs AND ordered spaces ---
        var spaceType: [CGSSpaceID: Int] = [:]          // spaceID → type
        var fullscreenPID: [CGSSpaceID: pid_t] = [:]    // spaceID → pid (fullscreen only)
        var orderedSpaceIDs: [CGSSpaceID] = []

        if let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] {
            for display in displays {
                guard let spaceList = display["Spaces"] as? [[String: Any]] else { continue }
                for info in spaceList {
                    guard let idNum = info["id64"] as? NSNumber else { continue }
                    let sid = CGSSpaceID(idNum.uint64Value)
                    orderedSpaceIDs.append(sid)

                    let type = info["type"] as? Int ?? 0
                    spaceType[sid] = type
                    if type == 4, let pid = info["pid"] as? pid_t, pid > 0 {
                        fullscreenPID[sid] = pid
                    }
                }
            }
        }

        // If it failed to get via managed display spaces, fallback to raw spaces
        if orderedSpaceIDs.isEmpty, let rawSpaces = CGSCopySpaces(cid, kCGSSpaceAll) as? [NSNumber] {
             orderedSpaceIDs = rawSpaces.map { CGSSpaceID($0.uint64Value) }
        }

        // --- Step 2: map windows → spaces (for regular desktop spaces) ---
        // Use .optionAll to get windows on ALL spaces, filter to layer == 0 only
        var spaceToPIDs: [CGSSpaceID: Set<pid_t>] = [:]

        if let allWindowsRaw = CGWindowListCopyWindowInfo(
            [.optionAll, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] {

            // Build windowID → PID (layer 0 = normal app windows)
            var windowToPID: [CGWindowID: pid_t] = [:]
            for info in allWindowsRaw {
                guard
                    let wid   = info[kCGWindowNumber as String] as? CGWindowID,
                    let pid   = info[kCGWindowOwnerPID as String] as? pid_t,
                    let layer = info[kCGWindowLayer as String] as? Int,
                    layer == 0, pid > 0
                else { continue }
                windowToPID[wid] = pid
            }

            // Ask CGS which space(s) each window lives on
            let widArray = windowToPID.keys.map { NSNumber(value: $0) } as CFArray

            if let mappings = CGSCopySpacesForWindows(cid, kCGSSpaceAll, widArray) as? [[String: Any]] {

                // First pass: collect ALL space memberships per window
                var windowToSpaces: [CGWindowID: Set<CGSSpaceID>] = [:]
                for m in mappings {
                    guard
                        let spaceNum = m["ManagedSpaceID"] as? NSNumber,
                        let widNum   = m["WindowID"] as? NSNumber
                    else { continue }
                    let sid = CGSSpaceID(spaceNum.uint64Value)
                    let wid = CGWindowID(widNum.uint32Value)
                    windowToSpaces[wid, default: []].insert(sid)
                }

                // Second pass: only include windows that live on EXACTLY one space.
                // Windows on multiple spaces are "All Spaces" overlays → skip them.
                for (wid, sids) in windowToSpaces {
                    guard sids.count == 1, let sid = sids.first else { continue }
                    guard let pid = windowToPID[wid] else { continue }
                    spaceToPIDs[sid, default: []].insert(pid)
                }
            }
        }

        // --- Step 3: build SpaceInfo list ---
        spaces = orderedSpaceIDs.enumerated().map { (index, spaceID) in
            let isFullscreen = spaceType[spaceID] == 4

            var icons: [NSImage] = []
            var names: [String]  = []
            var mainPID: pid_t?

            if isFullscreen {
                // For fullscreen spaces, macOS gives us the PID directly
                if let pid = fullscreenPID[spaceID],
                   let app = NSRunningApplication(processIdentifier: pid),
                   let icon = app.icon {
                    mainPID = pid
                    icons = [icon]
                    names = [app.localizedName ?? "Unknown"]
                }
            } else {
                // Regular desktop space — use window-mapped PIDs
                let pids = spaceToPIDs[spaceID] ?? []
                for pid in pids {
                    guard
                        let app  = NSRunningApplication(processIdentifier: pid),
                        let icon = app.icon,
                        app.activationPolicy == .regular
                    else { continue }
                    
                    if mainPID == nil { mainPID = pid }
                    
                    icons.append(icon)
                    names.append(app.localizedName ?? "Unknown")
                    if icons.count >= 1 { break }
                }
            }

            return SpaceInfo(
                id: spaceID,
                index: index,
                appIcons: icons,
                appNames: names,
                isFullscreen: isFullscreen,
                mainAppPID: mainPID
            )
        }
    }

    private func startObserving() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.debouncedRefresh() }

        appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.debouncedRefresh() }

        appLaunchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.debouncedRefresh() }

        appTerminateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.debouncedRefresh() }
    }

    private func debouncedRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if !Task.isCancelled {
                await MainActor.run { refresh() }
            }
        }
    }

    func switchToSpace(at index: Int) {
        guard index < spaces.count else { return }
        let space = spaces[index]
        
        // Primary strategy: Let macOS switch space automatically by activating the app
        if let pid = space.mainAppPID,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: .activateIgnoringOtherApps)
            // Stop here since opening the app will automatically slide to its space
            return
        }

        // Fallback strategy: empty space switch via Keyboard shortcut simulation
        let prompt = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        let opts = [prompt: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(opts) else { return }

        let keyCodes: [CGKeyCode] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard index < keyCodes.count else { return }

        let keyCode = keyCodes[index]
        let src = CGEventSource(stateID: .hidSystemState)

        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)

        down?.flags = .maskControl
        up?.flags   = .maskControl

        down?.post(tap: .cghidEventTap)
        usleep(50_000)
        up?.post(tap: .cghidEventTap)
    }

    deinit {
        refreshTask?.cancel()
        [spaceChangeObserver, appActivationObserver, appLaunchObserver, appTerminateObserver]
            .compactMap { $0 }
            .forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
}

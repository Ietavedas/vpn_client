import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let connectionManager: ConnectionManager
    private var cancellables = Set<AnyCancellable>()

    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        popover.contentSize = NSSize(width: 432, height: 680)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(connectionManager)
        )

        configureButton()
        bindStateChanges()
    }

    func showPanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePanel(_:))
        updateIcon(for: connectionManager.state)
    }

    private func bindStateChanges() {
        connectionManager.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateIcon(for: state)
            }
            .store(in: &cancellables)
    }

    @objc private func togglePanel(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateIcon(for state: ConnectionState) {
        guard let button = statusItem.button else { return }
        let symbolName = Self.symbolName(for: state)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "NaiveClient") {
            image.isTemplate = true
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = "NC"
        }
    }

    private static func symbolName(for state: ConnectionState) -> String {
        switch state {
        case .connected:
            return "network"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .error:
            return "exclamationmark.triangle"
        case .disconnected:
            return "network.slash"
        }
    }
}

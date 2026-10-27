import CoreGraphics
import Foundation
import GameController

enum PadButton: Hashable {
    case a, b, x, y
    case l1, r1, l2, r2
    /// Xbox Menu, PlayStation Options.
    case menu
    /// Xbox View, PlayStation Share/Create.
    case options
    /// Xbox button, PS button.
    case home
    case up, down, left, right
}

struct PadState {
    var pressed = Set<PadButton>()
    /// -1...1 on each axis, with up as positive y.
    var leftStick = CGPoint.zero
    var rightStick = CGPoint.zero
}

extension CGPoint {
    var magnitude: CGFloat { hypot(x, y) }
}

/// Reads every connected Xbox, PlayStation or MFi controller, including while another app is in front.
final class GamepadMonitor {
    var onConnect: ((String) -> Void)?
    var onDisconnect: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            // Turning on background events before the first controller connects can crash on macOS 12
            // (SDL hit this), so it's done here rather than at launch.
            GCController.shouldMonitorBackgroundEvents = true
            GamepadMonitor.configure(controller)
            self?.onConnect?(GamepadMonitor.name(of: controller))
        })
        observers.append(center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
            self?.onDisconnect?()
        })
        GCController.controllers().forEach(GamepadMonitor.configure)
    }

    var connectedName: String? {
        GCController.controllers().first(where: { $0.extendedGamepad != nil }).map(GamepadMonitor.name(of:))
    }

    /// Combines all controllers: a button counts if it's held on any of them, and each stick uses the most-pushed one.
    func state() -> PadState {
        var state = PadState()
        for controller in GCController.controllers() {
            guard let pad = controller.extendedGamepad else { continue }
            let buttons: [(PadButton, GCControllerButtonInput?)] = [
                (.a, pad.buttonA), (.b, pad.buttonB), (.x, pad.buttonX), (.y, pad.buttonY),
                (.l1, pad.leftShoulder), (.r1, pad.rightShoulder), (.l2, pad.leftTrigger), (.r2, pad.rightTrigger),
                (.menu, pad.buttonMenu), (.options, pad.buttonOptions), (.home, pad.buttonHome),
                (.up, pad.dpad.up), (.down, pad.dpad.down), (.left, pad.dpad.left), (.right, pad.dpad.right)
            ]
            for (button, input) in buttons where input?.isPressed == true {
                state.pressed.insert(button)
            }
            let left = CGPoint(x: CGFloat(pad.leftThumbstick.xAxis.value), y: CGFloat(pad.leftThumbstick.yAxis.value))
            let right = CGPoint(x: CGFloat(pad.rightThumbstick.xAxis.value), y: CGFloat(pad.rightThumbstick.yAxis.value))
            if left.magnitude > state.leftStick.magnitude { state.leftStick = left }
            if right.magnitude > state.rightStick.magnitude { state.rightStick = right }
        }
        return state
    }

    private static func configure(_ controller: GCController) {
        // While MacHome is in front, keep the Home button for MacHome instead of letting it open Launchpad.
        controller.extendedGamepad?.buttonHome?.preferredSystemGestureState = .disabled
    }

    private static func name(of controller: GCController) -> String {
        controller.vendorName ?? controller.productCategory
    }
}

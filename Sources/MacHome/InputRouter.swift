import AppKit

/// What the gamepad is driving right now.
enum InputContext {
    case launcher
    case player(InputProfile)
    /// Another app, by bundle identifier.
    case external(String, InputProfile)
}

/// Polls the controllers 60 times a second and turns their state into home-screen navigation,
/// key presses or pointer movement, depending on what is in front.
final class InputRouter {
    private let gamepad: GamepadMonitor
    private let synth: EventSynth
    private unowned let app: AppController
    private var timer: Timer?
    private var lastTick: TimeInterval = 0
    private var previous = Set<PadButton>()
    private var heldDirections = Set<Direction>()
    private var nextRepeat: [Direction: TimeInterval] = [:]
    private var stickDirection: Direction?
    private var chordActive = false
    private var scrollRemainder = CGVector.zero
    private var lastTilt = CGSize.zero
    private var hasAccess = false
    private var lastAccessCheck: TimeInterval = -100
    private var lastAccessWarning: TimeInterval = -100
    private var accessPrompted = false

    init(gamepad: GamepadMonitor, synth: EventSynth, app: AppController) {
        self.gamepad = gamepad
        self.synth = synth
        self.app = app
    }

    func start() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastTick == 0 ? 1.0 / 60.0 : min(now - lastTick, 0.1)
        lastTick = now

        let state = gamepad.state()
        let pressed = state.pressed
        let down = pressed.subtracting(previous)
        let released = previous.subtracting(pressed)
        previous = pressed

        // Home: the controller's Home button, or View and Menu together. The chord also works when
        // the Home button is taken by macOS (it opens Launchpad while another app is in front).
        if pressed.contains(.menu) && pressed.contains(.options) && !chordActive {
            chordActive = true
            goHome()
            return
        }
        if chordActive {
            if !pressed.contains(.menu) && !pressed.contains(.options) { chordActive = false }
            return
        }
        if down.contains(.home) {
            goHome()
            return
        }

        let context = app.inputContext()
        switch context {
        case .launcher:
            driveLauncher(state, down: down, now: now)
        case .player(let profile):
            if released.contains(.options) { app.toggleProfile() }
            drive(state, down: down, released: released, profile: profile, toPlayer: true, now: now, dt: dt)
        case .external(_, let profile):
            if released.contains(.options) { app.toggleProfile() }
            drive(state, down: down, released: released, profile: profile, toPlayer: false, now: now, dt: dt)
        }
    }

    private func goHome() {
        heldDirections = []
        nextRepeat = [:]
        stickDirection = nil
        scrollRemainder = .zero
        releaseMouseButtons()
        app.goHome()
    }

    // MARK: - Home screen

    private func driveLauncher(_ state: PadState, down: Set<PadButton>, now: TimeInterval) {
        releaseMouseButtons()
        let directions = currentDirections(state, stickNavigates: true)
        repeatDirections(directions, now: now) { self.app.launcher.move($0) }
        updateTilt(stickDirection == nil ? state.leftStick : .zero)
        if down.contains(.a) {
            app.launcher.activateFocused()
        }
        if !directions.isEmpty || !down.isEmpty {
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func updateTilt(_ stick: CGPoint) {
        let tilt = stick.magnitude > 0.1 ? CGSize(width: stick.x, height: stick.y) : .zero
        let changed = abs(tilt.width - lastTilt.width) > 0.04 || abs(tilt.height - lastTilt.height) > 0.04
        if changed || (tilt == .zero && lastTilt != .zero) {
            lastTilt = tilt
            app.launcher.tilt = tilt
        }
    }

    // MARK: - Apps

    private func drive(_ state: PadState, down: Set<PadButton>, released: Set<PadButton>,
                       profile: InputProfile, toPlayer: Bool, now: TimeInterval, dt: TimeInterval) {
        updateTilt(.zero)
        if profile == .native {
            releaseMouseButtons()
            heldDirections = []
            stickDirection = nil
            return
        }
        let pointer = profile == .pointer
        let directions = currentDirections(state, stickNavigates: !pointer)
        repeatDirections(directions, now: now) { self.press($0.key, toPlayer: toPlayer) }

        if pointer {
            movePointer(state.leftStick, dt: dt)
            if down.contains(.a) { setMouseButton(.left, down: true) }
            if released.contains(.a) { setMouseButton(.left, down: false) }
            if down.contains(.r2) { setMouseButton(.right, down: true) }
            if released.contains(.r2) { setMouseButton(.right, down: false) }
        } else {
            releaseMouseButtons()
            if down.contains(.a) { press(.enter, toPlayer: toPlayer) }
        }
        if down.contains(.b) { press(.escape, toPlayer: toPlayer) }
        if down.contains(.x) { press(.space, toPlayer: toPlayer) }
        if !toPlayer {
            if down.contains(.y) { press(.fullScreen, toPlayer: false) }
            if down.contains(.l1) { press(.back, toPlayer: false) }
            if down.contains(.r1) { press(.forward, toPlayer: false) }
        }
        scroll(state.rightStick, dt: dt, toPlayer: toPlayer)
    }

    private func press(_ key: SynthKey, toPlayer: Bool) {
        if toPlayer, let player = app.player {
            player.sendKey(key)
        } else if ensureAccess() {
            synth.tap(key)
        }
    }

    private func movePointer(_ stick: CGPoint, dt: TimeInterval) {
        let magnitude = stick.magnitude
        guard magnitude > 0.15, ensureAccess() else { return }
        // Squared response: fine control near the centre, about 1.2 seconds across the screen at full tilt.
        let strength = (magnitude - 0.15) / 0.85
        let speed = strength * strength * CGDisplayBounds(CGMainDisplayID()).width * 0.8
        let step = speed * CGFloat(dt) / magnitude
        synth.movePointer(by: CGVector(dx: stick.x * step, dy: -stick.y * step))
    }

    private func scroll(_ stick: CGPoint, dt: TimeInterval, toPlayer: Bool) {
        let magnitude = stick.magnitude
        guard magnitude > 0.2 else {
            scrollRemainder = .zero
            return
        }
        let strength = (magnitude - 0.2) / 0.8
        let step = strength * strength * 2400 * CGFloat(dt) / magnitude
        scrollRemainder.dx -= stick.x * step
        scrollRemainder.dy += stick.y * step
        let dx = Int32(scrollRemainder.dx)
        let dy = Int32(scrollRemainder.dy)
        guard dx != 0 || dy != 0 else { return }
        scrollRemainder.dx -= CGFloat(dx)
        scrollRemainder.dy -= CGFloat(dy)
        if toPlayer, let player = app.player {
            player.scroll(dx: dx, dy: dy)
        } else if ensureAccess() {
            synth.scroll(dx: dx, dy: dy)
        }
    }

    private func setMouseButton(_ button: CGMouseButton, down: Bool) {
        // Ignore releases of presses that started elsewhere, such as the A press that opened this app.
        if !down && !(button == .left ? synth.leftDown : synth.rightDown) { return }
        guard ensureAccess() else { return }
        synth.setButton(button, down: down)
    }

    private func releaseMouseButtons() {
        if synth.leftDown { synth.setButton(.left, down: false) }
        if synth.rightDown { synth.setButton(.right, down: false) }
    }

    /// Posting events to other apps needs Accessibility access. Ask once, then remind now and then.
    private func ensureAccess() -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastAccessCheck > 2 {
            hasAccess = synth.hasSystemAccess
            lastAccessCheck = now
        }
        if hasAccess { return true }
        if !accessPrompted {
            accessPrompted = true
            synth.requestSystemAccess()
        }
        if now - lastAccessWarning > 8 {
            lastAccessWarning = now
            app.toast.show("Allow MacHome in System Preferences › Security & Privacy › Accessibility",
                           symbol: "lock.fill", duration: 5)
        }
        return false
    }

    // MARK: - Directions

    private func currentDirections(_ state: PadState, stickNavigates: Bool) -> Set<Direction> {
        var directions = Set<Direction>()
        if state.pressed.contains(.up) { directions.insert(.up) }
        if state.pressed.contains(.down) { directions.insert(.down) }
        if state.pressed.contains(.left) { directions.insert(.left) }
        if state.pressed.contains(.right) { directions.insert(.right) }
        if stickNavigates {
            stickDirection = InputRouter.direction(of: state.leftStick, current: stickDirection)
            if let direction = stickDirection { directions.insert(direction) }
        } else {
            stickDirection = nil
        }
        return directions
    }

    /// Fires once on press, then repeats while held, like a keyboard.
    private func repeatDirections(_ directions: Set<Direction>, now: TimeInterval, action: (Direction) -> Void) {
        for direction in Direction.allCases where directions.contains(direction) {
            if !heldDirections.contains(direction) {
                action(direction)
                nextRepeat[direction] = now + 0.4
            } else if let due = nextRepeat[direction], now >= due {
                action(direction)
                nextRepeat[direction] = now + 0.1
            }
        }
        heldDirections = directions
    }

    /// Treats the stick as a d-pad, with a lower release threshold than press threshold so it doesn't flicker.
    private static func direction(of stick: CGPoint, current: Direction?) -> Direction? {
        if let current = current {
            let along: CGFloat
            switch current {
            case .left: along = -stick.x
            case .right: along = stick.x
            case .up: along = stick.y
            case .down: along = -stick.y
            }
            if along > 0.35 { return current }
        }
        guard max(abs(stick.x), abs(stick.y)) > 0.6 else { return nil }
        if abs(stick.x) > abs(stick.y) {
            return stick.x > 0 ? .right : .left
        }
        return stick.y > 0 ? .up : .down
    }
}

private extension Direction {
    var key: SynthKey {
        switch self {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        }
    }
}

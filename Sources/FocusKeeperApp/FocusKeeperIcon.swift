import AppKit

enum FocusKeeperIcon {
    enum MenuState {
        case idle
        case active
        case paused
        case error
        case pending
    }

    static func menuBarImage(state: MenuState = .idle) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let crescent = NSBezierPath()
        crescent.appendArc(
            withCenter: NSPoint(x: 8.0, y: 9.4),
            radius: 5.3,
            startAngle: 96,
            endAngle: 266,
            clockwise: false
        )
        crescent.appendArc(
            withCenter: NSPoint(x: 10.2, y: 9.7),
            radius: 4.1,
            startAngle: 262,
            endAngle: 100,
            clockwise: true
        )
        crescent.close()
        crescent.fill()

        let pinHead = NSBezierPath(ovalIn: NSRect(x: 10.9, y: 10.9, width: 3.9, height: 3.9))
        pinHead.lineWidth = 1.35
        pinHead.stroke()

        let pinNeedle = NSBezierPath()
        pinNeedle.move(to: NSPoint(x: 12.8, y: 10.8))
        pinNeedle.line(to: NSPoint(x: 10.7, y: 5.5))
        pinNeedle.lineWidth = state == .active ? 1.85 : 1.55
        pinNeedle.lineCapStyle = .round
        pinNeedle.stroke()

        let pinPoint = NSBezierPath()
        pinPoint.move(to: NSPoint(x: 10.7, y: 5.5))
        pinPoint.line(to: NSPoint(x: 9.8, y: 3.8))
        pinPoint.lineWidth = 1.25
        pinPoint.lineCapStyle = .round
        pinPoint.stroke()

        switch state {
        case .idle:
            break
        case .active:
            let mark = NSBezierPath(ovalIn: NSRect(x: 5.9, y: 8.0, width: 2.4, height: 2.4))
            mark.fill()
        case .paused:
            NSBezierPath(rect: NSRect(x: 4.4, y: 5.8, width: 1.4, height: 4.2)).fill()
            NSBezierPath(rect: NSRect(x: 7.0, y: 5.8, width: 1.4, height: 4.2)).fill()
        case .error:
            let alert = NSBezierPath()
            alert.move(to: NSPoint(x: 5.8, y: 12.3))
            alert.line(to: NSPoint(x: 3.3, y: 7.6))
            alert.line(to: NSPoint(x: 8.3, y: 7.6))
            alert.close()
            alert.lineWidth = 1.05
            alert.stroke()
        case .pending:
            let clock = NSBezierPath(ovalIn: NSRect(x: 3.2, y: 6.5, width: 5.5, height: 5.5))
            clock.lineWidth = 1.05
            clock.stroke()
            let hand = NSBezierPath()
            hand.move(to: NSPoint(x: 5.95, y: 9.25))
            hand.line(to: NSPoint(x: 5.95, y: 10.8))
            hand.move(to: NSPoint(x: 5.95, y: 9.25))
            hand.line(to: NSPoint(x: 7.0, y: 8.7))
            hand.lineWidth = 0.95
            hand.lineCapStyle = .round
            hand.stroke()
        }

        image.isTemplate = true
        image.accessibilityDescription = "FocusKeeper"
        return image
    }
}

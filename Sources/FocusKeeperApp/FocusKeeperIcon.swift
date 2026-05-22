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
            withCenter: NSPoint(x: 7.9, y: 9.2),
            radius: 6.1,
            startAngle: 92,
            endAngle: 268,
            clockwise: false
        )
        crescent.appendArc(
            withCenter: NSPoint(x: 10.4, y: 9.6),
            radius: 4.8,
            startAngle: 265,
            endAngle: 96,
            clockwise: true
        )
        crescent.close()
        crescent.fill()

        image.isTemplate = true
        image.accessibilityDescription = "FocusKeeper"
        return image
    }
}

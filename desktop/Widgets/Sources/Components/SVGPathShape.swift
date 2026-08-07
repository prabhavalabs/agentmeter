import SwiftUI

/// Renders one static SVG path-data string, scaled to fit the shape's rect.
/// Supports the command set used by the bundled brand marks:
/// M/m, L/l, H/h, V/v, C/c, S/s, Q/q, T/t, A/a, and Z/z.
struct SVGPathShape: Shape {
    let basePath: Path
    let viewBox: CGFloat

    init(basePath: Path, viewBox: CGFloat = 24) {
        self.basePath = basePath
        self.viewBox = viewBox
    }

    init(pathData: String, viewBox: CGFloat = 24) {
        self.init(basePath: SVGPathParser.path(for: pathData), viewBox: viewBox)
    }

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / viewBox
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: scale, y: scale)
        return basePath.applying(transform)
    }
}

enum SVGPathParser {
    static func path(for data: String) -> Path {
        parse(data)
    }

    private struct Scanner {
        let characters: [Character]
        var index = 0

        init(_ text: String) {
            characters = Array(text)
        }

        mutating func nextCommand() -> Character? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let character = characters[index]
            guard character.isLetter else { return nil }
            index += 1
            return character
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            var text = ""
            if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                text.append(characters[index])
                index += 1
            }
            var seenDot = false
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    text.append(character)
                    index += 1
                } else if character == ".", seenDot == false {
                    seenDot = true
                    text.append(character)
                    index += 1
                } else if character == "e" || character == "E" {
                    text.append(character)
                    index += 1
                    if index < characters.count,
                       characters[index] == "-" || characters[index] == "+" {
                        text.append(characters[index])
                        index += 1
                    }
                } else {
                    break
                }
            }
            return Double(text).map { CGFloat($0) }
        }

        mutating func flag() -> Bool? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let character = characters[index]
            guard character == "0" || character == "1" else { return nil }
            index += 1
            return character == "1"
        }

        private mutating func skipSeparators() {
            while index < characters.count {
                let character = characters[index]
                if character == "," || character.isWhitespace {
                    index += 1
                } else {
                    break
                }
            }
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func parse(_ data: String) -> Path {
        var path = Path()
        var scanner = Scanner(data)
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var lastQuadControl: CGPoint?
        var command: Character?

        while true {
            if let next = scanner.nextCommand() {
                command = next
            } else if scanner.index >= scanner.characters.count {
                break
            }
            guard let active = command else { break }
            let relative = active.isLowercase

            switch Character(active.lowercased()) {
            case "m":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y)
                    : CGPoint(x: x, y: y)
                subpathStart = current
                path.move(to: current)
                lastControl = nil
                lastQuadControl = nil
                // Additional coordinate pairs after a move are implicit line-tos.
                command = relative ? "l" : "L"
            case "l":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y)
                    : CGPoint(x: x, y: y)
                path.addLine(to: current)
                lastControl = nil
                lastQuadControl = nil
            case "h":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
                lastQuadControl = nil
            case "v":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
                lastQuadControl = nil
            case "c":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let origin = relative ? current : .zero
                let control1 = CGPoint(x: origin.x + x1, y: origin.y + y1)
                let control2 = CGPoint(x: origin.x + x2, y: origin.y + y2)
                current = CGPoint(x: origin.x + x, y: origin.y + y)
                path.addCurve(to: current, control1: control1, control2: control2)
                lastControl = control2
                lastQuadControl = nil
            case "s":
                guard let x2 = scanner.number(), let y2 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let origin = relative ? current : .zero
                let control1 = lastControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                let control2 = CGPoint(x: origin.x + x2, y: origin.y + y2)
                current = CGPoint(x: origin.x + x, y: origin.y + y)
                path.addCurve(to: current, control1: control1, control2: control2)
                lastControl = control2
                lastQuadControl = nil
            case "q":
                guard let x1 = scanner.number(), let y1 = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let origin = relative ? current : .zero
                let control = CGPoint(x: origin.x + x1, y: origin.y + y1)
                current = CGPoint(x: origin.x + x, y: origin.y + y)
                path.addQuadCurve(to: current, control: control)
                lastQuadControl = control
                lastControl = nil
            case "t":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                let origin = relative ? current : .zero
                let control = lastQuadControl.map {
                    CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y)
                } ?? current
                current = CGPoint(x: origin.x + x, y: origin.y + y)
                path.addQuadCurve(to: current, control: control)
                lastQuadControl = control
                lastControl = nil
            case "a":
                guard let radiusX = scanner.number(), let radiusY = scanner.number(),
                      let rotation = scanner.number(),
                      let largeArc = scanner.flag(), let sweep = scanner.flag(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let origin = relative ? current : .zero
                let end = CGPoint(x: origin.x + x, y: origin.y + y)
                addArc(
                    to: &path,
                    from: current,
                    to: end,
                    radiusX: radiusX,
                    radiusY: radiusY,
                    rotationDegrees: rotation,
                    largeArc: largeArc,
                    sweep: sweep
                )
                current = end
                lastControl = nil
                lastQuadControl = nil
            case "z":
                path.closeSubpath()
                current = subpathStart
                lastControl = nil
                lastQuadControl = nil
            default:
                return path
            }
        }
        return path
    }

    /// Endpoint-to-center arc conversion per the SVG specification, emitted
    /// as cubic segments of at most 90 degrees each.
    // swiftlint:disable:next function_body_length
    private static func addArc(
        to path: inout Path,
        from start: CGPoint,
        to end: CGPoint,
        radiusX: CGFloat,
        radiusY: CGFloat,
        rotationDegrees: CGFloat,
        largeArc: Bool,
        sweep: Bool
    ) {
        var radiusX = abs(radiusX)
        var radiusY = abs(radiusY)
        guard radiusX > 0, radiusY > 0, start != end else {
            path.addLine(to: end)
            return
        }
        let rotation = rotationDegrees * .pi / 180
        let cosRotation = cos(rotation)
        let sinRotation = sin(rotation)
        let deltaX = (start.x - end.x) / 2
        let deltaY = (start.y - end.y) / 2
        let x1 = cosRotation * deltaX + sinRotation * deltaY
        let y1 = -sinRotation * deltaX + cosRotation * deltaY

        let lambda = (x1 * x1) / (radiusX * radiusX) + (y1 * y1) / (radiusY * radiusY)
        if lambda > 1 {
            let scale = sqrt(lambda)
            radiusX *= scale
            radiusY *= scale
        }

        let numerator = radiusX * radiusX * radiusY * radiusY
            - radiusX * radiusX * y1 * y1
            - radiusY * radiusY * x1 * x1
        let denominator = radiusX * radiusX * y1 * y1 + radiusY * radiusY * x1 * x1
        var factor = sqrt(max(0, numerator / denominator))
        if largeArc == sweep { factor = -factor }
        let centerX1 = factor * radiusX * y1 / radiusY
        let centerY1 = -factor * radiusY * x1 / radiusX
        let centerX = cosRotation * centerX1 - sinRotation * centerY1 + (start.x + end.x) / 2
        let centerY = sinRotation * centerX1 + cosRotation * centerY1 + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            guard length > 0 else { return 0 }
            var value = acos(min(max(dot / length, -1), 1))
            if ux * vy - uy * vx < 0 { value = -value }
            return value
        }

        let startAngle = angle(1, 0, (x1 - centerX1) / radiusX, (y1 - centerY1) / radiusY)
        var sweepAngle = angle(
            (x1 - centerX1) / radiusX,
            (y1 - centerY1) / radiusY,
            (-x1 - centerX1) / radiusX,
            (-y1 - centerY1) / radiusY
        )
        if sweep == false, sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep, sweepAngle < 0 { sweepAngle += 2 * .pi }

        let segmentCount = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let segmentAngle = sweepAngle / CGFloat(segmentCount)
        let control = 4 / 3 * tan(segmentAngle / 4)

        var currentAngle = startAngle
        for _ in 0..<segmentCount {
            let nextAngle = currentAngle + segmentAngle
            let cosCurrent = cos(currentAngle)
            let sinCurrent = sin(currentAngle)
            let cosNext = cos(nextAngle)
            let sinNext = sin(nextAngle)

            func absolute(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(
                    x: centerX + cosRotation * radiusX * x - sinRotation * radiusY * y,
                    y: centerY + sinRotation * radiusX * x + cosRotation * radiusY * y
                )
            }

            let from = absolute(cosCurrent, sinCurrent)
            let target = absolute(cosNext, sinNext)
            let control1 = absolute(
                cosCurrent - control * sinCurrent,
                sinCurrent + control * cosCurrent
            )
            let control2 = absolute(
                cosNext + control * sinNext,
                sinNext - control * cosNext
            )
            _ = from
            path.addCurve(to: target, control1: control1, control2: control2)
            currentAngle = nextAngle
        }
    }
}

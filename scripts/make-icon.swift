// Draws the app icon into Resources/AppIcon.icns, and the menu bar icon. Run it again only when the
// design changes: the .icns is committed, so a build does not need it.
//
//     swift scripts/make-icon.swift
//
// Dibuja el icono de la app en Resources/AppIcon.icns, y el de la barra de menús. Solo hay que volver a
// ejecutarlo si cambia el diseño: el .icns está en el repo, así que compilar
// no lo necesita.
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

/// The brand symbol, in the 512-point space of the SVGs in `brand/` (y down):
/// two arrows going round a bolt, the account switching over.
/// El símbolo de la marca, en el espacio de 512 puntos de los SVG de `brand/`
/// (y hacia abajo): dos flechas que giran alrededor de un rayo, la cuenta que cambia.
enum Symbol {
    static func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

    /// An SVG quadratic segment, as AppKit has only cubic ones.
    /// Un segmento cuadrático de SVG, porque AppKit solo tiene cúbicos.
    static func quad(_ path: NSBezierPath, _ control: NSPoint, _ end: NSPoint) {
        let start = path.currentPoint
        path.curve(
            to: end,
            controlPoint1: point(start.x + 2 / 3 * (control.x - start.x), start.y + 2 / 3 * (control.y - start.y)),
            controlPoint2: point(end.x + 2 / 3 * (control.x - end.x), end.y + 2 / 3 * (control.y - end.y))
        )
    }

    static var upperArc: NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point(98, 247))
        path.curve(to: point(254, 98), controlPoint1: point(101, 162), controlPoint2: point(170, 98))
        path.curve(to: point(391, 173), controlPoint1: point(311, 98), controlPoint2: point(361, 128))
        return path
    }

    static var lowerArc: NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point(419, 263))
        path.curve(to: point(262, 416), controlPoint1: point(416, 351), controlPoint2: point(348, 416))
        path.curve(to: point(122, 340), controlPoint1: point(204, 416), controlPoint2: point(152, 385))
        return path
    }

    static var upperHead: NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point(420, 141))
        quad(path, point(424, 138), point(424, 144))
        path.line(to: point(421, 209))
        quad(path, point(421, 214), point(416, 212))
        path.line(to: point(357, 192))
        quad(path, point(351, 190), point(356, 186))
        path.close()
        return path
    }

    static var lowerHead: NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point(98, 379))
        quad(path, point(94, 383), point(94, 377))
        path.line(to: point(97, 311))
        quad(path, point(97, 306), point(102, 308))
        path.line(to: point(162, 329))
        quad(path, point(167, 331), point(162, 334))
        path.close()
        return path
    }

    static var bolt: NSBezierPath {
        let path = NSBezierPath()
        path.move(to: point(253, 186))
        quad(path, point(258, 179), point(258, 188))
        path.line(to: point(258, 231))
        quad(path, point(258, 235), point(262, 235))
        path.line(to: point(306, 235))
        quad(path, point(313, 235), point(308, 242))
        path.line(to: point(255, 320))
        quad(path, point(250, 327), point(250, 319))
        path.line(to: point(250, 273))
        quad(path, point(250, 269), point(246, 269))
        path.line(to: point(201, 269))
        quad(path, point(195, 269), point(199, 263))
        path.close()
        return path
    }

    /// Draws the symbol into `rect`, the 512-point square it was drawn in.
    /// Dibuja el símbolo en `rect`, el cuadrado de 512 puntos en que se dibujó.
    static func draw(in rect: NSRect, upper: NSColor, lower: NSColor, stroke: CGFloat = 19) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.maxY)
        transform.scale(by: rect.width / 512)
        transform.scaleX(by: 1, yBy: -1)
        transform.concat()
        for (arc, ink) in [(upperArc, upper), (lowerArc, lower)] {
            arc.lineWidth = stroke
            arc.lineCapStyle = .round
            ink.setStroke()
            arc.stroke()
        }
        upper.setFill()
        upperHead.fill()
        lower.setFill()
        lowerHead.fill()
        bolt.fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// The app icon: the symbol on a charcoal tile.
/// El icono de la app: el símbolo sobre una pieza carbón.
func draw() {
    // The tile, on the macOS icon grid: 824 of 1024, with room for the shadow.
    // La pieza, en la rejilla de iconos de macOS: 824 de 1024, con sitio para la sombra.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    color(0x272C36).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0x2D323D), ending: color(0x272C36))!.draw(in: tilePath, angle: -90)
    Symbol.draw(in: tile, upper: color(0xD9DAE0), lower: color(0x48BE96))
}

/// The menu bar icon: the symbol in one ink, heavier so it reads at 16 points.
/// macOS paints it black or white to match the bar.
/// El icono de la barra de menús: el símbolo en una tinta, más grueso para que se
/// lea a 16 puntos. macOS lo pinta de negro o de blanco según la barra.
func drawMenuBar(points: CGFloat) {
    // The symbol spans x 86–434 and y 90–424 of its 512 square; fit that to 16 of 18 points.
    // El símbolo ocupa x 86–434 e y 90–424 de su cuadrado de 512; se ajusta a 16 de 18 puntos.
    let scale = 16 / 348 * points / 18
    let side = 512 * scale
    let rect = NSRect(x: points / 2 - 260 * scale, y: points / 2 - (512 - 257) * scale, width: side, height: side)
    Symbol.draw(in: rect, upper: .black, lower: .black, stroke: 34)
}

func png(size: Int, canvas: CGFloat = canvas, body: () -> Void = draw) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = CGFloat(size) / canvas
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
    body()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try png(size: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try png(size: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try png(size: 1024).write(to: resources.appendingPathComponent("AppIcon.png"))
for scale in [1, 2] {
    let name = scale == 1 ? "MenuBarIcon.png" : "MenuBarIcon@2x.png"
    try png(size: 18 * scale, canvas: 18) { drawMenuBar(points: 18) }.write(to: resources.appendingPathComponent(name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Resources/AppIcon.icns, Resources/MenuBarIcon.png")

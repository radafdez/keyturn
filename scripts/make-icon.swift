// Draws the app icon into Resources/AppIcon.icns. Run it again only when the
// design changes: the .icns is committed, so a build does not need it.
//
//     swift scripts/make-icon.swift
//
// Dibuja el icono de la app en Resources/AppIcon.icns. Solo hay que volver a
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

/// A dark tile with a switch turned on, and a terminal prompt in its track:
/// the CLI, one flick away from the right account.
/// Una pieza oscura con un interruptor encendido y un prompt de terminal en su
/// carril: el CLI, a un toque de la cuenta correcta.
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
    color(0x111714).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: color(0x26302B), ending: color(0x0C110F))!.draw(in: tilePath, angle: -90)
    color(0xFFFFFF, 0.08).setStroke()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 3, dy: 3), xRadius: 183, yRadius: 183)
    rim.lineWidth = 6
    rim.stroke()

    // The switch track. / El carril del interruptor.
    let track = NSRect(x: 192, y: 362, width: 640, height: 300)
    let trackPath = NSBezierPath(roundedRect: track, xRadius: 150, yRadius: 150)
    NSGradient(starting: color(0x4BE09C), ending: color(0x1F9E66))!.draw(in: trackPath, angle: -90)
    color(0xFFFFFF, 0.18).setStroke()
    let trackRim = NSBezierPath(roundedRect: track.insetBy(dx: 2, dy: 2), xRadius: 148, yRadius: 148)
    trackRim.lineWidth = 4
    trackRim.stroke()

    // The prompt, `>_`, on the left of the track. / El prompt, `>_`, a la izquierda del carril.
    let ink = color(0x07301E, 0.9)
    ink.setStroke()
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: 300, y: 568))
    chevron.line(to: NSPoint(x: 372, y: 512))
    chevron.line(to: NSPoint(x: 300, y: 456))
    chevron.lineWidth = 36
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.stroke()
    let underscore = NSBezierPath()
    underscore.move(to: NSPoint(x: 410, y: 452))
    underscore.line(to: NSPoint(x: 500, y: 452))
    underscore.lineWidth = 36
    underscore.lineCapStyle = .round
    underscore.stroke()

    // The knob, switched to the right. / La perilla, a la derecha.
    let knob = NSRect(x: 552, y: 382, width: 260, height: 260)
    NSGraphicsContext.saveGraphicsState()
    let knobShadow = NSShadow()
    knobShadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    knobShadow.shadowOffset = NSSize(width: 0, height: -8)
    knobShadow.shadowBlurRadius = 18
    knobShadow.set()
    color(0xF7FAF8).setFill()
    NSBezierPath(ovalIn: knob).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0xFFFFFF), ending: color(0xE3EAE6))!.draw(in: NSBezierPath(ovalIn: knob), angle: -90)
}

func png(size: Int) -> Data {
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
    draw()
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

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Resources/AppIcon.icns")

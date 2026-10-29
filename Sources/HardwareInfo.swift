import AppKit
import ColorSync
import CoreGraphics

struct ChromaticityPoint: Equatable {
    let x: Double
    let y: Double
}

struct DisplayDescriptor: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let widthPoints: Double
    let heightPoints: Double
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Double
    let refreshRate: Double
    let profileName: String
    let primaries: [ChromaticityPoint]
    let whitePoint: ChromaticityPoint?
    let srgbAreaPercent: Double
    let p3AreaPercent: Double
    let adobeRGBAreaPercent: Double
    let isMain: Bool

    var resolutionText: String {
        "\(pixelWidth) × \(pixelHeight)"
    }

    var logicalResolutionText: String {
        "\(Int(widthPoints)) × \(Int(heightPoints)) pt"
    }

    var refreshText: String {
        refreshRate > 0 ? String(format: "%.0f Hz", refreshRate) : "--"
    }

    var gamutName: String {
        if p3AreaPercent >= 95 { return "Display P3" }
        if srgbAreaPercent >= 97 { return "sRGB" }
        return "自定义色域"
    }

    var gamutSummary: String {
        "sRGB \(Int(srgbAreaPercent.rounded()))% · P3 \(Int(p3AreaPercent.rounded()))%"
    }

    var srgbTriangle: [ChromaticityPoint] {
        [ChromaticityPoint(x: 0.640, y: 0.330),
         ChromaticityPoint(x: 0.300, y: 0.600),
         ChromaticityPoint(x: 0.150, y: 0.060)]
    }

    var p3Triangle: [ChromaticityPoint] {
        [ChromaticityPoint(x: 0.680, y: 0.320),
         ChromaticityPoint(x: 0.265, y: 0.690),
         ChromaticityPoint(x: 0.150, y: 0.060)]
    }

    var adobeTriangle: [ChromaticityPoint] {
        [ChromaticityPoint(x: 0.640, y: 0.330),
         ChromaticityPoint(x: 0.210, y: 0.710),
         ChromaticityPoint(x: 0.150, y: 0.060)]
    }
}

enum DisplayInfo {
    private static let srgbArea = triangleArea([
        ChromaticityPoint(x: 0.640, y: 0.330),
        ChromaticityPoint(x: 0.300, y: 0.600),
        ChromaticityPoint(x: 0.150, y: 0.060)
    ])
    private static let p3Area = triangleArea([
        ChromaticityPoint(x: 0.680, y: 0.320),
        ChromaticityPoint(x: 0.265, y: 0.690),
        ChromaticityPoint(x: 0.150, y: 0.060)
    ])
    private static let adobeArea = triangleArea([
        ChromaticityPoint(x: 0.640, y: 0.330),
        ChromaticityPoint(x: 0.210, y: 0.710),
        ChromaticityPoint(x: 0.150, y: 0.060)
    ])

    static func load() -> [DisplayDescriptor] {
        let mainID = CGMainDisplayID()
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = CGDirectDisplayID(number.uint32Value)
            let mode = CGDisplayCopyDisplayMode(id)
            let profile = profileData(for: id)
            let area = triangleArea(profile.primaries)
            let pixelWidth = mode?.pixelWidth ?? Int(screen.frame.width * screen.backingScaleFactor)
            let pixelHeight = mode?.pixelHeight ?? Int(screen.frame.height * screen.backingScaleFactor)
            let refresh = mode?.refreshRate ?? Double(screen.maximumFramesPerSecond)
            return DisplayDescriptor(
                id: id,
                name: screen.localizedName,
                widthPoints: Double(screen.frame.width),
                heightPoints: Double(screen.frame.height),
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                scale: Double(screen.backingScaleFactor),
                refreshRate: refresh,
                profileName: profile.name,
                primaries: profile.primaries,
                whitePoint: profile.whitePoint,
                srgbAreaPercent: area / srgbArea * 100.0,
                p3AreaPercent: area / p3Area * 100.0,
                adobeRGBAreaPercent: area / adobeArea * 100.0,
                isMain: id == mainID
            )
        }
    }

    private static func profileData(for id: CGDirectDisplayID) -> (name: String, primaries: [ChromaticityPoint], whitePoint: ChromaticityPoint?) {
        let fallback = (name: "Color LCD", primaries: [
            ChromaticityPoint(x: 0.640, y: 0.330),
            ChromaticityPoint(x: 0.300, y: 0.600),
            ChromaticityPoint(x: 0.150, y: 0.060)
        ], whitePoint: ChromaticityPoint(x: 0.3127, y: 0.3290))

        guard let unmanaged = ColorSyncProfileCreateWithDisplayID(id) else {
            return fallback
        }
        let profile = unmanaged.takeRetainedValue()
        var name = fallback.name
        if let description = ColorSyncProfileCopyDescriptionString(profile)?.takeRetainedValue() {
            name = description as String
        }

        let r = xyzTag(profile, signature: "rXYZ")
        let g = xyzTag(profile, signature: "gXYZ")
        let b = xyzTag(profile, signature: "bXYZ")
        let w = xyzTag(profile, signature: "wtpt")

        var primaries: [ChromaticityPoint] = []
        for value in [r, g, b] {
            guard let value else { return (name, fallback.primaries, fallback.whitePoint) }
            let sum = value.x + value.y + value.z
            guard sum > 0.000001 else { return (name, fallback.primaries, fallback.whitePoint) }
            primaries.append(ChromaticityPoint(x: value.x / sum, y: value.y / sum))
        }

        var whitePoint: ChromaticityPoint? = nil
        if let w {
            let sum = w.x + w.y + w.z
            if sum > 0.000001 {
                whitePoint = ChromaticityPoint(x: w.x / sum, y: w.y / sum)
            }
        }

        guard primaries.count == 3 else { return (name, fallback.primaries, fallback.whitePoint) }
        return (name, primaries, whitePoint ?? fallback.whitePoint)
    }

    private static func xyzTag(_ profile: ColorSyncProfile, signature: String) -> (x: Double, y: Double, z: Double)? {
        guard let unmanaged = ColorSyncProfileCopyTag(profile, signature as CFString) else {
            return nil
        }
        let data = unmanaged.takeRetainedValue() as Data
        guard data.count >= 20 else { return nil }
        return data.withUnsafeBytes { raw -> (Double, Double, Double)? in
            guard let base = raw.baseAddress else { return nil }
            func fixed(_ offset: Int) -> Double {
                let value = base.advanced(by: offset).load(as: Int32.self)
                return Double(Int32(bigEndian: value)) / 65536.0
            }
            return (fixed(8), fixed(12), fixed(16))
        }.map { (x: $0.0, y: $0.1, z: $0.2) }
    }

    private static func triangleArea(_ points: [ChromaticityPoint]) -> Double {
        guard points.count == 3 else { return 0 }
        let a = points[0], b = points[1], c = points[2]
        return abs(a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y)) / 2.0
    }
}

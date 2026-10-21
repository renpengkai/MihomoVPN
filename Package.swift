// swift-tools-version:5.9
import PackageDescription

// 体积优先: 界面与解析都不是热点, -Osize 与 -O 无可感知差别
let sizeFlags: [SwiftSetting] = [.unsafeFlags(["-Osize"], .when(configuration: .release))]

let package = Package(
    name: "MihomoVPN",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MihomoVPN", path: "Sources/MihomoVPN", swiftSettings: sizeFlags),
        .executableTarget(name: "mvpnhelper", path: "Sources/mvpnhelper", swiftSettings: sizeFlags),
    ]
)

// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BatteryBeacon", platforms: [.macOS(.v13)], products: [.executable(name: "BatteryBeacon", targets: ["BatteryBeacon"])], targets: [.executableTarget(name: "BatteryBeacon"), .testTarget(name: "BatteryBeaconTests", dependencies: ["BatteryBeacon"])])

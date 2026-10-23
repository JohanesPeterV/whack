// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Whack",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Whack", targets: ["Whack"]),
               .executable(name: "whack-check", targets: ["WhackCheck"]),
               .executable(name: "whack-tests", targets: ["WhackCoreTests"]),
               .executable(name: "whack-ui-tests", targets: ["WhackUITests"])],
    targets: [
        .target(name: "WhackCore", resources: [.copy("Sounds")]),
        .target(name: "WhackSensor", dependencies: ["WhackCore"]),
        .executableTarget(name: "Whack", dependencies: ["WhackCore", "WhackSensor"],
                          resources: [.copy("Resources/whack.png")]),
        .executableTarget(name: "WhackCheck", dependencies: ["WhackCore", "WhackSensor"]),
        // The command-line tools SDK lacks XCTest/Testing. This portable executable
        // runs the same regression suite without requiring a full Xcode installation.
        .executableTarget(name: "WhackCoreTests", dependencies: ["WhackCore"], path: "Tests/WhackCoreTests",
                          resources: [.copy("Fixtures")]),
        .executableTarget(name: "WhackUITests", path: "Tests/WhackUITests")
    ],
    swiftLanguageModes: [.v5]
)

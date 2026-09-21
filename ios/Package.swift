// swift-tools-version: 5.9
import PackageDescription

// うながすくんの iOS / macOS アプリ用。拡張機能の extension/logic.js をそのまま移した層。
// UI は持たない。ここが拡張と同じ答えを返すことを ../test/parity_test.mjs で突き合わせる。
let package = Package(
    name: "UnagasukunCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "UnagasukunCore", targets: ["UnagasukunCore"]),
    ],
    targets: [
        .target(name: "UnagasukunCore"),
        // JS版と答えを突き合わせるための入口。JSONを受けてJSONを返すだけ
        .executableTarget(name: "uk-probe", dependencies: ["UnagasukunCore"]),
        .testTarget(name: "UnagasukunCoreTests", dependencies: ["UnagasukunCore"]),
    ]
)

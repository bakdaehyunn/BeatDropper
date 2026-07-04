// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "BeatDropperNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "BeatDropperCore",
            targets: ["BeatDropperCore"]
        ),
        .executable(
            name: "BeatDropperNative",
            targets: ["BeatDropperNative"]
        ),
        .executable(
            name: "BeatDropperNativeAnalysisBenchmarks",
            targets: ["BeatDropperNativeAnalysisBenchmarks"]
        ),
        .executable(
            name: "BeatDropperNativePlannerBenchmarks",
            targets: ["BeatDropperNativePlannerBenchmarks"]
        ),
        .executable(
            name: "BeatDropperNativeLibraryStress",
            targets: ["BeatDropperNativeLibraryStress"]
        ),
        .executable(
            name: "BeatDropperNativeLoudnessValidation",
            targets: ["BeatDropperNativeLoudnessValidation"]
        )
    ],
    targets: [
        .target(
            name: "BeatDropperCore"
        ),
        .executableTarget(
            name: "BeatDropperNative",
            dependencies: ["BeatDropperCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "BeatDropperNativeAnalysisBenchmarks",
            dependencies: ["BeatDropperCore"]
        ),
        .executableTarget(
            name: "BeatDropperNativePlannerBenchmarks",
            dependencies: ["BeatDropperCore"]
        ),
        .executableTarget(
            name: "BeatDropperNativeLibraryStress",
            dependencies: ["BeatDropperCore"]
        ),
        .executableTarget(
            name: "BeatDropperNativeLoudnessValidation",
            dependencies: ["BeatDropperCore"],
            linkerSettings: [
                .linkedFramework("AVFoundation")
            ]
        ),
        .testTarget(
            name: "BeatDropperCoreTests",
            dependencies: ["BeatDropperCore"]
        )
    ]
)

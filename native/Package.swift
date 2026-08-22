// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "BeatDropperNative",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "BeatDropperDomain", targets: ["BeatDropperDomain"]),
        .library(name: "BeatDropperDSP", targets: ["BeatDropperDSP"]),
        .library(name: "BeatDropperLibrary", targets: ["BeatDropperLibrary"]),
        .library(name: "BeatDropperPlanning", targets: ["BeatDropperPlanning"]),
        .library(name: "BeatDropperReview", targets: ["BeatDropperReview"]),
        .library(name: "BeatDropperPlatform", targets: ["BeatDropperPlatform"]),
        .library(name: "BeatDropperApplication", targets: ["BeatDropperApplication"]),
        .library(name: "BeatDropperTestSupport", targets: ["BeatDropperTestSupport"]),
        .executable(
            name: "BeatDropperNative",
            targets: ["BeatDropperNativeApp"]
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
            name: "BeatDropperNativePlaybackStress",
            targets: ["BeatDropperNativePlaybackStress"]
        ),
        .executable(
            name: "BeatDropperNativeLoudnessValidation",
            targets: ["BeatDropperNativeLoudnessValidation"]
        ),
        .executable(
            name: "BeatDropperNativeAnalysisExtract",
            targets: ["BeatDropperNativeAnalysisExtract"]
        )
    ],
    targets: [
        .target(name: "BeatDropperDomain"),
        .target(
            name: "BeatDropperDSP",
            dependencies: ["BeatDropperDomain"]
        ),
        .target(
            name: "BeatDropperLibrary",
            dependencies: ["BeatDropperDomain"]
        ),
        .target(
            name: "BeatDropperReview",
            dependencies: ["BeatDropperDomain", "BeatDropperDSP"]
        ),
        .target(
            name: "BeatDropperPlanning",
            dependencies: ["BeatDropperDomain", "BeatDropperDSP", "BeatDropperLibrary", "BeatDropperReview"]
        ),
        .target(
            name: "BeatDropperTestSupport",
            dependencies: ["BeatDropperDomain", "BeatDropperDSP", "BeatDropperLibrary", "BeatDropperPlanning", "BeatDropperReview", "BeatDropperPlatform"]
        ),
        .target(
            name: "BeatDropperPlatform",
            dependencies: ["BeatDropperApplication", "BeatDropperDSP", "BeatDropperLibrary", "BeatDropperPlanning", "BeatDropperReview"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox")
            ]
        ),
        .target(
            name: "BeatDropperApplication",
            dependencies: ["BeatDropperDomain", "BeatDropperDSP", "BeatDropperLibrary", "BeatDropperPlanning", "BeatDropperReview"]
        ),
        .target(
            name: "BeatDropperNative",
            dependencies: ["BeatDropperApplication", "BeatDropperPlatform"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "BeatDropperNativeApp",
            dependencies: ["BeatDropperNative"]
        ),
        .executableTarget(
            name: "BeatDropperNativeAnalysisBenchmarks",
            dependencies: ["BeatDropperDomain", "BeatDropperTestSupport"]
        ),
        .executableTarget(
            name: "BeatDropperNativePlannerBenchmarks",
            dependencies: ["BeatDropperDomain", "BeatDropperDSP", "BeatDropperPlanning", "BeatDropperReview", "BeatDropperTestSupport"]
        ),
        .executableTarget(
            name: "BeatDropperNativeLibraryStress",
            dependencies: ["BeatDropperTestSupport"]
        ),
        .executableTarget(
            name: "BeatDropperNativePlaybackStress",
            dependencies: ["BeatDropperTestSupport"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation")
            ]
        ),
        .executableTarget(
            name: "BeatDropperNativeLoudnessValidation",
            dependencies: ["BeatDropperDomain", "BeatDropperDSP"],
            linkerSettings: [
                .linkedFramework("AVFoundation")
            ]
        ),
        .executableTarget(
            name: "BeatDropperNativeAnalysisExtract",
            dependencies: ["BeatDropperDomain", "BeatDropperDSP"],
            linkerSettings: [
                .linkedFramework("AVFoundation")
            ]
        ),
        .testTarget(
            name: "BeatDropperModuleTests",
            dependencies: ["BeatDropperDomain", "BeatDropperDSP", "BeatDropperLibrary", "BeatDropperPlanning", "BeatDropperReview", "BeatDropperPlatform", "BeatDropperTestSupport"],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox")
            ]
        ),
        .testTarget(
            name: "BeatDropperNativeTests",
            dependencies: ["BeatDropperNative", "BeatDropperApplication", "BeatDropperDomain", "BeatDropperDSP", "BeatDropperLibrary", "BeatDropperPlanning", "BeatDropperReview", "BeatDropperPlatform", "BeatDropperTestSupport"]
        )
    ]
)

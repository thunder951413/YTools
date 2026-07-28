// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "YTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "YToolsCore", targets: ["YToolsCore"]),
        .library(name: "YToolsModuleKit", targets: ["YToolsModuleKit"]),
        .executable(name: "YToolsCoreChecks", targets: ["YToolsCoreChecks"]),
        .executable(name: "YTools", targets: ["YTools"])
    ],
    targets: [
        .target(
            name: "YToolsCore",
            path: "Sources/YToolsCore"
        ),
        .target(
            name: "YToolsModuleKit",
            path: "Sources/YToolsModuleKit"
        ),
        .executableTarget(
            name: "YToolsCoreChecks",
            dependencies: ["YToolsCore", "YToolsModuleKit"],
            path: "Sources/YToolsCoreChecks"
        ),
        .executableTarget(
            name: "YTools",
            dependencies: ["YToolsCore", "YToolsModuleKit"],
            path: "Sources/YTools",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreServices"),
                .linkedFramework("QuickLookUI"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "YToolsTests",
            dependencies: ["YToolsCore", "YToolsModuleKit"],
            path: "Tests/YToolsTests"
        )
    ]
)

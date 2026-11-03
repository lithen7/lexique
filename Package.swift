// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lexique",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lexique", targets: ["Lexique"]),
        .executable(name: "lexique-probe", targets: ["Probe"])
    ],
    targets: [
        .target(
            name: "OpenMDict",
            path: "Vendor/OpenMDict/Sources/OpenMDict"
        ),
        .executableTarget(
            name: "Lexique",
            dependencies: ["OpenMDict"],
            path: "Sources/Lexique",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "Probe",
            dependencies: ["OpenMDict"],
            path: "Sources/Probe"
        )
    ]
)

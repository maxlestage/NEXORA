// swift-tools-version: 6.2
// Le cœur de l'application iOS NEXORA : fournisseurs d'IA, flux de réponses,
// GitHub, conversations. Sans interface : compile et se teste aussi sous Linux.
import PackageDescription

let package = Package(
    name: "NexoraKit",
    defaultLocalization: "fr",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NexoraKit", targets: ["NexoraKit"])
    ],
    targets: [
        .target(
            name: "NexoraKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "NexoraKitTests",
            dependencies: ["NexoraKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RedoApp",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "RedoCore",
            targets: ["RedoCore"]
        ),
        .library(
            name: "RedoCrypto",
            targets: ["RedoCrypto"]
        ),
        .library(
            name: "RedoUI",
            targets: ["RedoUI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk", from: "10.0.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0")
    ],
    targets: [
        // Core business logic
        .target(
            name: "RedoCore",
            dependencies: [
                "RedoCrypto"
            ]
        ),

        // Cryptography layer
        .target(
            name: "RedoCrypto",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),

        // UI layer
        .target(
            name: "RedoUI",
            dependencies: [
                "RedoCore",
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ]
        ),

        // Tests
        .testTarget(
            name: "RedoCoreTests",
            dependencies: ["RedoCore"]
        ),
        .testTarget(
            name: "RedoCryptoTests",
            dependencies: ["RedoCrypto"]
        )
    ]
)

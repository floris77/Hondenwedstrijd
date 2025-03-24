// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "Hondenwedstrijd",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "Hondenwedstrijd",
            targets: ["Hondenwedstrijd"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0")
    ],
    targets: [
        .target(
            name: "Hondenwedstrijd",
            dependencies: ["SwiftSoup"]),
        .testTarget(
            name: "HondenwedstrijdTests",
            dependencies: ["Hondenwedstrijd"]),
    ]
) 
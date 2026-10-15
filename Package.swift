// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cpin",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Cpin", targets: ["Cpin"]),
        .library(name: "CpinCore", targets: ["CpinCore"])
    ],
    targets: [
        .target(name: "CpinCore"),
        .executableTarget(name: "Cpin", dependencies: ["CpinCore"]),
        .testTarget(name: "CpinCoreTests", dependencies: ["CpinCore"], exclude: ["StandaloneChecks.swift"])
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QBSKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "QBSCore", targets: ["QBSCore"]),
        .executable(name: "QuizBowlStatkeeper", targets: ["QuizBowlStatkeeper"]),
    ],
    targets: [
        .target(name: "QBSCore"),
        .executableTarget(name: "QuizBowlStatkeeper", dependencies: ["QBSCore"], path: "Sources/QBSApp"),
    ]
)

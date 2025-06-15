// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GoAiPoiIOS",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "GoAiPoiIOS",
            targets: ["GoAiPoiIOS"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "GoAiPoiIOS",
            dependencies: []
        )
    ]
)

// swift-tools-version:5.10
import PackageDescription

// Resources (card.html, exercises.json, figures/) live in app/Resources and are
// copied into the .app bundle by scripts/build-app.sh, not managed by SwiftPM.
let package = Package(
    name: "ClaudePosture",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "ClaudePosture", path: "Sources/ClaudePosture")
    ]
)

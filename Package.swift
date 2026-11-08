// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MacWorkspaces",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacWorkspaces", targets: ["MacWorkspaces"]),
        .library(name: "MacWorkspacesCore", targets: ["MacWorkspacesCore"]),
    ],
    targets: [
        .target(name: "MacWorkspacesCore"),
        .executableTarget(
            name: "MacWorkspaces",
            dependencies: ["MacWorkspacesCore"]
        ),
        .testTarget(
            name: "MacWorkspacesCoreTests",
            dependencies: ["MacWorkspacesCore"]
        ),
    ]
)

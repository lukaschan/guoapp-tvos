// swift-tools-version: 6.0
// 纯逻辑测试包：tvOS 应用里 Core/Logic 下的文件只依赖 Foundation，同一份源码既编进应用，
// 也编进这里的 GuoAppLogic 目标，在 Mac 上用 `swift test --package-path tvos` 跑单元测试。
// Xcode 工程（GuoAppTV.xcodeproj）不引用本包。
import PackageDescription

let package = Package(
    name: "GuoAppLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GuoAppLogic", path: "GuoAppTV/GuoAppTV/Core/Logic"),
        .testTarget(name: "GuoAppLogicTests", dependencies: ["GuoAppLogic"], path: "LogicTests"),
    ]
)

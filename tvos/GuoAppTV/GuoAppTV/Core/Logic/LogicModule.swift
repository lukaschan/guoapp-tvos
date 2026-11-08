// Core/Logic：纯规则（选集分段、观看状态、续播目标、系列分组），只依赖 Foundation。
// 这些文件同时编进应用和 tvos/Package.swift 的 GuoAppLogic 测试包；不要在这里引用 SwiftUI / UIKit /
// CoreClient，否则 Mac 上的单元测试无法编译。

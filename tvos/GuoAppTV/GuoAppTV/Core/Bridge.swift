import Foundation

/// Swift 侧对 Go 核心 C ABI 的薄封装（见 native/bridge/main.go）。
///
/// Go 侧只暴露两个函数：`DuanjuRequest` 收一个 UTF-8 JSON 字符串，
/// 返回新分配的 UTF-8 JSON 字符串；调用方必须用 `DuanjuFree` 释放。
/// 头文件由构建脚本生成到 GuoAppTV/DuanjuCore.h，见 scripts/build_tvos.py。
enum DuanjuBridge {
    static func request(_ json: String) throws -> String {
        guard let cInput = strdup(json) else {
            throw CoreError.transport("无法分配请求内存")
        }
        defer { free(cInput) }
        guard let cOutput = DuanjuRequest(cInput) else {
            throw CoreError.transport("本地核心没有返回结果")
        }
        defer { DuanjuFree(cOutput) }
        return String(cString: cOutput)
    }
}

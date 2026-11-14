import Foundation

/// 核心的本机播放服务（Go 核心在 127.0.0.1 随机端口上起的 HTTP 服务，播放地址都指向它，
/// 见 upstream/native/core/app_stream.go 的 newNativeStreamServer）。
/// 它只在核心里创建一次；App 被系统挂起（电视休眠）后监听的套接字可能被回收，之后任何一集都连不上。
/// 这里只负责认出这个地址、探一下它还在不在。
struct GatewayEndpoint: Equatable, Sendable {
    let host: String
    let port: Int

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    /// 播放地址是本机播放服务（http://127.0.0.1:端口/…）时取出主机与端口；直连地址、本地文件为 nil。
    init?(planURL: String) {
        guard let components = URLComponents(string: planURL),
              components.scheme == "http",
              components.host == "127.0.0.1",
              let port = components.port
        else { return nil }
        self.init(host: "127.0.0.1", port: port)
    }

    /// 连一下看有没有在监听。本机回环上的连接立刻有结果（连上或被拒绝），不会卡住。
    func probe() -> GatewayHealth {
        switch connected() {
        case .success(let descriptor):
            close(descriptor)
            return .listening
        case .failure(let failure):
            return .unreachable(code: failure.code)
        }
    }

    /// 向本机播放服务要某个地址的第一个字节，返回状态行（如 "HTTP/1.1 206 Partial Content"）；
    /// 连不上或没有回应时返回原因。用来区分「服务没了」和「服务在、但取不到片源」。
    func statusLine(path: String, timeout: Int = 5) -> String {
        switch connected() {
        case .failure(let failure):
            return "connect errno \(failure.code)"
        case .success(let descriptor):
            defer { close(descriptor) }
            var limit = timeval(tv_sec: timeout, tv_usec: 0)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
            var on: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let request = "GET \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nRange: bytes=0-0\r\nConnection: close\r\n\r\n"
            let sent = request.withCString { send(descriptor, $0, strlen($0), 0) }
            guard sent > 0 else { return "send errno \(errno)" }
            var buffer = [UInt8](repeating: 0, count: 256)
            let received = recv(descriptor, &buffer, buffer.count, 0)
            guard received > 0 else { return received == 0 ? "closed without a response" : "recv errno \(errno)" }
            let text = String(decoding: buffer[..<received], as: UTF8.self)
            return text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "empty response"
        }
    }

    private struct ConnectFailure: Error {
        let code: Int32
    }

    private func connected() -> Result<Int32, ConnectFailure> {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return .failure(ConnectFailure(code: errno)) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(truncatingIfNeeded: port).bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            close(descriptor)
            return .failure(ConnectFailure(code: EINVAL))
        }
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(descriptor)
            return .failure(ConnectFailure(code: code))
        }
        return .success(descriptor)
    }
}

/// 本机播放服务探测结果。
enum GatewayHealth: Equatable, Sendable {
    /// 有服务在监听。
    case listening
    /// 连不上；code 是 errno（ECONNREFUSED = 没有在监听）。
    case unreachable(code: Int32)
}

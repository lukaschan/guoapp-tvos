import Foundation
import Testing
@testable import GuoAppLogic

/// 在本机随机端口上监听的测试用套接字。
private final class Listener {
    let descriptor: Int32
    let port: Int

    init() {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        self.descriptor = descriptor
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        _ = listen(descriptor, 4)
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        port = Int(UInt16(bigEndian: bound.sin_port))
    }

    func stop() { close(descriptor) }

    /// 接一个连接，读完请求后回一段固定内容再关掉。
    func respondOnce(with response: String) {
        let descriptor = descriptor
        Thread.detachNewThread {
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 1024)
            _ = recv(client, &buffer, buffer.count, 0)
            _ = response.withCString { send(client, $0, strlen($0), 0) }
            close(client)
        }
    }
}

struct GatewayEndpointTests {
    @Test func readsLoopbackHostAndPortFromThePlanURL() {
        let endpoint = GatewayEndpoint(planURL: "http://127.0.0.1:51234/0a1b/asset.m3u8")
        #expect(endpoint == GatewayEndpoint(host: "127.0.0.1", port: 51234))
    }

    /// 直连地址（不经核心的本机播放服务）与本地文件不是本机播放地址。
    @Test func ignoresAddressesThatAreNotTheLocalGateway() {
        #expect(GatewayEndpoint(planURL: "https://cdn.example.com/a.m3u8") == nil)
        #expect(GatewayEndpoint(planURL: "http://192.168.1.20:8080/a.m3u8") == nil)
        #expect(GatewayEndpoint(planURL: "file:///tmp/a.mp4") == nil)
        #expect(GatewayEndpoint(planURL: "http://127.0.0.1/a.m3u8") == nil)
        #expect(GatewayEndpoint(planURL: "") == nil)
    }

    @Test func aListeningPortIsReportedAsListening() {
        let listener = Listener()
        defer { listener.stop() }
        #expect(GatewayEndpoint(host: "127.0.0.1", port: listener.port).probe() == .listening)
    }

    @Test func statusLineIsTheFirstLineOfTheResponse() {
        let listener = Listener()
        defer { listener.stop() }
        listener.respondOnce(with: "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
        let endpoint = GatewayEndpoint(host: "127.0.0.1", port: listener.port)
        #expect(endpoint.statusLine(path: "/token/asset.m3u8") == "HTTP/1.1 502 Bad Gateway")
    }

    @Test func statusLineReportsARefusedConnection() {
        let listener = Listener()
        let port = listener.port
        listener.stop()
        #expect(GatewayEndpoint(host: "127.0.0.1", port: port).statusLine(path: "/x") == "connect errno \(ECONNREFUSED)")
    }

    /// 监听的套接字没了（系统在 App 挂起时回收）：连接被拒绝。
    @Test func aClosedPortIsReportedAsRefused() {
        let listener = Listener()
        let port = listener.port
        listener.stop()
        #expect(GatewayEndpoint(host: "127.0.0.1", port: port).probe() == .unreachable(code: ECONNREFUSED))
    }
}

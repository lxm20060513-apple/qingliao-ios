import Foundation
import Network

/// 网络类型监测：iOS 27 蜂窝下侧载 App 上行被管控（必须走 Safari relay）；
/// Wi-Fi 下 URLSession 直连即可（免 relay 弹窗）。
/// 单例 + MainActor 读取（App 所有请求都在主线程发起），main 队列写入。
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "qingliao.network.monitor")

    /// 当前是否蜂窝网络（蜂窝 → 需要 relay；Wi-Fi/其他 → 直连）
    private(set) var isCellular = false

    private init() {
        // v2.0.102：同步读取当前路径——避免首帧请求误判 Wi-Fi（蜂窝下首请求必失败一次）
        let p = monitor.currentPath
        let hasLAN = p.availableInterfaces.contains { $0.type == .wifi || $0.type == .wiredEthernet }
        isCellular = !hasLAN && (p.isExpensive || p.availableInterfaces.contains { $0.type == .cellular })
        monitor.pathUpdateHandler = { [weak self] path in
            // v2.0.67：有 WiFi/有线接口时绝不判蜂窝（此前 isExpensive 在 WiFi 低数据模式/
            // iOS 27 偶发 true → 误判蜂窝 → 登录走 Safari relay 弹窗，用户实测）
            let hasLAN = path.availableInterfaces.contains { $0.type == .wifi || $0.type == .wiredEthernet }
            let cellular = !hasLAN && (path.isExpensive
                || path.availableInterfaces.contains { $0.type == .cellular })
            DispatchQueue.main.async {
                self?.isCellular = cellular
            }
        }
        monitor.start(queue: queue)
    }
}

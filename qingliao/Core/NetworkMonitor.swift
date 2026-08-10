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
        monitor.pathUpdateHandler = { [weak self] path in
            let cellular = path.isExpensive
                || path.availableInterfaces.contains { $0.type == .cellular }
            DispatchQueue.main.async {
                self?.isCellular = cellular
            }
        }
        monitor.start(queue: queue)
    }
}

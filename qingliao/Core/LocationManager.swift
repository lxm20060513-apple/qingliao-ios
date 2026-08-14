import CoreLocation
import Foundation

// MARK: - v2.0.87v 定位（天气用）：授权后获取坐标，拒绝/未授权则 resolved=true 不再请求

@MainActor
final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private let manager = CLLocationManager()
    private(set) var location: CLLocationCoordinate2D?
    private(set) var resolved = false   // 已出结果（授权/拒绝/失败/超时）

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer   // 天气精度足够，省电
    }

    /// 请求定位（首次弹授权；拒绝后不再弹）
    func request() {
        guard !resolved else { return }
        let s = manager.authorizationStatus
        if s == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if s == .authorizedWhenInUse || s == .authorizedAlways {
            manager.requestLocation()
        } else {
            resolved = true   // 拒绝/受限 → 不再请求，不显示天气
        }
        // 15 秒超时兜底（授权后无回调等极端情况）
        Task {
            try? await Task.sleep(for: .seconds(15))
            if !self.resolved { self.resolved = true }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        if s == .authorizedWhenInUse || s == .authorizedAlways {
            manager.requestLocation()
        } else if s == .denied || s == .restricted {
            resolved = true
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.first?.coordinate
        resolved = true
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        resolved = true   // 定位失败（权限弹窗未响应等）→ 不显示天气
    }
}

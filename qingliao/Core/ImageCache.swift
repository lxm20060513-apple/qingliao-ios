import UIKit

// MARK: - v2.0.87c 图片解码缓存（历史消息图片重复解码 → NSCache，滑动/重看不卡）

// v2.0.87f：NSCache 非 Sendable → @MainActor 隔离（视图均在主线程调用，安全且满足 Swift 6 并发检查）
@MainActor
private let imageCache = NSCache<NSString, UIImage>()

/// 解码 dataURL 图片（base64），带 NSCache 缓存（主线程调用）
@MainActor
func dataURLImage(_ urlStr: String) -> UIImage? {
    guard !urlStr.isEmpty else { return nil }
    if let img = imageCache.object(forKey: urlStr as NSString) {
        return img
    }
    guard let data = Data(base64Encoded: String(urlStr.dropFirst("data:image/jpeg;base64,".count)),
                          options: .ignoreUnknownCharacters) else { return nil }
    guard let img = UIImage(data: data) else { return nil }
    if imageCache.totalCostLimit == 0 {
        imageCache.totalCostLimit = 40 * 1024 * 1024   // 40MB
    }
    imageCache.setObject(img, forKey: urlStr as NSString, cost: data.count)
    return img
}

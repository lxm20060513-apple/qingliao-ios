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
    // v2.0.102：动态匹配 data URL 前缀（png/heic 等非 jpeg 也被正确截断；纯 base64 原样解码）
    var b64 = urlStr
    if let comma = urlStr.firstIndex(of: ","),
       urlStr[..<comma].hasPrefix("data:image/") {
        b64 = String(urlStr[urlStr.index(after: comma)...])
    }
    guard let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return nil }
    guard let img = UIImage(data: data) else { return nil }
    if imageCache.totalCostLimit == 0 {
        imageCache.totalCostLimit = 40 * 1024 * 1024   // 40MB
    }
    imageCache.setObject(img, forKey: urlStr as NSString, cost: data.count)
    return img
}

/// v2.0.128：已下载的远程图片缓存（AI 发图 / 大图查看器共用，滚动复用不重复下载）
@MainActor
private let remoteImageCache = NSCache<NSString, UIImage>()

@MainActor
func cachedRemoteImage(_ urlStr: String) -> UIImage? {
    remoteImageCache.object(forKey: urlStr as NSString)
}

@MainActor
func setRemoteImageCache(_ urlStr: String, _ img: UIImage, cost: Int) {
    if remoteImageCache.totalCostLimit == 0 {
        remoteImageCache.totalCostLimit = 40 * 1024 * 1024   // 40MB
    }
    remoteImageCache.setObject(img, forKey: urlStr as NSString, cost: cost)
}

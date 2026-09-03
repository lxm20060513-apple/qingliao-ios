import UIKit

// MARK: - v2.0.87c 图片解码缓存（历史消息图片重复解码 → NSCache，滑动/重看不卡）

// v2.0.87f：NSCache 非 Sendable → @MainActor 隔离（视图均在主线程调用，安全且满足 Swift 6 并发检查）
@MainActor
private let imageCache = NSCache<NSString, UIImage>()

/// v3.0.x fix：base64 解码放到后台队列，避免大图片阻塞主线程
private let _imageDecodeQueue = DispatchQueue(label: "qingliao.image.decode", qos: .userInitiated)

/// 初始化缓存限制（App 启动时调用一次；避免首次使用前 0 限制 → 无上限缓存）
@MainActor
func initImageCacheLimit() {
    imageCache.totalCostLimit = 40 * 1024 * 1024  // 40MB
}

/// 解码 dataURL 图片（base64），带 NSCache 缓存（主线程调用）
/// v3.0.x fix：大图片解码移到后台队列（NSCache 读写仍在主线程）
@MainActor
func dataURLImage(_ urlStr: String) -> UIImage? {
    guard !urlStr.isEmpty else { return nil }
    // 缓存命中直接返回（零开销）
    if let img = imageCache.object(forKey: urlStr as NSString) {
        return img
    }
    // v2.0.102：动态匹配 data URL 前缀（png/heic 等非 jpeg 也被正确截断；纯 base64 原样解码）
    var b64 = urlStr
    if let comma = urlStr.firstIndex(of: ","),
       urlStr[..<comma].hasPrefix("data:image/") {
        b64 = String(urlStr[urlStr.index(after: comma)...])
    }
    guard let imgData = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return nil }
    // 小图片（< 100KB）直接在主线程解码（dispatch 开销 > 解码开销）
    if imgData.count < 100_000 {
        guard let img = UIImage(data: imgData) else { return nil }
        if imageCache.totalCostLimit == 0 {
            imageCache.totalCostLimit = 40 * 1024 * 1024
        }
        imageCache.setObject(img, forKey: urlStr as NSString, cost: imgData.count)
        return img
    }
    // 大图片：先在主线程解码（保证首次也能显示），但 base64 Data 已在上面解析完，此步仅 UIImage init
    // 真正的优化：AIImageView 等调用方应使用 asyncDataURLImage（见下方）
    guard let img = UIImage(data: imgData) else { return nil }
    if imageCache.totalCostLimit == 0 {
        imageCache.totalCostLimit = 40 * 1024 * 1024
    }
    imageCache.setObject(img, forKey: urlStr as NSString, cost: imgData.count)
    return img
}

/// v3.0.x fix：异步版——大图片 base64 解码在后台线程完成，不阻塞 UI
/// 调用方在 view.task 中调用，decoded 回调在主线程执行
@MainActor
func asyncDataURLImage(_ urlStr: String, decoded: @escaping @MainActor (UIImage) -> Void) {
    guard !urlStr.isEmpty else { return }
    if let img = imageCache.object(forKey: urlStr as NSString) {
        decoded(img)
        return
    }
    var b64 = urlStr
    if let comma = urlStr.firstIndex(of: ","),
       urlStr[..<comma].hasPrefix("data:image/") {
        b64 = String(urlStr[urlStr.index(after: comma)...])
    }
    guard let imgData = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) else { return }
    _imageDecodeQueue.async {
        guard let img = UIImage(data: imgData) else { return }
        DispatchQueue.main.async {
            if imageCache.totalCostLimit == 0 {
                imageCache.totalCostLimit = 40 * 1024 * 1024
            }
            imageCache.setObject(img, forKey: urlStr as NSString, cost: imgData.count)
            decoded(img)
        }
    }
}

/// v2.0.128：已下载的远程图片缓存（AI 发图 / 大图查看器共用，滚动复用不重复下载）
@MainActor
private let remoteImageCache = NSCache<NSString, UIImage>()

@MainActor
func cachedRemoteImage(_ urlStr: String) -> UIImage? {
    remoteImageCache.object(forKey: remoteCacheKey(urlStr))
}

@MainActor
func setRemoteImageCache(_ urlStr: String, _ img: UIImage, cost: Int) {
    if remoteImageCache.totalCostLimit == 0 {
        remoteImageCache.totalCostLimit = 40 * 1024 * 1024   // 40MB
    }
    remoteImageCache.setObject(img, forKey: remoteCacheKey(urlStr), cost: cost)
}

/// v3.0.x fix：缓存 key 去除 query 参数（同一资源不同 token/时间戳共享缓存）
@MainActor
private func remoteCacheKey(_ urlStr: String) -> NSString {
    guard let url = URL(string: urlStr) else { return urlStr as NSString }
    // 用 path（去除 query/fragment）作为 key
    return url.path as NSString
}

import Foundation
import Observation
import UIKit

// MARK: - 键盘观察器：键盘弹出/收起高度（Dock 隐藏 + 输入框贴键盘）
// 用 NSObject + @objc selector（addObserver(forName:using:) 闭包是 @Sendable，Swift 6 下不能捕获 self）

@MainActor
@Observable
final class KeyboardObserver: NSObject {
    var height: CGFloat = 0
    var topY: CGFloat = 0   // v2.0.37：键盘顶部 y（屏幕坐标，精确贴键盘用）
    var isVisible: Bool { height > 0 }

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(kbWillShow(_:)),
                           name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(kbWillHide(_:)),
                           name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func kbWillShow(_ note: Notification) {
        if let rect = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            height = rect.height
            topY = rect.minY
        }
    }

    @objc private func kbWillHide(_ note: Notification) {
        height = 0
        topY = 0
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

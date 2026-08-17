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
    // v2.0.133e：键盘动画时长/曲线——输入框 padding 动画与键盘系统动画同参数，消除衔接跳变
    // （原来固定 easeOut 0.22s 与系统 ~0.25s 不同步，键盘弹起瞬间输入框轻微跳）
    var animationDuration: TimeInterval = 0.25
    var animationOptions: UIView.AnimationOptions = [.curveEaseOut]
    // v2.0.107：上次键盘弹出时间戳——长按输入框时区分"键盘早就开着"vs"刚被触摸聚焦弹出"
    var lastShowTime: Date? = nil

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(kbWillShow(_:)),
                           name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(kbWillHide(_:)),
                           name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func kbWillShow(_ note: Notification) {
        lastShowTime = Date()
        if let rect = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
            height = rect.height
            topY = rect.minY
        }
        if let dur = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber {
            animationDuration = dur.doubleValue
        }
        if let curveRaw = note.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber {
            animationOptions = UIView.AnimationOptions(rawValue: UInt(curveRaw.uintValue) << 16)
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

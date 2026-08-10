import Foundation
import WebKit
import UIKit

/// WebKit 网络层：内嵌隐藏 WKWebView，用 JS fetch 发请求
/// 背景：iOS 27 原生网络栈（URLSession/NWConnection/CFStream）的 POST 在蜂窝+外网全废（实测三个栈 GET 通 POST 从未到达服务器），
///       而 WebKit（Safari/PWA）POST 正常——用 WKWebView 的 fetch 与 PWA 完全同栈。
/// 原生 UI 不变，仅网络请求改经此层。
@MainActor
final class WebKitClient: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private var pending: [String: CheckedContinuation<(Int, String), Error>] = [:]
    private var counter = 0
    private var ready = false

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        let content = WKUserContentController()
        content.add(self, name: "qingliaoBridge")
        config.userContentController = content
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.navigationDelegate = self
        webView = wv
        // ⚠️ 必须加入视图层级且不可隐藏：不在 window 的 WKWebView 页面未激活 → iOS WebKit 节流/挂起网络请求（fetch 永不回调；Safari 前台正常）
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first })
            .first {
            window.addSubview(wv)
            wv.isHidden = false
            wv.alpha = 0.01
            wv.isOpaque = false
            wv.backgroundColor = .clear
        }
        // 加载空页；didFinish 后才 ready（web process 就绪，fetch 才能正常发出）
        wv.loadHTMLString("<!DOCTYPE html><html><body></body></html>", baseURL: nil)
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
    }

    /// 请求：JS fetch 异步执行，结果经 messageHandler 回传
    func request(url: String, method: String = "GET", headers: [String: String] = [:],
                 body: String? = nil, timeout: TimeInterval = 10) async throws -> (Int, String) {
        let id = "r\(counter)"; counter += 1

        // JS 字符串字面量安全编码（JSON 转义）
        func jsStr(_ s: String) -> String {
            let data = (JSONSerialization.isValidJSONObject(s)
                        ? (try? JSONSerialization.data(withJSONObject: s)) : nil) ?? Data("\"\"".utf8)
            return String(data: data, encoding: .utf8) ?? "\"\""
        }
        let urlJS = jsStr(url)
        let methodJS = jsStr(method)
        var headersJS = "{"
        for (k, v) in headers {
            headersJS += "\(jsStr(k)): \(jsStr(v)),"
        }
        headersJS += "}"
        let bodyJS = body.map { jsStr($0) } ?? "null"

        let js = """
        (function(){
          try {
            fetch(\(urlJS), {method: \(methodJS), headers: \(headersJS), body: \(bodyJS)})
              .then(function(r){ return r.text().then(function(t){
                window.webkit.messageHandlers.qingliaoBridge.postMessage({id: \(jsStr(id)), status: r.status, body: t});
              });})
              .catch(function(e){ window.webkit.messageHandlers.qingliaoBridge.postMessage({id: \(jsStr(id)), status: 0, body: String(e)}); });
          } catch(e) {
            window.webkit.messageHandlers.qingliaoBridge.postMessage({id: \(jsStr(id)), status: 0, body: String(e)});
          }
        })();
        """

        // 等待 WKWebView 就绪（web process 启动后才可 evaluateJavaScript）
        while !ready {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Int, String), Error>) in
            pending[id] = cont
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    // evaluateJavaScript 本身失败（如 web process 未就绪/JS 异常）
                    Task { @MainActor in
                        if let c = self.pending.removeValue(forKey: id) {
                            c.resume(throwing: APIError.badResponseDetail("js eval fail: \(error.localizedDescription)"))
                        }
                    }
                }
            }
            // 超时兜底
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if let c = pending.removeValue(forKey: id) {
                    c.resume(throwing: APIError.timeoutDetail("wk timeout"))
                }
            }
        }
    }

    // MARK: - WKScriptMessageHandler
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            guard let dict = message.body as? [String: Any],
                  let id = dict["id"] as? String,
                  let cont = pending.removeValue(forKey: id) else { return }
            let status = dict["status"] as? Int ?? 0
            let body = dict["body"] as? String ?? ""
            cont.resume(returning: (status, body))
        }
    }
}

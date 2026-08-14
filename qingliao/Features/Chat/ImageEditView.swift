import SwiftUI

// MARK: - v2.0.92 发送前图片编辑（裁剪框拖动/缩放 + 涂鸦标注 4 色 + 撤销）
// v2.0.92f：Canvas 渲染不可靠（编辑时看不到涂鸦）→ 改 Path 叠加；补 dismiss 退出；
// 每条笔迹存颜色；onChange(geo.size) 重算裁剪框。

struct ImageEditView: View {
    let image: UIImage
    let onDone: (UIImage) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    enum EditMode { case crop, draw }

    @State private var mode: EditMode = .crop
    @State private var cropRect: CGRect = .zero
    @State private var viewRect: CGRect = .zero      // 图片 aspectFit 显示区域（view 坐标）
    @State private var strokes: [(color: Color, points: [CGPoint])] = []   // 笔迹（带颜色）
    @State private var currentStroke: [CGPoint] = []
    @State private var penColor: Color = .red
    @State private var dragStart: CGRect?
    @State private var lastMag: CGFloat = 1

    let penColors: [Color] = [.red, .yellow, .white, .black]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let vr = aspectFitRect(image.size, in: geo.size)
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: vr.width, height: vr.height)
                        .position(x: vr.midX, y: vr.midY)

                    // 涂鸦显示（Path 叠加，逐条绘制——比 Canvas 可靠）
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(strokes.enumerated()), id: \.offset) { _, s in
                            strokePath(s.points, color: s.color)
                        }
                        strokePath(currentStroke, color: penColor)
                    }
                    .frame(width: vr.width, height: vr.height)
                    .position(x: vr.midX, y: vr.midY)
                    .allowsHitTesting(false)

                    // 裁剪模式：框外遮罩 + 白色裁剪框
                    if mode == .crop {
                        // v2.0.93f：捏合手势挂整层（裁剪框小，双指常在框外——挂框上识别不到）
                        ZStack {
                            cropMask(vr)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .strokeBorder(Color.white, lineWidth: 2)
                                .frame(width: cropRect.width, height: cropRect.height)
                                .position(x: cropRect.midX, y: cropRect.midY)
                                .gesture(cropDragGesture(vr))
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .contentShape(Rectangle())
                        .gesture(cropZoomGesture(vr))
                    } else {
                        // 涂鸦模式：画笔层接收手势（覆盖图片区域）
                        Color.clear
                            .frame(width: vr.width, height: vr.height)
                            .position(x: vr.midX, y: vr.midY)
                            .contentShape(Rectangle())
                            .gesture(drawGesture(vr))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .onAppear {
                    viewRect = vr
                    cropRect = CGRect(x: vr.minX + vr.width * 0.06,
                                      y: vr.minY + vr.height * 0.06,
                                      width: vr.width * 0.88,
                                      height: vr.height * 0.88)
                }
                .onChange(of: geo.size) { _, _ in
                    let vr2 = aspectFitRect(image.size, in: geo.size)
                    viewRect = vr2
                    cropRect = CGRect(x: vr2.minX + vr2.width * 0.06,
                                      y: vr2.minY + vr2.height * 0.06,
                                      width: vr2.width * 0.88,
                                      height: vr2.height * 0.88)
                }
            }

            // 顶部：模式切换 + 颜色 + 撤销
            VStack {
                HStack(spacing: 10) {
                    modeButton("裁剪", mode: .crop)
                    modeButton("涂鸦", mode: .draw)
                    Spacer()
                    if mode == .draw {
                        ForEach(penColors, id: \.self) { c in
                            Circle()
                                .fill(c)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(c == penColor ? Color.white : Color.white.opacity(0.3), lineWidth: c == penColor ? 3 : 1))
                                .onTapGesture { penColor = c }
                        }
                        Button {
                            if !strokes.isEmpty { strokes.removeLast() }
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(.white.opacity(0.18), in: Circle())
                        }
                        .disabled(strokes.isEmpty)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                // 底部：取消 / 完成
                HStack(spacing: 20) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Text("取消")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 26)
                            .padding(.vertical, 11)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                    Button {
                        finish()
                        dismiss()
                    } label: {
                        Text("完成")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 30)
                            .padding(.vertical, 11)
                            .background(LinearGradient(colors: [.blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
                    }
                }
                .padding(.bottom, 26)
            }
        }
    }

    // MARK: - 组件

    /// 一条笔迹 → Path 视图（v2.0.92f：替代 Canvas，实时可见）
    private func strokePath(_ points: [CGPoint], color: Color) -> some View {
        Path { p in
            guard points.count > 1 else { return }
            p.move(to: points[0])
            for pt in points.dropFirst() { p.addLine(to: pt) }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }

    private func modeButton(_ name: String, mode m: EditMode) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { mode = m }
        } label: {
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(mode == m ? .white : .white.opacity(0.7))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(mode == m ? Color.blue : Color.white.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// 框外 4 块遮罩（上下左右）
    private func cropMask(_ vr: CGRect) -> some View {
        let r = cropRect
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.55).frame(width: vr.width, height: max(0, r.minY - vr.minY)).offset(x: vr.minX, y: vr.minY)
            Color.black.opacity(0.55).frame(width: vr.width, height: max(0, vr.maxY - r.maxY)).offset(x: vr.minX, y: r.maxY)
            Color.black.opacity(0.55).frame(width: max(0, r.minX - vr.minX), height: max(0, r.height)).offset(x: vr.minX, y: r.minY)
            Color.black.opacity(0.55).frame(width: max(0, vr.maxX - r.maxX), height: max(0, r.height)).offset(x: r.maxX, y: r.minY)
        }
        .allowsHitTesting(false)
    }

    // MARK: - 手势

    private func cropDragGesture(_ vr: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { v in
                if dragStart == nil { dragStart = cropRect }
                if let s = dragStart {
                    let minX = vr.minX, maxX = vr.maxX - cropRect.width
                    let minY = vr.minY, maxY = vr.maxY - cropRect.height
                    cropRect.origin = CGPoint(
                        x: min(max(minX, s.minX + v.translation.width), maxX),
                        y: min(max(minY, s.minY + v.translation.height), maxY)
                    )
                }
            }
            .onEnded { _ in dragStart = nil }
    }

    private func cropZoomGesture(_ vr: CGRect) -> some Gesture {
        MagnificationGesture()
            .onChanged { m in
                let delta = m / lastMag
                lastMag = m
                let w = min(max(cropRect.width * delta, 80), vr.width)
                let h = min(max(cropRect.height * delta, 80), vr.height)
                let cx = cropRect.midX
                let cy = cropRect.midY
                cropRect = CGRect(
                    x: min(max(vr.minX, cx - w / 2), vr.maxX - w),
                    y: min(max(vr.minY, cy - h / 2), vr.maxY - h),
                    width: w, height: h
                )
            }
            .onEnded { _ in lastMag = 1 }
    }

    private func drawGesture(_ vr: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                currentStroke.append(v.location)
            }
            .onEnded { _ in
                if !currentStroke.isEmpty {
                    strokes.append((color: penColor, points: currentStroke))
                }
                currentStroke = []
            }
    }

    // MARK: - 合成

    private func finish() {
        // 1) 归一化方向（EXIF orientation → up），保证像素坐标与显示一致
        let norm: UIImage
        if image.imageOrientation == .up {
            norm = image
        } else {
            norm = UIGraphicsImageRenderer(size: image.size).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }
        guard let cg = norm.cgImage else { onCancel(); return }
        // 2) 裁剪框（view 坐标）→ 像素坐标
        let inter = cropRect.intersection(viewRect)
        guard !inter.isEmpty, inter.width > 2, inter.height > 2 else { onCancel(); return }
        let scaleX = norm.size.width / viewRect.width
        let scaleY = norm.size.height / viewRect.height
        let px = CGRect(x: (inter.minX - viewRect.minX) * scaleX,
                        y: (inter.minY - viewRect.minY) * scaleY,
                        width: inter.width * scaleX,
                        height: inter.height * scaleY)
        guard let cropped = cg.cropping(to: px) else { onCancel(); return }
        // 3) 合成：裁剪图 + 涂鸦（每条线用自己颜色）
        let outSize = CGSize(width: cropped.width, height: cropped.height)
        let renderer = UIGraphicsImageRenderer(size: outSize)
        let result = renderer.image { ctx in
            UIImage(cgImage: cropped).draw(in: CGRect(origin: .zero, size: outSize))
            ctx.cgContext.setLineCap(.round)
            ctx.cgContext.setLineJoin(.round)
            for s in strokes {
                guard s.points.count > 1 else { continue }
                let path = UIBezierPath()
                let p0 = CGPoint(x: (s.points[0].x - viewRect.minX) * scaleX - px.minX,
                                 y: (s.points[0].y - viewRect.minY) * scaleY - px.minY)
                path.move(to: p0)
                for p in s.points.dropFirst() {
                    path.addLine(to: CGPoint(x: (p.x - viewRect.minX) * scaleX - px.minX,
                                             y: (p.y - viewRect.minY) * scaleY - px.minY))
                }
                ctx.cgContext.setStrokeColor(UIColor(s.color).cgColor)
                ctx.cgContext.setLineWidth(4 * scaleX)
                ctx.cgContext.addPath(path.cgPath)
                ctx.cgContext.strokePath()
            }
        }
        onDone(result)
    }

    /// 图片 aspectFit 显示区域
    private func aspectFitRect(_ imgSize: CGSize, in container: CGSize) -> CGRect {
        guard imgSize.width > 0, imgSize.height > 0 else { return .zero }
        let scale = min(container.width / imgSize.width, container.height / imgSize.height)
        let w = imgSize.width * scale
        let h = imgSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}

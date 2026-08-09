import SwiftUI

// MARK: - 看板页（智能家居 2x3 + NAS 面板 2x3，阶段 1 占位数据）

struct DashboardView: View {
    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "看板", subtitle: "智能家居 · NAS 状态")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle("智能家居")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        DeviceCard(name: "客厅灯", value: "100%", sub: "已开启 · 暖白", status: .on)
                        DeviceCard(name: "空调", value: "26°", sub: "制冷 · 自动风", status: .on)
                        DeviceCard(name: "门锁", value: "已上锁", sub: "电量 78%", status: .on)
                        DeviceCard(name: "猫眼", value: "在线", sub: "电量 64%", status: .on)
                        DeviceCard(name: "安防", value: "布防", sub: "所有门窗已关闭", status: .on)
                        DeviceCard(name: "温度", value: "26.5°", sub: "湿度 48%", status: .on)
                    }

                    sectionTitle("NAS 面板")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        MeterCard(name: "CPU", value: "12%", sub: nil, ratio: 0.12, color: .blue)
                        MeterCard(name: "内存", value: "4.6G", sub: "/ 19 GB", ratio: 0.24, color: .green)
                        MeterCard(name: "磁盘 v1", value: "57%", sub: "124 / 218 GB", ratio: 0.57, color: .orange)
                        ServiceCard(name: "轻聊后端", detail: "24.9 MB")
                        ServiceCard(name: "Hermes 网关", detail: "376 MB")
                        ServiceCard(name: "运行时间", detail: "3 天 12 时")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 100)
            }
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 15, weight: .bold))
            .padding(.top, 6)
    }
}

enum DeviceStatus { case on, off, warn }

struct DeviceCard: View {
    let name: String
    let value: String
    let sub: String
    let status: DeviceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(name)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.6), radius: 4)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .padding(.top, 6)
            Text(sub)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var color: Color {
        switch status {
        case .on: .green
        case .off: .gray
        case .warn: .orange
        }
    }
}

struct MeterCard: View {
    let name: String
    let value: String
    let sub: String?
    let ratio: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(name).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(.green).frame(width: 8, height: 8)
            }
            Text(value).font(.system(size: 18, weight: .bold)).padding(.top, 6)
            if let sub {
                Text(sub).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .systemGray5))
                    Capsule().fill(color).frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 4)
            .padding(.top, 7)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ServiceCard: View {
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(name).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(.green).frame(width: 8, height: 8)
            }
            Text("运行中").font(.system(size: 14, weight: .bold)).padding(.top, 6)
            Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 1)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

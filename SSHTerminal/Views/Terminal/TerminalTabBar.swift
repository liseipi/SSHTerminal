import SwiftUI

struct TerminalTabBar: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(viewModel.tabs) { tab in
                    TabButton(
                        tab: tab,
                        isActive: viewModel.activeTabId == tab.id,
                        onSelect: {
                            viewModel.switchTab(to: tab.id)
                        },
                        onClose: {
                            viewModel.closeTab(tab.id)
                        }
                    )
                }
            }
        }
        .frame(height: 40)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct TabButton: View {
    let tab: TerminalTab
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            // 连接图标
            Image(systemName: "terminal.fill")
                .font(.caption)
                .foregroundColor(isActive ? .blue : .secondary)
            
            // 连接名称
            Text(tab.displayName)
                .font(.system(size: 12))
                .lineLimit(1)
                .foregroundColor(isActive ? .primary : .secondary)
            
            // 状态指示器
            if tab.connectionStatus == "已连接" {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            } else if tab.connectionStatus == "正在连接..." {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
            } else if tab.connectionStatus == "连接失败" {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
            }
            
            // 关闭按钮（悬停时显示）
            if isHovering || isActive {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .background(Color.gray.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("关闭标签页")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color(NSColor.controlBackgroundColor) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isActive ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

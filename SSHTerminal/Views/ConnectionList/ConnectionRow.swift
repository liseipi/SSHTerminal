import SwiftUI

struct ConnectionRow: View {
    let connection: SSHConnection
    let isActive: Bool
    let isConnecting: Bool
    let onConnect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.name)
                    .font(.system(size: 14, weight: .medium))
                
                Text("\(connection.username)@\(connection.host):\(connection.port)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Image(systemName: connection.authType == .password ? "lock.fill" : "key.fill")
                        .font(.system(size: 10))
                    Text(connection.authType.rawValue)
                        .font(.system(size: 10))
                }
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 操作按钮（悬停时显示）
            if isHovering || isActive {
                HStack(spacing: 8) {
                    // 编辑按钮
                    Button(action: onEdit) {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("编辑连接")
                    
                    // 连接状态指示器
                    if isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else if isActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    }
                    
                    // 删除按钮
                    Button(action: onDelete) {
                        Image(systemName: "trash.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("删除连接")
                }
            }
        }
        .padding()
        .background(isActive ? Color.blue.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // 双击创建新 Tab
            if !isConnecting {
                onConnect()
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

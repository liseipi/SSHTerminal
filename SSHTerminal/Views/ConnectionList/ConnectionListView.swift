import SwiftUI

struct ConnectionListView: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                Label("SSH 连接", systemImage: "server.rack")
                    .font(.headline)
                Spacer()
                
                // 已连接的 Tab 数量
                if !viewModel.tabs.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.caption)
                        Text("\(viewModel.tabs.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
                
                Button(action: { viewModel.showAddForm.toggle() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // 添加连接表单
            if viewModel.showAddForm {
                AddConnectionForm(viewModel: viewModel)
                Divider()
            }
            
            // 连接列表
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.connections) { connection in
                        let hasActiveTab = viewModel.tabs.contains { $0.connection.id == connection.id }
                        
                        ConnectionRow(
                            connection: connection,
                            isActive: hasActiveTab,
                            isConnecting: viewModel.isConnecting,
                            onConnect: {
                                // 双击创建新 Tab
                                viewModel.createTab(for: connection)
                            },
                            onEdit: { viewModel.editConnection(connection) },
                            onDelete: { viewModel.deleteConnection(connection) }
                        )
                        Divider()
                    }
                }
            }
            
            // 底部提示
            if !viewModel.connections.isEmpty {
                Divider()
                HStack {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("双击连接打开新标签页")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

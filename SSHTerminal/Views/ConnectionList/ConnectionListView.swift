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
                
                // 连接状态指示器
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.activeConnection != nil ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(viewModel.connectionStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                        ConnectionRow(
                            connection: connection,
                            isActive: viewModel.activeConnection?.id == connection.id,
                            isConnecting: viewModel.isConnecting && viewModel.activeConnection?.id == connection.id,
                            onConnect: {
                                if viewModel.activeConnection?.id == connection.id {
                                    viewModel.disconnect()
                                } else {
                                    viewModel.connect(to: connection)
                                }
                            },
                            onEdit: { viewModel.editConnection(connection) },
                            onDelete: { viewModel.deleteConnection(connection) }
                        )
                        Divider()
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

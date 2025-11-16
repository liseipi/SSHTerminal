import SwiftUI

struct AddConnectionForm: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    @State private var connection: SSHConnection
    
    var isEditing: Bool {
        viewModel.editingConnection != nil
    }
    
    init(viewModel: SSHTerminalViewModel) {
        self.viewModel = viewModel
        self._connection = State(initialValue: viewModel.editingConnection ?? SSHConnection())
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text(isEditing ? "编辑连接" : "添加新连接")
                .font(.headline)
            
            TextField("连接名称", text: $connection.name)
                .textFieldStyle(.roundedBorder)
            
            TextField("主机地址", text: $connection.host)
                .textFieldStyle(.roundedBorder)
            
            TextField("端口", value: $connection.port, format: .number)
                .textFieldStyle(.roundedBorder)
            
            TextField("用户名", text: $connection.username)
                .textFieldStyle(.roundedBorder)
            
            Picker("认证方式", selection: $connection.authType) {
                ForEach(SSHConnection.AuthType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            if connection.authType == .password {
                SecureField("密码", text: $connection.password)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("密钥路径 (如: ~/.ssh/id_rsa)", text: $connection.keyPath)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Button(isEditing ? "保存" : "添加") {
                    if isEditing {
                        viewModel.updateConnection(connection)
                    } else {
                        viewModel.addConnection(connection)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(connection.name.isEmpty || connection.host.isEmpty || connection.username.isEmpty)
                
                Button("取消") {
                    viewModel.showAddForm = false
                    viewModel.editingConnection = nil
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

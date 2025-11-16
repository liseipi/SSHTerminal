import SwiftUI

struct AddConnectionForm: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    @State private var newConnection = SSHConnection()
    
    var body: some View {
        VStack(spacing: 8) {
            TextField("连接名称", text: $newConnection.name)
                .textFieldStyle(.roundedBorder)
            
            TextField("主机地址", text: $newConnection.host)
                .textFieldStyle(.roundedBorder)
            
            TextField("端口", value: $newConnection.port, format: .number)
                .textFieldStyle(.roundedBorder)
            
            TextField("用户名", text: $newConnection.username)
                .textFieldStyle(.roundedBorder)
            
            Picker("认证方式", selection: $newConnection.authType) {
                ForEach(SSHConnection.AuthType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)
            
            if newConnection.authType == .password {
                SecureField("密码", text: $newConnection.password)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField("密钥路径", text: $newConnection.keyPath)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Button("添加") {
                    viewModel.addConnection(newConnection)
                    newConnection = SSHConnection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newConnection.name.isEmpty || newConnection.host.isEmpty || newConnection.username.isEmpty)
                
                Button("取消") {
                    viewModel.showAddForm = false
                    newConnection = SSHConnection()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

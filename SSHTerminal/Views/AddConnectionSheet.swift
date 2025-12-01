internal import SwiftUI
internal import UniformTypeIdentifiers
internal import Combine
internal import SwiftTerm

// MARK: - 添加连接表单
struct AddConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (SSHConnection) -> Void
    
    @State private var name = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var username = ""
    @State private var authMethod: SSHConnection.AuthMethod = .password
    @State private var password = ""
    @State private var privateKeyPath = ""
    @State private var notes = ""
    @State private var tags = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("连接名称", text: $name)
                    TextField("主机地址", text: $host)
                    TextField("端口", text: $port)
                        .frame(width: 100)
                    TextField("用户名", text: $username)
                }
                
                Section("认证方式") {
                    Picker("认证方式", selection: $authMethod) {
                        ForEach(SSHConnection.AuthMethod.allCases, id: \.self) { method in
                            Label(method.rawValue, systemImage: method.systemImage)
                                .tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if authMethod == .password {
                        SecureField("密码", text: $password)
                            .help("SSH登录密码")
                    }
                    
                    if authMethod == .publicKey {
                        HStack {
                            TextField("私钥路径", text: $privateKeyPath)
                            Button("选择") {
                                selectPrivateKey()
                            }
                        }
                    }
                }
                
                Section("其他") {
                    TextField("标签 (用逗号分隔)", text: $tags)
                    TextField("备注", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("添加连接")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveConnection()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 500, height: 550)
    }
    
    private var isValid: Bool {
        !name.isEmpty && !host.isEmpty && !username.isEmpty && Int(port) != nil
    }
    
    private func saveConnection() {
        let tagArray = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        let connection = SSHConnection(
            name: name,
            host: host,
            port: Int(port) ?? 22,
            username: username,
            authMethod: authMethod,
            privateKeyPath: authMethod == .publicKey ? privateKeyPath : nil,
            notes: notes.isEmpty ? nil : notes,
            tags: tagArray
        )
        
        if authMethod == .password && !password.isEmpty {
            connection.setPassword(password)
        }
        
        onSave(connection)
        dismiss()
    }
    
    private func selectPrivateKey() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        panel.message = "选择SSH私钥文件"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        
        if panel.runModal() == .OK, let url = panel.url {
            privateKeyPath = url.path
        }
    }
}

// MARK: - 编辑连接表单
struct EditConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let connection: SSHConnection
    let onSave: (SSHConnection) -> Void
    
    @State private var name: String
    @State private var host: String
    @State private var port: String
    @State private var username: String
    @State private var authMethod: SSHConnection.AuthMethod
    @State private var password: String
    @State private var privateKeyPath: String
    @State private var notes: String
    @State private var tags: String
    
    init(connection: SSHConnection, onSave: @escaping (SSHConnection) -> Void) {
        self.connection = connection
        self.onSave = onSave
        
        _name = State(initialValue: connection.name)
        _host = State(initialValue: connection.host)
        _port = State(initialValue: String(connection.port))
        _username = State(initialValue: connection.username)
        _authMethod = State(initialValue: connection.authMethod)
        _password = State(initialValue: connection.password ?? "")
        _privateKeyPath = State(initialValue: connection.privateKeyPath ?? "")
        _notes = State(initialValue: connection.notes ?? "")
        _tags = State(initialValue: connection.tags.joined(separator: ", "))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("连接名称", text: $name)
                    TextField("主机地址", text: $host)
                    TextField("端口", text: $port)
                        .frame(width: 100)
                    TextField("用户名", text: $username)
                }
                
                Section("认证方式") {
                    Picker("认证方式", selection: $authMethod) {
                        ForEach(SSHConnection.AuthMethod.allCases, id: \.self) { method in
                            Label(method.rawValue, systemImage: method.systemImage)
                                .tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    if authMethod == .password {
                        SecureField("密码", text: $password)
                            .help("SSH登录密码")
                    }
                    
                    if authMethod == .publicKey {
                        HStack {
                            TextField("私钥路径", text: $privateKeyPath)
                            Button("选择") {
                                selectPrivateKey()
                            }
                        }
                    }
                }
                
                Section("其他") {
                    TextField("标签 (用逗号分隔)", text: $tags)
                    TextField("备注", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("信息") {
                    LabeledContent("创建时间") {
                        Text(connection.createdAt, style: .date)
                    }
                    
                    if let lastUsed = connection.lastUsedAt {
                        LabeledContent("最后使用") {
                            Text(lastUsed, style: .relative)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑连接")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveConnection()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .frame(width: 500, height: 600)
    }
    
    private var isValid: Bool {
        !name.isEmpty && !host.isEmpty && !username.isEmpty && Int(port) != nil
    }
    
    private func saveConnection() {
        let tagArray = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        var updated = connection
        updated.name = name
        updated.host = host
        updated.port = Int(port) ?? 22
        updated.username = username
        updated.authMethod = authMethod
        updated.privateKeyPath = authMethod == .publicKey ? privateKeyPath : nil
        updated.notes = notes.isEmpty ? nil : notes
        updated.tags = tagArray
        
        if authMethod == .password {
            updated.setPassword(password.isEmpty ? nil : password)
        } else {
            updated.setPassword(nil)
        }
        
        onSave(updated)
        dismiss()
    }
    
    private func selectPrivateKey() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.data]
        panel.message = "选择SSH私钥文件"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        
        if panel.runModal() == .OK, let url = panel.url {
            privateKeyPath = url.path
        }
    }
}

#Preview {
    AddConnectionSheet { _ in }
}

import SwiftUI
import Combine

class SSHTerminalViewModel: ObservableObject {
    @Published var connections: [SSHConnection] = []
    @Published var activeConnection: SSHConnection?
    @Published var terminalLines: [TerminalLine] = []
    @Published var currentCommand: String = ""
    @Published var fileTree: [FileItem] = []
    @Published var currentPath: String = "~"
    @Published var showAddForm: Bool = false
    @Published var editingConnection: SSHConnection?
    @Published var isConnecting: Bool = false
    @Published var isLoadingFiles: Bool = false
    @Published var connectionStatus: String = "未连接"
    
    private var sshService: SSHService?
    private var sftpService: SFTPService?
    private let connectionManager = ConnectionManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // 从持久化存储加载连接
        connectionManager.$connections
            .assign(to: \.connections, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - 连接管理
    
    func connect(to connection: SSHConnection) {
        print("🔵 [ViewModel] connect() called")
        print("🔵 [ViewModel] Connection: \(connection.name)")
        print("🔵 [ViewModel] isConnecting: \(isConnecting)")
        
        guard !isConnecting else {
            print("⚠️ [ViewModel] Already connecting, ignoring request")
            return
        }
        
        isConnecting = true
        connectionStatus = "正在连接..."
        
        print("🔵 [ViewModel] Adding system message to terminal")
        
        // 添加系统消息
        terminalLines.append(TerminalLine(
            text: "正在连接到 \(connection.username)@\(connection.host):\(connection.port)...",
            type: .system
        ))
        
        print("🔵 [ViewModel] Creating SSHService")
        
        // 创建 SSH 服务
        let service = SSHService()
        sshService = service
        
        print("🔵 [ViewModel] Setting up service observers")
        
        // 监听连接状态
        service.$isConnected
            .sink { [weak self] isConnected in
                print("🔵 [ViewModel] isConnected changed to: \(isConnected)")
                if isConnected {
                    self?.handleConnectionSuccess(connection)
                }
            }
            .store(in: &cancellables)
        
        // 监听输出
        service.onOutputReceived = { [weak self] output, type in
            print("🔵 [ViewModel] Output received: \(output)")
            self?.handleTerminalOutput(output, type: type)
        }
        
        print("🟢 [ViewModel] Calling service.connect()")
        
        // 发起连接
        service.connect(to: connection) { [weak self] result in
            print("🔵 [ViewModel] Connection result received")
            DispatchQueue.main.async {
                self?.isConnecting = false
                
                switch result {
                case .success():
                    print("🟢 [ViewModel] Connection successful!")
                    self?.activeConnection = connection
                    self?.connectionStatus = "已连接"
                    self?.terminalLines.append(TerminalLine(
                        text: "✓ 成功连接到 \(connection.name)",
                        type: .system
                    ))
                    
                    // 初始化 SFTP 服务
                    self?.sftpService = SFTPService(connection: connection)
                    
                    // 自动获取当前路径
                    self?.getCurrentDirectory()
                    
                case .failure(let error):
                    print("🔴 [ViewModel] Connection failed: \(error)")
                    self?.connectionStatus = "连接失败"
                    self?.terminalLines.append(TerminalLine(
                        text: "✗ 连接失败: \(error.localizedDescription)",
                        type: .error
                    ))
                }
            }
        }
        
        print("🟢 [ViewModel] connect() method completed")
    }
    
    private func handleConnectionSuccess(_ connection: SSHConnection) {
        // 连接成功后的初始化工作
    }
    
    func disconnect() {
        guard let connection = activeConnection else { return }
        
        terminalLines.append(TerminalLine(
            text: "\n正在断开连接...",
            type: .system
        ))
        
        sshService?.disconnect()
        sshService = nil
        sftpService = nil
        activeConnection = nil
        connectionStatus = "未连接"
        fileTree = []
        currentPath = "~"
        
        terminalLines.append(TerminalLine(
            text: "✓ 已断开与 \(connection.name) 的连接\n",
            type: .system
        ))
    }
    
    // MARK: - 命令执行
    
    func executeCommand() {
        guard let connection = activeConnection,
              let service = sshService,
              !currentCommand.isEmpty else { return }
        
        let cmd = currentCommand.trimmingCharacters(in: .whitespaces)
        
        // 添加命令行（带提示符）
        terminalLines.append(TerminalLine(
            text: "\(connection.username)@\(connection.host):\(currentPath)$ \(cmd)",
            type: .command
        ))
        
        // 清空当前输入
        let commandToExecute = currentCommand
        currentCommand = ""
        
        // 特殊命令处理
        if cmd.lowercased() == "clear" {
            clearTerminal()
            return
        }
        
        if cmd.lowercased() == "exit" || cmd.lowercased() == "logout" {
            disconnect()
            return
        }
        
        // 执行命令
        service.executeCommand(commandToExecute) { [weak self] output in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // 显示输出
                if !output.isEmpty {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines where !line.isEmpty {
                        self.terminalLines.append(TerminalLine(
                            text: line,
                            type: .output
                        ))
                    }
                }
                
                // 如果是 cd 命令，更新路径和文件列表
                if cmd.lowercased().hasPrefix("cd ") {
                    self.getCurrentDirectory()
                }
            }
        }
    }
    
    private func clearTerminal() {
        terminalLines.removeAll()
    }
    
    private func handleTerminalOutput(_ output: String, type: TerminalLine.LineType) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            // 过滤掉提示符
            let cleanLine = line.trimmingCharacters(in: .whitespaces)
            if !cleanLine.isEmpty && !cleanLine.hasSuffix("$") {
                terminalLines.append(TerminalLine(
                    text: line,
                    type: type
                ))
            }
        }
    }
    
    // MARK: - 目录和文件操作
    
    private func getCurrentDirectory() {
        guard let service = sshService else { return }
        
        service.executeCommand("pwd") { [weak self] output in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty && !path.contains("$") {
                    self.currentPath = path
                    self.loadDirectory(path: path)
                }
            }
        }
    }
    
    func loadDirectory(path: String) {
        guard let service = sftpService else { return }
        
        isLoadingFiles = true
        
        service.listDirectory(path: path) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isLoadingFiles = false
                
                switch result {
                case .success(let files):
                    self.fileTree = files.sorted { item1, item2 in
                        // 目录排在前面
                        if item1.type == .directory && item2.type == .file {
                            return true
                        } else if item1.type == .file && item2.type == .directory {
                            return false
                        }
                        // 同类型按名称排序
                        return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
                    }
                    self.currentPath = path
                    
                case .failure(let error):
                    self.terminalLines.append(TerminalLine(
                        text: "无法加载目录 \(path): \(error.localizedDescription)",
                        type: .error
                    ))
                }
            }
        }
    }
    
    func navigateToDirectory(_ dirName: String) {
        let newPath: String
        if currentPath == "/" {
            newPath = "/\(dirName)"
        } else if currentPath.hasSuffix("/") {
            newPath = currentPath + dirName
        } else {
            newPath = currentPath + "/" + dirName
        }
        
        // 同时在终端中执行 cd 命令
        currentCommand = "cd \(newPath)"
        executeCommand()
    }
    
    func navigateToParent() {
        let components = currentPath.split(separator: "/")
        if components.count > 1 {
            let parentPath = "/" + components.dropLast().joined(separator: "/")
            loadDirectory(path: parentPath)
            
            // 在终端中执行 cd 命令
            currentCommand = "cd \(parentPath)"
            executeCommand()
        } else if currentPath != "/" && currentPath != "~" {
            loadDirectory(path: "~")
            currentCommand = "cd ~"
            executeCommand()
        }
    }
    
    func openFile(_ fileName: String) {
        guard let connection = activeConnection else { return }
        
        let filePath = currentPath.hasSuffix("/") ? currentPath + fileName : currentPath + "/" + fileName
        
        // 在终端中使用 cat 查看文件内容
        terminalLines.append(TerminalLine(
            text: "\(connection.username)@\(connection.host):\(currentPath)$ cat \(fileName)",
            type: .command
        ))
        
        sshService?.executeCommand("cat \(filePath)") { [weak self] output in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if !output.isEmpty {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        self.terminalLines.append(TerminalLine(
                            text: line,
                            type: .output
                        ))
                    }
                }
            }
        }
    }
    
    func downloadFile(remotePath: String, localPath: String) {
        guard let service = sftpService else { return }
        
        terminalLines.append(TerminalLine(
            text: "正在下载: \(remotePath) -> \(localPath)",
            type: .system
        ))
        
        service.downloadFile(remotePath: remotePath, localPath: localPath) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success():
                    self?.terminalLines.append(TerminalLine(
                        text: "✓ 下载完成",
                        type: .system
                    ))
                    
                case .failure(let error):
                    self?.terminalLines.append(TerminalLine(
                        text: "✗ 下载失败: \(error.localizedDescription)",
                        type: .error
                    ))
                }
            }
        }
    }
    
    func uploadFile(localPath: String, remotePath: String) {
        guard let service = sftpService else { return }
        
        terminalLines.append(TerminalLine(
            text: "正在上传: \(localPath) -> \(remotePath)",
            type: .system
        ))
        
        service.uploadFile(localPath: localPath, remotePath: remotePath) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success():
                    self?.terminalLines.append(TerminalLine(
                        text: "✓ 上传完成",
                        type: .system
                    ))
                    self?.loadDirectory(path: self?.currentPath ?? "~")
                    
                case .failure(let error):
                    self?.terminalLines.append(TerminalLine(
                        text: "✗ 上传失败: \(error.localizedDescription)",
                        type: .error
                    ))
                }
            }
        }
    }
    
    // MARK: - 连接列表管理
    
    func addConnection(_ connection: SSHConnection) {
        connectionManager.addConnection(connection)
        showAddForm = false
        editingConnection = nil
    }
    
    func updateConnection(_ connection: SSHConnection) {
        connectionManager.updateConnection(connection)
        showAddForm = false
        editingConnection = nil
        
        // 如果更新的是当前连接，断开并提示重新连接
        if activeConnection?.id == connection.id {
            terminalLines.append(TerminalLine(
                text: "连接配置已更新，请重新连接",
                type: .system
            ))
            disconnect()
        }
    }
    
    func editConnection(_ connection: SSHConnection) {
        editingConnection = connection
        showAddForm = true
    }
    
    func deleteConnection(_ connection: SSHConnection) {
        // 如果正在使用该连接，先断开
        if activeConnection?.id == connection.id {
            disconnect()
        }
        connectionManager.deleteConnection(connection)
    }
}

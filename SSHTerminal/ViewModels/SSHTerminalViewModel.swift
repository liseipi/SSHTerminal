import SwiftUI
import Combine

class SSHTerminalViewModel: ObservableObject {
    @Published var connections: [SSHConnection] = []
    @Published var tabs: [TerminalTab] = []
    @Published var activeTabId: UUID?
    @Published var showAddForm: Bool = false
    @Published var editingConnection: SSHConnection?
    @Published var isConnecting: Bool = false
    
    private let connectionManager = ConnectionManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // 当前活动的 Tab
    var activeTab: TerminalTab? {
        guard let id = activeTabId else { return nil }
        return tabs.first(where: { $0.id == id })
    }
    
    // 当前 Tab 的索引
    private var activeTabIndex: Int? {
        guard let id = activeTabId else { return nil }
        return tabs.firstIndex(where: { $0.id == id })
    }
    
    init() {
        connectionManager.$connections
            .assign(to: \.connections, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Tab 管理
    
    func createTab(for connection: SSHConnection) {
        print("🔵 [ViewModel] createTab() called for: \(connection.name)")
        
        // 检查是否已有该连接的 Tab
        if let existingTab = tabs.first(where: { $0.connection.id == connection.id }) {
            print("🟡 [ViewModel] Tab already exists, switching to it")
            activeTabId = existingTab.id
            return
        }
        
        // 创建新 Tab
        let newTab = TerminalTab(connection: connection)
        tabs.append(newTab)
        activeTabId = newTab.id
        
        // 自动连接
        connect(to: connection, tabId: newTab.id)
    }
    
    func closeTab(_ tabId: UUID) {
        print("🔵 [ViewModel] closeTab() called for: \(tabId)")
        
        // 找到要关闭的 Tab
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        
        // 断开连接
        if let service = tabs[index].sshService {
            print("🔵 [ViewModel] Disconnecting service for tab")
            service.disconnect()
        }
        
        // 移除 Tab
        tabs.remove(at: index)
        
        // 如果关闭的是当前 Tab,切换到其他 Tab
        if activeTabId == tabId {
            activeTabId = tabs.last?.id
        }
    }
    
    func switchTab(to tabId: UUID) {
        print("🔵 [ViewModel] switchTab() to: \(tabId)")
        activeTabId = tabId
        
        // 检查切换后的 Tab 状态
        if let index = tabs.firstIndex(where: { $0.id == tabId }) {
            print("🔍 [ViewModel] Switched tab status:")
            print("  - Connection: \(tabs[index].connection.name)")
            print("  - Status: \(tabs[index].connectionStatus)")
            print("  - Service exists: \(tabs[index].sshService != nil)")
            if let service = tabs[index].sshService {
                print("  - Service isConnected: \(service.isConnected)")
            }
        }
    }
    
    // MARK: - 连接管理
    
    func connect(to connection: SSHConnection, tabId: UUID) {
        print("🔵 [ViewModel] connect() called for tab: \(tabId)")
        
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else {
            print("🔴 [ViewModel] Tab not found!")
            return
        }
        
        guard !isConnecting else {
            print("⚠️ [ViewModel] Already connecting, ignoring request")
            return
        }
        
        isConnecting = true
        tabs[index].connectionStatus = "正在连接..."
        
        // 添加系统消息
        tabs[index].terminalLines.append(TerminalLine(
            text: "正在连接到 \(connection.username)@\(connection.host):\(connection.port)...",
            type: .system
        ))
        
        // 创建 SSH 服务并强引用
        let service = SSHService()
        print("🟢 [ViewModel] Created SSHService instance")
        
        // 重要：立即保存到 Tab 中，确保引用不被释放
        tabs[index].sshService = service
        print("🟢 [ViewModel] SSHService assigned to tab")
        
        // 监听输出
        service.onOutputReceived = { [weak self] output, type in
            self?.handleTerminalOutput(output, type: type, tabId: tabId)
        }
        
        // 发起连接
        service.connect(to: connection) { [weak self] result in
            DispatchQueue.main.async {
                self?.isConnecting = false
                
                guard let self = self,
                      let index = self.tabs.firstIndex(where: { $0.id == tabId }) else {
                    print("🔴 [ViewModel] Tab disappeared during connection")
                    return
                }
                
                switch result {
                case .success():
                    print("🟢 [ViewModel] Connection successful!")
                    
                    // 验证 service 引用
                    if self.tabs[index].sshService != nil {
                        print("🟢 [ViewModel] Service reference is valid")
                    } else {
                        print("🔴 [ViewModel] Service reference was lost!")
                    }
                    
                    // 等待一小段时间确保进程完全初始化
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard let idx = self.tabs.firstIndex(where: { $0.id == tabId }) else { return }
                        
                        // 再次验证 service
                        if let svc = self.tabs[idx].sshService {
                            print("🔍 [ViewModel] Final check:")
                            print("  - Service exists: true")
                            print("  - Service isConnected: \(svc.isConnected)")
                        } else {
                            print("🔴 [ViewModel] Service lost after delay!")
                        }
                        
                        self.tabs[idx].connectionStatus = "已连接"
                        self.tabs[idx].terminalLines.append(TerminalLine(
                            text: "✓ 成功连接到 \(connection.name)",
                            type: .system
                        ))
                        
                        // 初始化 SFTP 服务
                        self.tabs[idx].sftpService = SFTPService(connection: connection)
                        
                        // 自动获取当前路径
                        self.getCurrentDirectory(tabId: tabId)
                    }
                    
                case .failure(let error):
                    print("🔴 [ViewModel] Connection failed: \(error)")
                    self.tabs[index].connectionStatus = "连接失败"
                    self.tabs[index].terminalLines.append(TerminalLine(
                        text: "✗ 连接失败: \(error.localizedDescription)",
                        type: .error
                    ))
                }
            }
        }
    }
    
    func disconnect(tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        
        tabs[index].terminalLines.append(TerminalLine(
            text: "\n正在断开连接...",
            type: .system
        ))
        
        tabs[index].sshService?.disconnect()
        tabs[index].sshService = nil
        tabs[index].sftpService = nil
        tabs[index].connectionStatus = "未连接"
        tabs[index].fileTree = []
        tabs[index].currentPath = "~"
        
        tabs[index].terminalLines.append(TerminalLine(
            text: "✓ 已断开连接\n",
            type: .system
        ))
    }
    
    // MARK: - 命令执行
    
    func executeCommand(tabId: UUID) {
        print("🔵 [ViewModel.executeCommand] Called for tab: \(tabId)")
        
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else {
            print("🔴 [ViewModel.executeCommand] Tab not found!")
            return
        }
        
        // 检查 service 引用
        if tabs[index].sshService == nil {
            print("🔴 [ViewModel.executeCommand] No SSH service!")
            tabs[index].terminalLines.append(TerminalLine(
                text: "错误：SSH 服务不存在，请重新连接",
                type: .error
            ))
            return
        }
        
        guard let service = tabs[index].sshService else {
            print("🔴 [ViewModel.executeCommand] Service guard failed")
            return
        }
        
        guard !tabs[index].currentCommand.isEmpty else {
            print("🔴 [ViewModel.executeCommand] Empty command")
            return
        }
        
        print("🟢 [ViewModel.executeCommand] Starting command execution")
        print("  - Tab index: \(index)")
        print("  - Service exists: \(tabs[index].sshService != nil)")
        print("  - Command: '\(tabs[index].currentCommand)'")
        
        let cmd = tabs[index].currentCommand.trimmingCharacters(in: .whitespaces)
        let connection = tabs[index].connection
        
        // 添加命令行
        tabs[index].terminalLines.append(TerminalLine(
            text: "\(connection.username)@\(connection.host):\(tabs[index].currentPath)$ \(cmd)",
            type: .command
        ))
        
        // 清空当前输入
        let commandToExecute = tabs[index].currentCommand
        tabs[index].currentCommand = ""
        
        // 特殊命令处理
        if cmd.lowercased() == "clear" {
            tabs[index].terminalLines.removeAll()
            return
        }
        
        if cmd.lowercased() == "exit" || cmd.lowercased() == "logout" {
            disconnect(tabId: tabId)
            return
        }
        
        // 检查是否是 cd 命令
        let isCdCommand = cmd.lowercased().hasPrefix("cd ")
        
        print("🟢 [ViewModel.executeCommand] Calling service.executeCommand")
        
        // 执行命令
        service.executeCommand(commandToExecute) { [weak self] output in
            DispatchQueue.main.async {
                guard let self = self,
                      let index = self.tabs.firstIndex(where: { $0.id == tabId }) else { return }
                
                print("🟢 [ViewModel.executeCommand] Got response: '\(output)'")
                
                if !output.isEmpty && !output.hasPrefix("错误") {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines where !line.isEmpty {
                        self.tabs[index].terminalLines.append(TerminalLine(
                            text: line,
                            type: .output
                        ))
                    }
                } else if output.hasPrefix("错误") {
                    self.tabs[index].terminalLines.append(TerminalLine(
                        text: output,
                        type: .error
                    ))
                }
                
                // 如果是 cd 命令,延迟一下再更新路径和文件列表
                if isCdCommand && !output.hasPrefix("错误") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.getCurrentDirectory(tabId: tabId)
                    }
                }
            }
        }
    }
    
    private func handleTerminalOutput(_ output: String, type: TerminalLine.LineType, tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        
        let lines = output.components(separatedBy: .newlines)
        for line in lines where !line.isEmpty {
            let cleanLine = line.trimmingCharacters(in: .whitespaces)
            if !cleanLine.isEmpty && !cleanLine.hasSuffix("$") {
                tabs[index].terminalLines.append(TerminalLine(
                    text: line,
                    type: type
                ))
            }
        }
    }
    
    // MARK: - 目录和文件操作
    
    private func getCurrentDirectory(tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }),
              let service = tabs[index].sshService else {
            print("🔴 [getCurrentDirectory] No service found for tab: \(tabId)")
            return
        }
        
        print("🟢 [getCurrentDirectory] Executing pwd command")
        
        service.executeCommand("pwd") { [weak self] output in
            DispatchQueue.main.async {
                guard let self = self,
                      let index = self.tabs.firstIndex(where: { $0.id == tabId }) else { return }
                
                let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
                print("🟢 [getCurrentDirectory] Got path: '\(path)'")
                
                if !path.isEmpty && !path.contains("$") && !path.contains("错误") {
                    self.tabs[index].currentPath = path
                    self.loadDirectory(path: path, tabId: tabId)
                } else {
                    print("🔴 [getCurrentDirectory] Invalid path output")
                }
            }
        }
    }
    
    func loadDirectory(path: String, tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }),
              let service = tabs[index].sftpService else {
            print("🔴 [loadDirectory] No SFTP service for tab: \(tabId)")
            return
        }
        
        print("🟢 [loadDirectory] Loading directory: \(path)")
        tabs[index].isLoadingFiles = true
        
        service.listDirectory(path: path) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self,
                      let index = self.tabs.firstIndex(where: { $0.id == tabId }) else { return }
                
                self.tabs[index].isLoadingFiles = false
                
                switch result {
                case .success(let files):
                    print("🟢 [loadDirectory] Got \(files.count) files")
                    self.tabs[index].fileTree = files.sorted { item1, item2 in
                        if item1.type == .directory && item2.type == .file {
                            return true
                        } else if item1.type == .file && item2.type == .directory {
                            return false
                        }
                        return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
                    }
                    self.tabs[index].currentPath = path
                    
                case .failure(let error):
                    print("🔴 [loadDirectory] Error: \(error)")
                    self.tabs[index].terminalLines.append(TerminalLine(
                        text: "无法加载目录 \(path): \(error.localizedDescription)",
                        type: .error
                    ))
                }
            }
        }
    }
    
    func navigateToDirectory(_ dirName: String, tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        
        let currentPath = tabs[index].currentPath
        let newPath: String
        if currentPath == "/" {
            newPath = "/\(dirName)"
        } else if currentPath.hasSuffix("/") {
            newPath = currentPath + dirName
        } else {
            newPath = currentPath + "/" + dirName
        }
        
        tabs[index].currentCommand = "cd \(newPath)"
        executeCommand(tabId: tabId)
    }
    
    func navigateToParent(tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        
        let currentPath = tabs[index].currentPath
        let components = currentPath.split(separator: "/")
        if components.count > 1 {
            let parentPath = "/" + components.dropLast().joined(separator: "/")
            tabs[index].currentCommand = "cd \(parentPath)"
            executeCommand(tabId: tabId)
        } else if currentPath != "/" && currentPath != "~" {
            tabs[index].currentCommand = "cd ~"
            executeCommand(tabId: tabId)
        }
    }
    
    func openFile(_ fileName: String, tabId: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == tabId }) else { return }
        
        let connection = tabs[index].connection
        let currentPath = tabs[index].currentPath
        let filePath = currentPath.hasSuffix("/") ? currentPath + fileName : currentPath + "/" + fileName
        
        tabs[index].terminalLines.append(TerminalLine(
            text: "\(connection.username)@\(connection.host):\(currentPath)$ cat \(fileName)",
            type: .command
        ))
        
        tabs[index].sshService?.executeCommand("cat \(filePath)") { [weak self] output in
            DispatchQueue.main.async {
                guard let self = self,
                      let index = self.tabs.firstIndex(where: { $0.id == tabId }) else { return }
                
                if !output.isEmpty {
                    let lines = output.components(separatedBy: .newlines)
                    for line in lines {
                        self.tabs[index].terminalLines.append(TerminalLine(
                            text: line,
                            type: .output
                        ))
                    }
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
        
        // 如果有使用该连接的 Tab,提示重新连接
        for tab in tabs where tab.connection.id == connection.id {
            disconnect(tabId: tab.id)
        }
    }
    
    func editConnection(_ connection: SSHConnection) {
        editingConnection = connection
        showAddForm = true
    }
    
    func deleteConnection(_ connection: SSHConnection) {
        // 关闭所有使用该连接的 Tab
        let tabsToClose = tabs.filter { $0.connection.id == connection.id }
        for tab in tabsToClose {
            closeTab(tab.id)
        }
        connectionManager.deleteConnection(connection)
    }
}

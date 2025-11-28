import Foundation
import Combine

// MARK: - SSH 会话管理器
class SSHSessionManager: ObservableObject {
    @Published var output: String = ""
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var error: String?
    
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var keepAliveTimer: Timer?
    private var outputQueue = DispatchQueue(label: "ssh.output", qos: .userInteractive)
    
    var connection: SSHConnection?
    
    // MARK: - 连接到服务器
    func connect(to connection: SSHConnection) {
        guard !isConnecting && !isConnected else { return }
        
        self.connection = connection
        isConnecting = true
        error = nil
        output = ""
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.startSSHSession(connection)
        }
    }
    
    // MARK: - 启动 SSH 会话
    private func startSSHSession(_ connection: SSHConnection) {
        do {
            let process = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            
            print("🔗 开始连接...")
            print("   主机: \(connection.host)")
            print("   端口: \(connection.port)")
            print("   用户: \(connection.username)")
            print("   认证方式: \(connection.authMethod.rawValue)")
            
            // 根据认证方式构建命令
            if connection.authMethod == .password {
                if let password = connection.password {
                    print("🔐 使用密码认证（密码长度: \(password.count)）")
                    
                    // 使用 expect 自动输入密码
                    let expectScript = createExpectScriptFile(connection: connection, password: password)
                    
                    if expectScript.isEmpty {
                        throw NSError(domain: "SSHSession", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法创建 expect 脚本"])
                    }
                    
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
                    process.arguments = [expectScript]
                    
                    print("📜 expect 脚本: \(expectScript)")
                } else {
                    print("❌ 错误: 密码认证但没有密码")
                    throw NSError(domain: "SSHSession", code: -2, userInfo: [NSLocalizedDescriptionKey: "密码为空"])
                }
            } else {
                // 密钥认证
                print("🔑 使用密钥认证")
                
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                var args = [
                    "-o", "StrictHostKeyChecking=no",
                    "-t"  // 强制分配伪终端
                ]
                
                if connection.port != 22 {
                    args.append(contentsOf: ["-p", "\(connection.port)"])
                }
                
                if let keyPath = connection.privateKeyPath {
                    args.append(contentsOf: ["-i", keyPath])
                    print("   密钥路径: \(keyPath)")
                }
                
                args.append("\(connection.username)@\(connection.host)")
                process.arguments = args
            }
            
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = outputPipe
            
            // 设置环境变量
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            env["LANG"] = "en_US.UTF-8"
            env["LC_ALL"] = "en_US.UTF-8"
            process.environment = env
            
            self.process = process
            self.inputPipe = inputPipe
            self.outputPipe = outputPipe
            
            // 监听输出
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if !data.isEmpty {
                    if let newOutput = String(data: data, encoding: .utf8) {
                        self?.outputQueue.async {
                            DispatchQueue.main.async {
                                // 直接添加原始输出，不做处理
                                self?.output.append(newOutput)
                            }
                        }
                    }
                }
            }
            
            // 启动进程
            try process.run()
            
            print("✅ SSH 进程已启动，PID: \(process.processIdentifier)")
            
            DispatchQueue.main.async { [weak self] in
                self?.isConnecting = false
                self?.isConnected = true
                self?.startKeepAlive()
            }
            
            // 等待进程结束
            process.waitUntilExit()
            
            print("⚠️ SSH 进程已退出，状态: \(process.terminationStatus)")
            
            DispatchQueue.main.async { [weak self] in
                self?.isConnected = false
                self?.stopKeepAlive()
                
                if process.terminationStatus != 0 {
                    self?.error = "连接已断开（退出码: \(process.terminationStatus)）"
                }
            }
            
        } catch {
            print("❌ 启动 SSH 会话失败: \(error)")
            DispatchQueue.main.async { [weak self] in
                self?.isConnecting = false
                self?.error = "连接失败: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - 创建 expect 脚本文件
    private func createExpectScriptFile(connection: SSHConnection, password: String) -> String {
        let tempDir: URL
        if let realTempDir = getenv("TMPDIR") {
            tempDir = URL(fileURLWithPath: String(cString: realTempDir))
        } else {
            tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = UUID().uuidString.prefix(8)
        let scriptFile = tempDir.appendingPathComponent("ssh_\(timestamp)_\(random).exp")
        
        // 转义密码
        let escapedPwd = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        
        let sshCommand = "ssh -p \(connection.port) -o StrictHostKeyChecking=no \(connection.username)@\(connection.host)"
        
        let expectScript = """
        #!/usr/bin/expect -f
        set timeout 30
        log_user 0
        
        spawn \(sshCommand)
        
        expect {
            -re "(?i)(are you sure|fingerprint)" {
                send "yes\\r"
                exp_continue
            }
            -re "(?i)(password:|password for|'s password:)" {
                send "\(escapedPwd)\\r"
            }
            "Permission denied" {
                puts "\\nERROR: Authentication failed"
                exit 1
            }
            timeout {
                puts "\\nERROR: Connection timeout"
                exit 1
            }
        }
        
        expect {
            -re "\\$|#|>" {
                log_user 1
            }
            "Permission denied" {
                puts "\\nERROR: Authentication failed"
                exit 1
            }
            timeout {
                log_user 1
            }
        }
        
        interact
        """
        
        do {
            try expectScript.write(to: scriptFile, atomically: true, encoding: .utf8)
            
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["755", scriptFile.path]
            try? chmodProcess.run()
            chmodProcess.waitUntilExit()
            
            // 延迟删除
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
                try? FileManager.default.removeItem(at: scriptFile)
            }
            
            return scriptFile.path
        } catch {
            print("❌ 创建 expect 脚本失败: \(error)")
            return ""
        }
    }
    private func createExpectScript(connection: SSHConnection, password: String) -> String {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptFile = tempDir.appendingPathComponent("ssh_expect_\(UUID().uuidString).exp")
        
        let escapedPwd = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
        
        let sshCommand = connection.authMethod == .publicKey && connection.privateKeyPath != nil
            ? "ssh -i \(connection.privateKeyPath!) -p \(connection.port) \(connection.username)@\(connection.host)"
            : "ssh -p \(connection.port) \(connection.username)@\(connection.host)"
        
        let expectScript = """
        #!/usr/bin/expect -f
        set timeout 30
        log_user 1
        
        spawn \(sshCommand)
        
        expect {
            -re "(?i)(are you sure|fingerprint)" {
                send "yes\\r"
                exp_continue
            }
            -re "(?i)(password:|password for)" {
                send "\(escapedPwd)\\r"
            }
            timeout {
                puts "连接超时"
                exit 1
            }
        }
        
        interact
        """
        
        try? expectScript.write(to: scriptFile, atomically: true, encoding: .utf8)
        
        // 设置可执行权限
        let chmodProcess = Process()
        chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
        chmodProcess.arguments = ["+x", scriptFile.path]
        try? chmodProcess.run()
        chmodProcess.waitUntilExit()
        
        // 延迟删除
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            try? FileManager.default.removeItem(at: scriptFile)
        }
        
        return scriptFile.path
    }
    
    // MARK: - 发送命令
    func sendCommand(_ command: String) {
        guard let inputPipe = inputPipe, isConnected else { return }
        
        let data = (command + "\n").data(using: .utf8)!
        inputPipe.fileHandleForWriting.write(data)
    }
    
    // MARK: - 发送按键
    func sendInput(_ text: String) {
        guard let inputPipe = inputPipe, isConnected else { return }
        
        if let data = text.data(using: .utf8) {
            do {
                try inputPipe.fileHandleForWriting.write(contentsOf: data)
            } catch {
                print("❌ 发送输入失败: \(error)")
            }
        }
    }
    
    // MARK: - 断开连接
    func disconnect() {
        stopKeepAlive()
        
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        
        isConnected = false
        isConnecting = false
    }
    
    // MARK: - 保持连接活跃
    private func startKeepAlive() {
        // 每 30 秒发送一个空命令保持连接
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendInput("\0")  // 发送空字符保持连接
        }
    }
    
    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }
    
    deinit {
        disconnect()
    }
}

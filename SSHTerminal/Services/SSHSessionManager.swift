import Foundation
import Combine

// MARK: - SSH 会话管理器（线程安全版）
@MainActor
class SSHSessionManager: ObservableObject {
    @Published var output: String = ""
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var error: String?
    
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var keepAliveTimer: Timer?
    
    var connection: SSHConnection?
    
    // MARK: - 连接到服务器
    nonisolated func connect(to connection: SSHConnection) {
        print("🟢 [Session] connect() 被调用，线程: \(Thread.current)")
        
        // 使用 Task 在 MainActor 上执行
        Task { @MainActor in
            guard !self.isConnecting && !self.isConnected else {
                print("⚠️ [Session] 已经在连接中或已连接，忽略")
                return
            }
            
            self.connection = connection
            
            print("🟢 [Session] 更新 UI 状态")
            self.isConnecting = true
            self.error = nil
            self.output = ""
            
            print("🟢 [Session] 准备启动 SSH")
            
            // 在后台任务中启动 SSH
            Task.detached { [weak self] in
                print("🟢 [Session] 后台任务开始")
                await self?.startSSHSession(connection)
            }
        }
    }
    
    // MARK: - 启动 SSH 会话
    private func startSSHSession(_ connection: SSHConnection) async {
        print("🟢 [SSH] startSSHSession 开始，线程: \(Thread.current)")
        
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
                print("🔑 使用密钥认证")
                
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                var args = [
                    "-o", "StrictHostKeyChecking=no",
                    "-t"
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
            
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            env["LANG"] = "en_US.UTF-8"
            env["LC_ALL"] = "en_US.UTF-8"
            process.environment = env
            
            self.process = process
            self.inputPipe = inputPipe
            self.outputPipe = outputPipe
            
            print("🟢 [SSH] 设置输出监听器")
            
            let fileHandle = outputPipe.fileHandleForReading
            
            fileHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                
                if let newOutput = String(data: data, encoding: .utf8) {
                    print("📥 [SSH] 收到输出，长度: \(newOutput.count)")
                    
                    // ⭐️ 使用 Task 在 MainActor 上更新
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        print("📥 [SSH] 追加到 output，当前长度: \(self.output.count)")
                        self.output.append(newOutput)
                        print("📥 [SSH] 追加后长度: \(self.output.count)")
                    }
                } else {
                    print("⚠️ [SSH] 无法解码输出数据")
                }
            }
            
            print("🟢 [SSH] 准备启动进程")
            
            try process.run()
            
            print("✅ SSH 进程已启动，PID: \(process.processIdentifier)")
            print("🟢 [SSH] 进程正在运行: \(process.isRunning)")
            
            // ⭐️ 使用 Task 更新状态
            await MainActor.run {
                print("🟢 [SSH] 更新 UI 状态为已连接")
                self.isConnecting = false
                self.isConnected = true
                self.startKeepAlive()
            }
            
            print("🟢 [SSH] 设置进程终止监听")
            
            process.terminationHandler = { [weak self] proc in
                print("⚠️ SSH 进程已退出，状态: \(proc.terminationStatus)")
                
                fileHandle.readabilityHandler = nil
                
                Task { @MainActor [weak self] in
                    self?.isConnected = false
                    self?.stopKeepAlive()
                    
                    if proc.terminationStatus != 0 {
                        self?.error = "连接已断开（退出码: \(proc.terminationStatus)）"
                    }
                }
            }
            
            print("🟢 [SSH] startSSHSession 完成，进程在后台运行")
            
        } catch {
            print("❌ 启动 SSH 会话失败: \(error)")
            await MainActor.run {
                self.isConnecting = false
                self.error = "连接失败: \(error.localizedDescription)"
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
    
    // MARK: - 发送输入
    nonisolated func sendInput(_ text: String) {
        Task {
            await sendInputAsync(text)
        }
    }
    
    private func sendInputAsync(_ text: String) async {
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
    nonisolated func disconnect() {
        Task { @MainActor in
            self.stopKeepAlive()
            
            self.process?.terminate()
            self.process = nil
            self.inputPipe = nil
            self.outputPipe = nil
            
            self.isConnected = false
            self.isConnecting = false
        }
    }
    
    // MARK: - 保持连接活跃
    private func startKeepAlive() {
        // 每 30 秒发送一个空命令保持连接
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendInput("\0")
        }
    }
    
    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
    }
    
    deinit {
        // ⭐️ 直接清理，不调用 disconnect()
        process?.terminate()
        keepAliveTimer?.invalidate()
    }
}

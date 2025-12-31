internal import Foundation
internal import SwiftUI
internal import SwiftTerm
internal import Combine

// MARK: - SSH 会话管理器
@MainActor
class SwiftTermSSHManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var error: String?
    
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var keepAliveTimer: Timer?
    
    var connection: SSHConnection?
    var terminalSize: (cols: Int, rows: Int) = (80, 24)
    
    // 使用闭包而不是协议，避免循环引用
    var onDataReceived: ((Data) -> Void)?
    
    // MARK: - 连接到服务器
    func connect(to connection: SSHConnection) {
        guard !isConnecting && !isConnected else { return }
        
        self.connection = connection
        self.isConnecting = true
        self.error = nil
        
        Task.detached { [weak self] in
            await self?.startSSHSession(connection)
        }
    }
    
    // MARK: - 启动 SSH 会话
    private func startSSHSession(_ connection: SSHConnection) async {
        do {
            let process = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            print("🔗 开始连接: \(connection.host):\(connection.port)")
            
            // 根据认证方式构建命令
            if connection.authMethod == .password {
                if let password = connection.password {
                    print("🔐 使用密码认证，密码长度: \(password.count)")
                    
                    // 检查 sshpass 是否可用
                    if isCommandAvailable("sshpass") {
                        print("   使用 sshpass")
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/sshpass")
                        
                        var args = ["-p", password, "ssh"]
                        args.append(contentsOf: [
                            "-p", "\(connection.port)",
                            "-o", "StrictHostKeyChecking=no",
                            "-o", "ServerAliveInterval=60",
                            "-o", "ServerAliveCountMax=10",
                            "-o", "TCPKeepAlive=yes",
                            "-o", "ConnectTimeout=30",
                            "-t",
                            "\(connection.username)@\(connection.host)"
                        ])
                        
                        process.arguments = args
                    } else {
                        print("   sshpass 不可用，使用 expect 脚本")
                        
                        // ⭐️ 修改：创建脚本并将密码作为参数传递
                        let scriptPath = createExpectScriptFile(connection: connection)
                        
                        if scriptPath.isEmpty {
                            throw NSError(domain: "SSHSession", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "无法创建 expect 脚本"])
                        }
                        
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
                        // ⭐️ 关键：将密码作为参数传递
                        process.arguments = [scriptPath, password]
                    }
                } else {
                    throw NSError(domain: "SSHSession", code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "密码为空"])
                }
            } else {
                // 密钥认证
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                var args = [
                    "-p", "\(connection.port)",
                    "-o", "StrictHostKeyChecking=no",
                    "-o", "ServerAliveInterval=60",
                    "-o", "ServerAliveCountMax=10",
                    "-o", "TCPKeepAlive=yes",
                    "-o", "ConnectTimeout=30",
                    "-t"  // 强制分配 PTY
                ]
                
                if let keyPath = connection.privateKeyPath {
                    args.append(contentsOf: ["-i", keyPath])
                }
                
                args.append("\(connection.username)@\(connection.host)")
                process.arguments = args
            }
            
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // ⭐️ 关键修复：设置正确的环境变量
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            env["LANG"] = "zh_CN.UTF-8"       // ✅ 改为中文
            env["LC_ALL"] = "zh_CN.UTF-8"      // ✅ 改为中文
            env["LC_CTYPE"] = "zh_CN.UTF-8"    // ✅ 添加此项
            env["COLUMNS"] = "\(terminalSize.cols)"
            env["LINES"] = "\(terminalSize.rows)"
            process.environment = env
            
            // 设置输出处理
            setupOutputHandler(outputPipe.fileHandleForReading, isError: false)
            setupOutputHandler(errorPipe.fileHandleForReading, isError: true)
            
            // 保存引用
            self.process = process
            self.inputPipe = inputPipe
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe
            
            try process.run()
            
            print("✅ SSH 进程已启动，PID: \(process.processIdentifier)")
            
            await MainActor.run {
                self.isConnecting = false
                self.isConnected = true
                self.startKeepAlive()
                
                // ⭐️ 连接成功后发送终端尺寸设置命令
                self.sendTerminalSizeUpdate()
            }
            
            process.terminationHandler = { [weak self] proc in
                print("⚠️ SSH 进程已退出，状态: \(proc.terminationStatus)")
                
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.stopKeepAlive()
                    self.isConnected = false
                    
                    if proc.terminationStatus != 0 {
                        self.error = "连接已断开（退出码: \(proc.terminationStatus)）"
                    }
                    
                    self.process = nil
                    self.inputPipe = nil
                    self.outputPipe = nil
                    self.errorPipe = nil
                }
            }
            
        } catch {
            print("❌ 启动 SSH 会话失败: \(error)")
            await MainActor.run {
                self.isConnecting = false
                self.error = "连接失败: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - 设置输出处理器
    private func setupOutputHandler(_ fileHandle: FileHandle, isError: Bool = false) {
        fileHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            
            Task { @MainActor [weak self] in
                self?.onDataReceived?(data)
            }
        }
    }
    
    // MARK: - 发送输入
    func send(data: Data) {
        guard let inputPipe = inputPipe, isConnected else { return }
        
        Task.detached {
            do {
                try inputPipe.fileHandleForWriting.write(contentsOf: data)
            } catch {
                print("❌ 发送数据失败: \(error)")
            }
        }
    }
    
    // ⭐️ 新增：更新终端尺寸
    func updateTerminalSize(cols: Int, rows: Int) {
        terminalSize = (cols, rows)
        
        if isConnected {
            sendTerminalSizeUpdate()
        }
    }
    
    // ⭐️ 发送终端尺寸更新（通过 stty）
    private func sendTerminalSizeUpdate() {
        // 通过发送 stty 命令来更新远程终端尺寸
        let command = "stty cols \(terminalSize.cols) rows \(terminalSize.rows)\r"
        if let data = command.data(using: .utf8) {
            send(data: data)
        }
    }
    
    // MARK: - 断开连接
    func disconnect() {
        stopKeepAlive()
        
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        
        isConnected = false
        isConnecting = false
    }
    
    // MARK: - 保活定时器
    private func startKeepAlive() {
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isConnected else { return }
                
                print("💓 发送保活信号")
                // 发送一个空格加退格，不会影响终端显示
                let keepAliveData = Data([32, 8]) // 空格 + 退格
                self.send(data: keepAliveData)
            }
        }
        
        if let timer = keepAliveTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
        
        print("💓 保活定时器已启动（每 3 分钟）")
    }
    
    private func stopKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        print("💓 保活定时器已停止")
    }
    
    // MARK: - 创建 expect 脚本
    private func createExpectScriptFile(connection: SSHConnection) -> String {
        let tempDir: URL
        if let realTempDir = getenv("TMPDIR") {
            tempDir = URL(fileURLWithPath: String(cString: realTempDir))
        } else {
            tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = UUID().uuidString.prefix(8)
        let scriptFile = tempDir.appendingPathComponent("ssh_\(timestamp)_\(random).exp")
        
        let sshCommand = "ssh -p \(connection.port) -o StrictHostKeyChecking=no -o ConnectTimeout=30 -o ServerAliveInterval=60 -t \(connection.username)@\(connection.host)"
        
        // ⭐️ expect 脚本：从命令行参数读取密码
        let expectScript = """
    #!/usr/bin/expect -f
    set timeout 60
    log_user 1

    # 从命令行参数获取密码
    if {[llength $argv] < 1} {
        puts "错误：缺少密码参数"
        exit 1
    }
    set password [lindex $argv 0]

    # 设置环境变量
    set env(TERM) "xterm-256color"
    set env(LANG) "zh_CN.UTF-8"
    set env(LC_ALL) "zh_CN.UTF-8"
    set env(LC_CTYPE) "zh_CN.UTF-8"

    # 启动 SSH 连接
    puts "🔗 Connecting to \(connection.host):\(connection.port)..."
    spawn \(sshCommand)

    # 等待密码提示或其他交互
    expect {
        -re "(?i)(are you sure|fingerprint)" {
            puts "🔑 接受主机密钥..."
            send "yes\\r"
            exp_continue
        }
        -re "(?i)(password:|password for)" {
            puts "🔐 输入密码..."
            send -- "$password\\r"
            exp_continue
        }
        -re "(?i)(permission denied|access denied)" {
            puts "\\n❌ 认证失败：密码错误或权限不足"
            exit 1
        }
        -re ".*(@|\\\\$|#|%|>).*" {
            puts "\\n✅ 登录成功"
        }
        -re "Connection refused" {
            puts "\\n❌ 连接被拒绝"
            exit 1
        }
        -re "No route to host" {
            puts "\\n❌ 无法访问主机"
            exit 1
        }
        -re "Name or service not known" {
            puts "\\n❌ 主机名解析失败"
            exit 1
        }
        timeout {
            puts "\\n❌ 连接超时"
            exit 1
        }
        eof {
            puts "\\n❌ 连接意外关闭"
            exit 1
        }
    }

    # 进入交互模式
    interact
    """
        
        do {
            try expectScript.write(to: scriptFile, atomically: true, encoding: .utf8)
            
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["755", scriptFile.path]
            try? chmodProcess.run()
            chmodProcess.waitUntilExit()
            
            print("✅ Expect 脚本已创建: \(scriptFile.path)")
            
            // 5分钟后删除临时文件
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
                try? FileManager.default.removeItem(at: scriptFile)
            }
            
            // ⭐️ 返回脚本路径（不是完整命令）
            return scriptFile.path
        } catch {
            print("❌ 创建 expect 脚本失败: \(error)")
            return ""
        }
    }
    
    deinit {
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        process?.terminate()
        print("💓 SwiftTermSSHManager 已释放")
    }
    
    // MARK: - 检查命令是否可用
    private func isCommandAvailable(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

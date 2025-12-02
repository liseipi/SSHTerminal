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
    
    var connection: SSHConnection?
    
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
                        process.arguments = ["-p", password, "ssh", "-p", "\(connection.port)",
                                           "-o", "StrictHostKeyChecking=no", "-t",
                                           "\(connection.username)@\(connection.host)"]
                    } else {
                        print("   sshpass 不可用，使用 expect 脚本")
                        let expectScript = createExpectScriptFile(connection: connection, password: password)
                        
                        if expectScript.isEmpty {
                            throw NSError(domain: "SSHSession", code: -1,
                                        userInfo: [NSLocalizedDescriptionKey: "无法创建 expect 脚本"])
                        }
                        
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
                        process.arguments = [expectScript]
                    }
                } else {
                    throw NSError(domain: "SSHSession", code: -2,
                                userInfo: [NSLocalizedDescriptionKey: "密码为空"])
                }
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                var args = [
                    "-o", "StrictHostKeyChecking=no",
                    "-t",  // 强制分配 PTY
                    "-o", "ServerAliveInterval=30",
                    "-o", "ServerAliveCountMax=3"
                ]
                
                if connection.port != 22 {
                    args.append(contentsOf: ["-p", "\(connection.port)"])
                }
                
                if let keyPath = connection.privateKeyPath {
                    args.append(contentsOf: ["-i", keyPath])
                }
                
                args.append("\(connection.username)@\(connection.host)")
                process.arguments = args
            }
            
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "xterm-256color"
            env["LANG"] = "en_US.UTF-8"
            env["LC_ALL"] = "en_US.UTF-8"
            process.environment = env
            
            self.process = process
            self.inputPipe = inputPipe
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe
            
            // 设置输出处理
            setupOutputHandler(outputPipe.fileHandleForReading, isError: false)
            setupOutputHandler(errorPipe.fileHandleForReading, isError: true)
            
            try process.run()
            
            print("✅ SSH 进程已启动，PID: \(process.processIdentifier)")
            if connection.authMethod == .password {
                print("   使用 expect 脚本进行密码认证")
            } else {
                print("   使用密钥认证")
            }
            
            await MainActor.run {
                self.isConnecting = false
                self.isConnected = true
            }
            
            process.terminationHandler = { [weak self] proc in
                print("⚠️ SSH 进程已退出，状态: \(proc.terminationStatus)")
                
                // 读取剩余的错误输出
                if let errorData = try? errorPipe.fileHandleForReading.readToEnd(),
                   let errorText = String(data: errorData, encoding: .utf8), !errorText.isEmpty {
                    print("🔴 [SSH Final Error] \(errorText)")
                }
                
                // 清理 readability handler
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                Task { @MainActor [weak self] in
                    self?.isConnected = false
                    
                    if proc.terminationStatus != 0 {
                        self?.error = "连接已断开（退出码: \(proc.terminationStatus)）"
                    }
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
            
            // 打印调试信息
            if let text = String(data: data, encoding: .utf8) {
                let prefix = isError ? "🔴 [Error]" : "🟢 [Output]"
                print("\(prefix) 收到 \(data.count) 字节: \(text.prefix(100))")
            } else {
                let prefix = isError ? "🔴 [Error]" : "🟢 [Output]"
                print("\(prefix) 收到 \(data.count) 字节 (非 UTF-8)")
            }
            
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
    
    // MARK: - 断开连接
    func disconnect() {
        process?.terminate()
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        
        isConnected = false
        isConnecting = false
    }
    
    // MARK: - 创建 expect 脚本
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
        
        let escapedPwd = password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
        
        let sshCommand = "ssh -p \(connection.port) -o StrictHostKeyChecking=no -t \(connection.username)@\(connection.host)"
        
        let expectScript = """
#!/usr/bin/expect -f
set timeout 30

spawn \(sshCommand)

expect {
    -re "(?i)are you sure" {
        send "yes\\r"
        exp_continue
    }
    "assword:" {
        send "\(escapedPwd)\\r"
        exp_continue
    }
    -re "(?i)permission denied" {
        send_user "Auth failed\\r"
        exit 1
    }
    -re "\\\\$|#" {
    }
    timeout {
        send_user "Timeout\\r"
        exit 1
    }
}

interact
"""
        
        do {
            // 确保使用 ASCII 编码写入
            guard let scriptData = expectScript.data(using: .ascii) else {
                print("❌ 无法将脚本转换为 ASCII")
                return ""
            }
            
            try scriptData.write(to: scriptFile)
            
            print("📝 Expect 脚本已创建: \(scriptFile.path)")
            print("   SSH 命令: \(sshCommand)")
            print("   脚本内容前 200 字符:")
            if let preview = String(data: scriptData.prefix(200), encoding: .ascii) {
                print("   \(preview.replacingOccurrences(of: "\n", with: "\\n"))")
            }
            
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["755", scriptFile.path]
            try? chmodProcess.run()
            chmodProcess.waitUntilExit()
            
            print("   权限已设置")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
                try? FileManager.default.removeItem(at: scriptFile)
            }
            
            return scriptFile.path
        } catch {
            print("❌ 创建 expect 脚本失败: \(error)")
            return ""
        }
    }
    
    deinit {
        process?.terminate()
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

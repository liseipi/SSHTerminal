import Foundation
import Combine

class SSHService: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var connectionError: String?
    
    private var sshProcess: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    
    private var connection: SSHConnection?
    private var outputBuffer = ""
    
    var onOutputReceived: ((String, TerminalLine.LineType) -> Void)?
    
    // MARK: - 连接管理
    
    func connect(to connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🔵 [SSHService] Starting connection process...")
        print("🔵 [SSHService] Host: \(connection.host):\(connection.port)")
        print("🔵 [SSHService] User: \(connection.username)")
        print("🔵 [SSHService] Auth: \(connection.authType.rawValue)")
        
        guard !isConnected else {
            print("🔴 [SSHService] Already connected!")
            completion(.failure(SSHError.alreadyConnected))
            return
        }
        
        self.connection = connection
        
        if connection.authType == .password {
            print("🔵 [SSHService] Using password authentication...")
            connectWithPassword(connection, completion: completion)
        } else {
            print("🔵 [SSHService] Using key authentication...")
            connectWithKey(connection, completion: completion)
        }
    }
    
    private func connectWithPassword(_ connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🟡 [connectWithPassword] Starting password-based connection...")
        
        let escapedPassword = connection.password
            .replacingOccurrences(of: "'", with: "'\\''")
        
        // 在沙盒环境中,sshpass 无法使用,直接使用 expect
        let expectCommand = """
        /usr/bin/expect -c '
        set timeout 30
        log_user 1
        
        puts "EXPECT_START"
        spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -p \(connection.port) \(connection.username)@\(connection.host)
        
        puts "EXPECT_SPAWN_DONE"
        
        expect {
            -re "(?i)assword:" {
                puts "EXPECT_PASSWORD_PROMPT"
                send "\(escapedPassword)\\r"
                puts "EXPECT_PASSWORD_SENT"
                expect {
                    -re "\\\\$ |# " {
                        puts "SSH_CONNECTION_READY"
                        interact
                    }
                    -re "(?i)permission denied|(?i)authentication.*failed" {
                        puts "ERROR_AUTH_FAILED"
                        exit 1
                    }
                    timeout {
                        puts "ERROR_AUTH_TIMEOUT"
                        exit 1
                    }
                }
            }
            timeout {
                puts "ERROR_NO_PASSWORD_PROMPT"
                exit 1
            }
            eof {
                puts "ERROR_EARLY_EOF"
                exit 1
            }
        }
        '
        """
        
        print("🟢 [connectWithPassword] Command prepared")
        startSSHProcess(command: expectCommand, connection: connection, completion: completion)
    }
    
    private func connectWithKey(_ connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🟡 [connectWithKey] Starting key-based connection...")
        
        let expandedKeyPath = NSString(string: connection.keyPath).expandingTildeInPath
        
        guard FileManager.default.fileExists(atPath: expandedKeyPath) else {
            print("🔴 [connectWithKey] Key file not found: \(expandedKeyPath)")
            completion(.failure(SSHError.authenticationFailed))
            return
        }
        
        print("🟢 [connectWithKey] Key file found: \(expandedKeyPath)")
        
        // 直接使用 ssh 命令,不需要 expect
        let sshCommand = """
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "\(expandedKeyPath)" -p \(connection.port) \(connection.username)@\(connection.host)
        """
        
        print("🟢 [connectWithKey] Command prepared")
        startSSHProcess(command: sshCommand, connection: connection, completion: completion, useExpect: false)
    }
    
    private func startSSHProcess(command: String, connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void, useExpect: Bool = true) {
        print("🟡 [startSSHProcess] Initializing process...")
        
        sshProcess = Process()
        inputPipe = Pipe()
        outputPipe = Pipe()
        errorPipe = Pipe()
        
        guard let sshProcess = sshProcess,
              let inputPipe = inputPipe,
              let outputPipe = outputPipe,
              let errorPipe = errorPipe else {
            print("🔴 [startSSHProcess] Failed to create pipes!")
            completion(.failure(SSHError.processCreationFailed))
            return
        }
        
        print("🟡 [startSSHProcess] Using bash command")
        sshProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
        sshProcess.arguments = ["-c", command]  // 不使用 -l,避免沙盒权限问题
        
        sshProcess.standardInput = inputPipe
        sshProcess.standardOutput = outputPipe
        sshProcess.standardError = errorPipe
        
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"
        environment["PATH"] = "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        sshProcess.environment = environment
        
        var connectionCompleted = false
        var connectionAttempted = false
        
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let output = String(data: data, encoding: .utf8) {
                let lines = output.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    print("📤 [SSH Output] \(line)")
                }
                
                DispatchQueue.main.async {
                    // 状态跟踪
                    if output.contains("EXPECT_START") {
                        print("🟡 [SSH] Expect script started")
                        connectionAttempted = true
                    }
                    if output.contains("EXPECT_SPAWN_DONE") {
                        print("🟡 [SSH] SSH process spawned")
                    }
                    if output.contains("EXPECT_PASSWORD_PROMPT") {
                        print("🟢 [SSH] Got password prompt!")
                    }
                    if output.contains("EXPECT_PASSWORD_SENT") {
                        print("🟢 [SSH] Password sent!")
                    }
                    
                    // 连接成功检测
                    let successMarkers = ["SSH_CONNECTION_READY"]
                    // 对于 key 认证,检测 shell 提示符
                    let shellPromptPattern = "[$#] $"
                    
                    if (successMarkers.contains(where: output.contains) ||
                        (!useExpect && output.range(of: shellPromptPattern, options: .regularExpression) != nil)) &&
                       !connectionCompleted {
                        print("🟢 [startSSHProcess] Connection success detected!")
                        connectionCompleted = true
                        self?.isConnected = true
                        completion(.success(()))
                    } else if output.contains("ERROR_") && !connectionCompleted {
                        print("🔴 [startSSHProcess] Connection error detected!")
                        connectionCompleted = true
                        
                        if output.contains("ERROR_AUTH_FAILED") {
                            print("🔴 [SSH] Authentication failed")
                            completion(.failure(SSHError.authenticationFailed))
                        } else if output.contains("ERROR_NO_PASSWORD_PROMPT") {
                            print("🔴 [SSH] No password prompt received")
                            completion(.failure(SSHError.connectionFailed))
                        } else if output.contains("ERROR_EARLY_EOF") {
                            print("🔴 [SSH] Connection closed unexpectedly")
                            completion(.failure(SSHError.connectionFailed))
                        } else {
                            completion(.failure(SSHError.connectionFailed))
                        }
                    } else {
                        // 连接成功后才处理输出
                        if self?.isConnected == true {
                            self?.handleOutput(output)
                        }
                    }
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let error = String(data: data, encoding: .utf8) {
                let lines = error.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    // 只打印真正的错误
                    if !line.contains("TIOCGETD") &&
                       !line.contains("NSSecureCoding") &&
                       !line.contains("Warning: Permanently added") {
                        print("⚠️ [SSH Error] \(line)")
                    }
                }
            }
        }
        
        sshProcess.terminationHandler = { [weak self] process in
            print("🔚 [startSSHProcess] Process terminated with exit code: \(process.terminationStatus)")
            DispatchQueue.main.async {
                if !connectionCompleted {
                    print("🔴 [startSSHProcess] Process ended before connection completed!")
                    if !connectionAttempted {
                        print("🔴 [SSH] Connection not attempted - possible script error")
                    }
                    connectionCompleted = true
                    completion(.failure(SSHError.connectionFailed))
                }
                self?.isConnected = false
            }
        }
        
        do {
            print("🚀 [startSSHProcess] Starting process...")
            try sshProcess.run()
            print("🟢 [startSSHProcess] Process started successfully, PID: \(sshProcess.processIdentifier)")
            
            // 连接超时
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
                if !connectionCompleted {
                    print("⏱️ [startSSHProcess] Connection timeout after 30 seconds")
                    if !connectionAttempted {
                        print("🔴 [SSH] No connection attempt detected")
                    }
                    connectionCompleted = true
                    completion(.failure(SSHError.connectionFailed))
                    self?.sshProcess?.terminate()
                }
            }
        } catch {
            print("🔴 [startSSHProcess] Failed to start process: \(error)")
            completion(.failure(error))
        }
    }
    
    // MARK: - 命令执行
    
    func executeCommand(_ command: String, completion: @escaping (String) -> Void) {
        print("🔵 [executeCommand] command: \(command)")
        
        guard isConnected else {
            print("🔴 [executeCommand] Not connected!")
            completion("错误:未连接")
            return
        }
        
        guard let inputPipe = inputPipe else {
            print("🔴 [executeCommand] No input pipe!")
            completion("错误:输入管道不存在")
            return
        }
        
        outputBuffer = ""
        
        // 添加结束标记
        let marker = "CMD_END_\(UUID().uuidString.prefix(8))"
        let fullCommand = "\(command); echo \"\(marker)\"\n"
        
        guard let data = fullCommand.data(using: .utf8) else {
            print("🔴 [executeCommand] Failed to encode command!")
            completion("错误:命令编码失败")
            return
        }
        
        var outputCollected = false
        let originalHandler = onOutputReceived
        
        onOutputReceived = { [weak self] output, type in
            guard let self = self else { return }
            
            if output.contains(marker) {
                if !outputCollected {
                    outputCollected = true
                    let lines = self.outputBuffer.components(separatedBy: .newlines)
                    let filteredLines = lines.filter {
                        !$0.contains(marker) &&
                        !$0.contains("PROMPT>") &&
                        !$0.trimmingCharacters(in: .whitespaces).isEmpty
                    }
                    let result = filteredLines.joined(separator: "\n")
                    print("🟢 [executeCommand] Output: \(result)")
                    completion(result)
                    self.onOutputReceived = originalHandler
                }
            } else {
                self.outputBuffer += output + "\n"
                originalHandler?(output, type)
            }
        }
        
        do {
            print("🟢 [executeCommand] Sending command...")
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                if !outputCollected {
                    outputCollected = true
                    let result = self?.outputBuffer ?? ""
                    completion(result)
                    self?.onOutputReceived = originalHandler
                }
            }
        } catch {
            print("🔴 [executeCommand] Failed: \(error)")
            completion("错误:\(error.localizedDescription)")
            onOutputReceived = originalHandler
        }
    }
    
    private func handleOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.isEmpty ||
               trimmed.hasPrefix("spawn ") ||
               trimmed.contains("SSH_CONNECTION_READY") ||
               trimmed.hasPrefix("PROMPT>") ||
               trimmed.hasPrefix("EXPECT_") ||
               trimmed.hasPrefix("USING_") ||
               trimmed.contains("stty -echo") {
                continue
            }
            
            onOutputReceived?(line, .output)
        }
    }
    
    // MARK: - 断开连接
    
    func disconnect() {
        guard let sshProcess = sshProcess, sshProcess.isRunning else { return }
        if let data = "exit\n".data(using: .utf8) {
            try? inputPipe?.fileHandleForWriting.write(contentsOf: data)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if self?.sshProcess?.isRunning == true {
                self?.sshProcess?.terminate()
            }
        }
        isConnected = false
    }
    
    deinit {
        disconnect()
    }
}

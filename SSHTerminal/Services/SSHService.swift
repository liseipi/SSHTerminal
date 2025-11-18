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
    private var commandQueue: [(command: String, completion: (String) -> Void)] = []
    private var isExecutingCommand = false
    
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
        connectWithExpect(connection, completion: completion)
    }
    
    private func connectWithExpect(_ connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🟡 [connectWithExpect] Using inline expect script...")
        
        let escapedPassword = connection.password
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        
        let expectCommand = """
        /usr/bin/expect << 'EXPECTEOF'
        set timeout 30
        log_user 1
        
        puts "=== Starting SSH connection to \(connection.host) ==="
        
        spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PubkeyAuthentication=no -o PreferredAuthentications=password -o NumberOfPasswordPrompts=3 -v -p \(connection.port) \(connection.username)@\(connection.host)
        
        puts "=== Waiting for password prompt ==="
        
        expect {
            -re "password:" {
                puts "=== PASSWORD PROMPT DETECTED ==="
                sleep 0.1
                send "\(escapedPassword)\\r"
                puts "=== PASSWORD SENT ==="
            }
            -re "Password:" {
                puts "=== PASSWORD PROMPT DETECTED (caps) ==="
                sleep 0.1
                send "\(escapedPassword)\\r"
                puts "=== PASSWORD SENT ==="
            }
            timeout {
                puts "=== ERROR: No password prompt received ==="
                exit 1
            }
            eof {
                puts "=== ERROR: Connection closed before password prompt ==="
                exit 1
            }
        }
        
        puts "=== Waiting for shell prompt ==="
        
        expect {
            -re "\\$|#" {
                puts "=== SUCCESS: Got shell prompt ==="
                send "echo SSH_CONNECTION_READY\\r"
            }
            -re "(?i)permission denied" {
                puts "=== ERROR: Permission denied - wrong password ==="
                exit 1
            }
            -re "(?i)authentication.*failed" {
                puts "=== ERROR: Authentication failed ==="
                exit 1
            }
            timeout {
                puts "=== ERROR: Timeout waiting for shell ==="
                exit 1
            }
            eof {
                puts "=== ERROR: Connection closed after password ==="
                exit 1
            }
        }
        
        expect "SSH_CONNECTION_READY"
        puts "=== Connection established, entering interactive mode ==="
        interact
        EXPECTEOF
        """
        
        print("🟢 [connectWithExpect] Command prepared")
        startSSHProcess(command: expectCommand, scriptPath: nil, connection: connection, completion: completion)
    }
    
    private func connectWithKey(_ connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🟡 [connectWithKey] Using inline expect script for key auth...")
        
        let expandedKeyPath = NSString(string: connection.keyPath).expandingTildeInPath
        
        guard FileManager.default.fileExists(atPath: expandedKeyPath) else {
            print("🔴 [connectWithKey] Key file not found: \(expandedKeyPath)")
            completion(.failure(SSHError.authenticationFailed))
            return
        }
        
        print("🟢 [connectWithKey] Key file found: \(expandedKeyPath)")
        
        let expectCommand = """
        /usr/bin/expect -c '
        set timeout 30
        log_user 1
        
        puts "Starting SSH connection with key..."
        
        spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "\(expandedKeyPath)" -p \(connection.port) \(connection.username)@\(connection.host)
        
        expect {
            "$ " {
                puts "SUCCESS: Connected"
                send "echo SSH_READY\\r"
            }
            "# " {
                puts "SUCCESS: Connected (root)"
                send "echo SSH_READY\\r"
            }
            "Permission denied" {
                puts "ERROR: Permission denied"
                exit 1
            }
            timeout {
                puts "ERROR: Timeout"
                exit 1
            }
            eof {
                puts "ERROR: Connection closed"
                exit 1
            }
        }
        
        expect "SSH_READY"
        puts "Ready for commands"
        interact
        '
        """
        
        print("🟢 [connectWithKey] Command prepared")
        startSSHProcess(command: expectCommand, scriptPath: nil, connection: connection, completion: completion)
    }
    
    private func startSSHProcess(command: String? = nil, scriptPath: String? = nil, connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
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
        
        if let command = command {
            print("🟡 [startSSHProcess] Using bash command")
            sshProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            sshProcess.arguments = ["-c", command]
        } else if let scriptPath = scriptPath {
            print("🟡 [startSSHProcess] Using expect script: \(scriptPath)")
            sshProcess.executableURL = URL(fileURLWithPath: scriptPath)
            sshProcess.arguments = []
        }
        
        sshProcess.standardInput = inputPipe
        sshProcess.standardOutput = outputPipe
        sshProcess.standardError = errorPipe
        
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LANG"] = "en_US.UTF-8"
        sshProcess.environment = environment
        
        var connectionCompleted = false
        
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let output = String(data: data, encoding: .utf8) {
                print("📤 [SSH Output] \(output)")
                DispatchQueue.main.async {
                    if (output.contains("SUCCESS:") || output.contains("SSH_CONNECTION_READY") || output.contains("Connection established")) && !connectionCompleted {
                        print("🟢 [startSSHProcess] Connection success detected!")
                        connectionCompleted = true
                        self?.isConnected = true
                        completion(.success(()))
                    }
                    self?.handleOutput(output)
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let error = String(data: data, encoding: .utf8) {
                if !error.contains("NSSecureCoding") && !error.contains("NSXPCDecoder") {
                    print("⚠️ [SSH Error] \(error)")
                    DispatchQueue.main.async {
                        if (error.contains("Wrong password") || error.contains("Permission denied")) && !connectionCompleted {
                            print("🔴 [startSSHProcess] Authentication failed!")
                            connectionCompleted = true
                            completion(.failure(SSHError.authenticationFailed))
                        } else if error.contains("ERROR:") && !connectionCompleted {
                            print("🔴 [startSSHProcess] Connection error detected!")
                            connectionCompleted = true
                            completion(.failure(SSHError.connectionFailed))
                        }
                        self?.handleError(error)
                    }
                }
            }
        }
        
        sshProcess.terminationHandler = { [weak self] process in
            print("🔚 [startSSHProcess] Process terminated with exit code: \(process.terminationStatus)")
            DispatchQueue.main.async {
                if !connectionCompleted {
                    print("🔴 [startSSHProcess] Process ended before connection completed!")
                    connectionCompleted = true
                    completion(.failure(SSHError.connectionFailed))
                }
                self?.isConnected = false
                if let scriptPath = scriptPath {
                    try? FileManager.default.removeItem(atPath: scriptPath)
                    print("🧹 [startSSHProcess] Cleaned up script file")
                }
            }
        }
        
        do {
            print("🚀 [startSSHProcess] Starting process...")
            try sshProcess.run()
            print("🟢 [startSSHProcess] Process started successfully, PID: \(sshProcess.processIdentifier)")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) { [weak self] in
                if !connectionCompleted {
                    print("⏱️ [startSSHProcess] Connection timeout after 20 seconds")
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
        print("🔵 [executeCommand] isConnected: \(isConnected)")
        print("🔵 [executeCommand] inputPipe exists: \(inputPipe != nil)")
        print("🔵 [executeCommand] command: \(command)")
        
        guard isConnected else {
            print("🔴 [executeCommand] Not connected!")
            completion("错误：未连接")
            return
        }
        
        guard let inputPipe = inputPipe else {
            print("🔴 [executeCommand] No input pipe!")
            completion("错误：输入管道不存在")
            return
        }
        
        guard let data = (command + "\n").data(using: .utf8) else {
            print("🔴 [executeCommand] Failed to encode command!")
            completion("错误：命令编码失败")
            return
        }
        
        do {
            print("🟢 [executeCommand] Sending command to SSH...")
            try inputPipe.fileHandleForWriting.write(contentsOf: data)
            print("🟢 [executeCommand] Command sent successfully")
            completion("")
        } catch {
            print("🔴 [executeCommand] Failed to write: \(error)")
            completion("错误：\(error.localizedDescription)")
        }
    }
    
    private func processCommandQueue() {
        guard !isExecutingCommand, !commandQueue.isEmpty else { return }
        
        isExecutingCommand = true
        let (command, completion) = commandQueue.removeFirst()
        outputBuffer = ""
        
        guard let data = (command + "\n").data(using: .utf8) else {
            isExecutingCommand = false
            completion("错误：命令编码失败")
            return
        }
        
        do {
            try inputPipe?.fileHandleForWriting.write(contentsOf: data)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                completion(self.outputBuffer)
                self.isExecutingCommand = false
                self.processCommandQueue()
            }
        } catch {
            isExecutingCommand = false
            completion("错误：\(error.localizedDescription)")
        }
    }
    
    private func handleOutput(_ output: String) {
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // 过滤不需要显示的内容
            if trimmed.isEmpty ||
               trimmed.hasPrefix("===") ||
               trimmed.hasPrefix("debug") ||
               trimmed.hasPrefix("spawn ") ||
               trimmed.contains("Starting SSH connection") ||
               trimmed.contains("Waiting for password") ||
               trimmed.contains("PASSWORD PROMPT") ||
               trimmed.contains("PASSWORD SENT") ||
               trimmed.contains("Got shell prompt") ||
               trimmed.contains("SSH_CONNECTION_READY") ||
               trimmed.contains("Connection established") ||
               trimmed.contains("entering interactive mode") ||
               trimmed.contains("Warning:") ||
               trimmed.contains("OpenSSH_") ||
               trimmed.contains("LibreSSL") ||
               trimmed.contains("stty:") ||
               trimmed.contains("TIOCGETD") ||
               trimmed.contains("Permission denied, please try again") ||
               trimmed.contains("ERROR:") {
                continue
            }
            
            outputBuffer += line + "\n"
            onOutputReceived?(line, .output)
        }
    }
    
    private func handleError(_ error: String) {
        connectionError = error
        onOutputReceived?(error, .error)
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

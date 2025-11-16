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
        guard !isConnected else {
            completion(.failure(SSHError.alreadyConnected))
            return
        }
        
        self.connection = connection
        
        // 根据认证类型选择不同的连接方式
        if connection.authType == .password {
            connectWithPassword(connection, completion: completion)
        } else {
            connectWithKey(connection, completion: completion)
        }
    }
    
    private func connectWithPassword(_ connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        // 使用 sshpass（如果可用）或者通过 expect 脚本
        // 注意：macOS 默认不包含 sshpass，需要使用 expect
        connectWithExpect(connection, completion: completion)
    }
    
    private func connectWithExpect(_ connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        // 创建 expect 脚本处理密码输入
        let expectScript = """
        #!/usr/bin/expect -f
        set timeout 30
        spawn ssh -p \(connection.port) \(connection.username)@\(connection.host)
        expect {
            "Are you sure you want to continue connecting" {
                send "yes\\r"
                exp_continue
            }
            "password:" {
                send "\(connection.password)\\r"
            }
            "Password:" {
                send "\(connection.password)\\r"
            }
        }
        interact
        """
        
        // 创建临时 expect 脚本文件
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("ssh_expect_\(UUID().uuidString).exp")
        
        do {
            try expectScript.write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
            
            startSSHProcess(scriptPath: scriptPath.path, connection: connection, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }
    
    private func connectWithKey(_ connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        let sshCommand = """
        ssh -i \(connection.keyPath) -p \(connection.port) \(connection.username)@\(connection.host)
        """
        
        startSSHProcess(command: sshCommand, connection: connection, completion: completion)
    }
    
    private func startSSHProcess(command: String? = nil, scriptPath: String? = nil, connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        sshProcess = Process()
        inputPipe = Pipe()
        outputPipe = Pipe()
        errorPipe = Pipe()
        
        guard let sshProcess = sshProcess,
              let inputPipe = inputPipe,
              let outputPipe = outputPipe,
              let errorPipe = errorPipe else {
            completion(.failure(SSHError.processCreationFailed))
            return
        }
        
        if let scriptPath = scriptPath {
            sshProcess.executableURL = URL(fileURLWithPath: scriptPath)
        } else {
            sshProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            sshProcess.arguments = ["-c", command ?? ""]
        }
        
        sshProcess.standardInput = inputPipe
        sshProcess.standardOutput = outputPipe
        sshProcess.standardError = errorPipe
        
        // 配置 PTY（伪终端）
        configurePTY()
        
        // 监听输出
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            
            if let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.handleOutput(output)
                }
            }
        }
        
        // 监听错误输出
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            
            if let error = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.handleError(error)
                }
            }
        }
        
        // 进程终止处理
        sshProcess.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.handleTermination(exitCode: process.terminationStatus)
            }
        }
        
        do {
            try sshProcess.run()
            
            // 等待连接建立
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                if self?.sshProcess?.isRunning == true {
                    self?.isConnected = true
                    completion(.success(()))
                } else {
                    completion(.failure(SSHError.connectionFailed))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    private func configurePTY() {
        // 配置伪终端环境变量
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["PS1"] = "\\u@\\h:\\w$ "
        sshProcess?.environment = environment
    }
    
    // MARK: - 命令执行
    
    func executeCommand(_ command: String, completion: @escaping (String) -> Void) {
        guard isConnected, let inputPipe = inputPipe else {
            completion("错误：未连接到服务器")
            return
        }
        
        commandQueue.append((command: command, completion: completion))
        processCommandQueue()
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
            
            // 等待命令执行完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                completion(self.outputBuffer)
                self.isExecutingCommand = false
                self.processCommandQueue()
            }
        } catch {
            isExecutingCommand = false
            completion("错误：命令发送失败 - \(error.localizedDescription)")
        }
    }
    
    // MARK: - 输出处理
    
    private func handleOutput(_ output: String) {
        outputBuffer += output
        onOutputReceived?(output, .output)
    }
    
    private func handleError(_ error: String) {
        connectionError = error
        onOutputReceived?(error, .error)
    }
    
    private func handleTermination(exitCode: Int32) {
        isConnected = false
        if exitCode != 0 {
            onOutputReceived?("连接已断开（退出码：\(exitCode)）", .error)
        } else {
            onOutputReceived?("连接已正常关闭", .system)
        }
    }
    
    // MARK: - 断开连接
    
    func disconnect() {
        guard let sshProcess = sshProcess, sshProcess.isRunning else { return }
        
        // 发送退出命令
        if let data = "exit\n".data(using: .utf8) {
            try? inputPipe?.fileHandleForWriting.write(contentsOf: data)
        }
        
        // 等待一段时间后强制终止
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if self?.sshProcess?.isRunning == true {
                self?.sshProcess?.terminate()
            }
        }
        
        isConnected = false
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
    }
    
    deinit {
        disconnect()
    }
}

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
    
    func connect(to connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !isConnected else {
            completion(.failure(SSHError.alreadyConnected))
            return
        }
        
        self.connection = connection
        
        if connection.authType == .password {
            connectWithPassword(connection, completion: completion)
        } else {
            connectWithKey(connection, completion: completion)
        }
    }
    
    private func connectWithPassword(_ connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        let expectScript = """
        #!/usr/bin/expect -f
        set timeout 30
        spawn ssh -o StrictHostKeyChecking=no -p \(connection.port) \(connection.username)@\(connection.host)
        expect {
            "password:" { send "\(connection.password)\\r" }
            "Password:" { send "\(connection.password)\\r" }
        }
        interact
        """
        
        let tempDir = FileManager.default.temporaryDirectory
        let scriptPath = tempDir.appendingPathComponent("ssh_\(UUID().uuidString).exp")
        
        do {
            try expectScript.write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
            startSSHProcess(scriptPath: scriptPath.path, connection: connection, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }
    
    private func connectWithKey(_ connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        let expandedKeyPath = NSString(string: connection.keyPath).expandingTildeInPath
        let sshCommand = "ssh -o StrictHostKeyChecking=no -i \(expandedKeyPath) -p \(connection.port) \(connection.username)@\(connection.host)"
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
        
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        sshProcess.environment = environment
        
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.handleOutput(output)
                }
            }
        }
        
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let error = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self?.handleError(error)
                }
            }
        }
        
        sshProcess.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.isConnected = false
            }
        }
        
        do {
            try sshProcess.run()
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
    
    func executeCommand(_ command: String, completion: @escaping (String) -> Void) {
        guard isConnected, let inputPipe = inputPipe else {
            completion("错误：未连接")
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
        outputBuffer += output
        onOutputReceived?(output, .output)
    }
    
    private func handleError(_ error: String) {
        connectionError = error
        onOutputReceived?(error, .error)
    }
    
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

import Foundation

class SFTPService {
    private let connection: SSHConnection
    
    init(connection: SSHConnection) {
        self.connection = connection
    }
    
    // MARK: - 目录浏览
    
    func listDirectory(path: String, completion: @escaping (Result<[FileItem], Error>) -> Void) {
        let sftpCommand = buildSFTPCommand(path: path)
        
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", sftpCommand]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if process.terminationStatus == 0 {
                if let output = String(data: outputData, encoding: .utf8) {
                    let files = parseSFTPOutput(output)
                    completion(.success(files))
                } else {
                    completion(.failure(SSHError.invalidOutput))
                }
            } else {
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                completion(.failure(SSHError.commandFailed(errorMessage)))
            }
        } catch {
            completion(.failure(error))
        }
    }
    
    private func buildSFTPCommand(path: String) -> String {
        let authOption: String
        if connection.authType == .password {
            // 使用 expect 处理密码
            return """
            expect -c '
            spawn sftp -P \(connection.port) \(connection.username)@\(connection.host)
            expect {
                "password:" {
                    send "\(connection.password)\\r"
                }
                "Password:" {
                    send "\(connection.password)\\r"
                }
            }
            expect "sftp>"
            send "cd \(path)\\r"
            expect "sftp>"
            send "ls -la\\r"
            expect "sftp>"
            send "bye\\r"
            expect eof
            '
            """
        } else {
            authOption = "-i \(connection.keyPath)"
            return """
            echo -e "cd \(path)\\nls -la\\nbye" | sftp \(authOption) -P \(connection.port) \(connection.username)@\(connection.host)
            """
        }
    }
    
    private func parseSFTPOutput(_ output: String) -> [FileItem] {
        var files: [FileItem] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            // 解析 ls -la 输出格式
            // 例如: drwxr-xr-x    5 user  group      160 Jan 15 10:30 documents
            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 9 else { continue }
            
            let permissions = String(components[0])
            let name = components[8...].joined(separator: " ")
            
            // 跳过 . 和 ..
            guard name != "." && name != ".." else { continue }
            
            let isDirectory = permissions.hasPrefix("d")
            let size = isDirectory ? nil : formatFileSize(String(components[4]))
            
            let fileItem = FileItem(
                name: name,
                type: isDirectory ? .directory : .file,
                size: size,
                children: isDirectory ? [] : nil
            )
            
            files.append(fileItem)
        }
        
        return files
    }
    
    private func formatFileSize(_ bytes: String) -> String {
        guard let byteCount = Int64(bytes) else { return bytes }
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }
    
    // MARK: - 文件操作
    
    func downloadFile(remotePath: String, localPath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let command: String
        if connection.authType == .password {
            command = """
            expect -c '
            spawn sftp -P \(connection.port) \(connection.username)@\(connection.host)
            expect "password:"
            send "\(connection.password)\\r"
            expect "sftp>"
            send "get \(remotePath) \(localPath)\\r"
            expect "sftp>"
            send "bye\\r"
            expect eof
            '
            """
        } else {
            command = """
            echo "get \(remotePath) \(localPath)" | sftp -i \(connection.keyPath) -P \(connection.port) \(connection.username)@\(connection.host)
            """
        }
        
        executeShellCommand(command, completion: completion)
    }
    
    func uploadFile(localPath: String, remotePath: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let command: String
        if connection.authType == .password {
            command = """
            expect -c '
            spawn sftp -P \(connection.port) \(connection.username)@\(connection.host)
            expect "password:"
            send "\(connection.password)\\r"
            expect "sftp>"
            send "put \(localPath) \(remotePath)\\r"
            expect "sftp>"
            send "bye\\r"
            expect eof
            '
            """
        } else {
            command = """
            echo "put \(localPath) \(remotePath)" | sftp -i \(connection.keyPath) -P \(connection.port) \(connection.username)@\(connection.host)
            """
        }
        
        executeShellCommand(command, completion: completion)
    }
    
    private func executeShellCommand(_ command: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let process = Process()
        let errorPipe = Pipe()
        
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                completion(.success(()))
            } else {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                completion(.failure(SSHError.commandFailed(errorMessage)))
            }
        } catch {
            completion(.failure(error))
        }
    }
}

import Foundation

class SFTPService {
    private let connection: SSHConnection
    
    init(connection: SSHConnection) {
        self.connection = connection
    }
    
    func listDirectory(path: String, completion: @escaping (Result<[FileItem], Error>) -> Void) {
        let sftpCommand = buildListCommand(path: path)
        executeCommand(sftpCommand) { result in
            switch result {
            case .success(let output):
                let files = self.parseListOutput(output)
                completion(.success(files))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func buildListCommand(path: String) -> String {
        let expandedPath = NSString(string: path).expandingTildeInPath
        if connection.authType == .password {
            return """
            /usr/bin/expect -c '
            set timeout 10
            spawn sftp -o StrictHostKeyChecking=no -P \(connection.port) \(connection.username)@\(connection.host)
            expect "password:" { send "\(connection.password)\\r" }
            expect "sftp>"
            send "cd \(expandedPath)\\r"
            expect "sftp>"
            send "ls -la\\r"
            expect "sftp>"
            send "bye\\r"
            expect eof
            '
            """
        } else {
            let keyPath = NSString(string: connection.keyPath).expandingTildeInPath
            return "echo -e 'cd \(expandedPath)\\nls -la\\nbye' | sftp -o StrictHostKeyChecking=no -i \(keyPath) -P \(connection.port) \(connection.username)@\(connection.host)"
        }
    }
    
    private func parseListOutput(_ output: String) -> [FileItem] {
        var files: [FileItem] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            
            let components = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 9 else { continue }
            
            let permissions = String(components[0])
            let name = components[8...].joined(separator: " ")
            
            guard name != "." && name != ".." else { continue }
            guard !name.contains("sftp>") else { continue }
            
            let isDirectory = permissions.hasPrefix("d")
            let size = isDirectory ? nil : String(components[4])
            
            files.append(FileItem(
                name: name,
                type: isDirectory ? .directory : .file,
                size: size,
                children: isDirectory ? [] : nil
            ))
        }
        
        return files
    }
    
    private func executeCommand(_ command: String, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                
                if process.terminationStatus == 0 {
                    completion(.success(output))
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let error = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    completion(.failure(SSHError.commandFailed(error)))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}

import SwiftUI
import Combine

class SSHTerminalViewModel: ObservableObject {
    @Published var connections: [SSHConnection] = []
    @Published var activeConnection: SSHConnection?
    @Published var terminalLines: [TerminalLine] = []
    @Published var currentCommand: String = ""
    @Published var fileTree: [FileItem] = []
    @Published var currentPath: String = "/home"
    @Published var showAddForm: Bool = false
    
    init() {
        loadSampleConnections()
    }
    
    private func loadSampleConnections() {
        connections = [
            SSHConnection(name: "生产服务器", host: "192.168.1.100", port: 22, 
                         username: "root", authType: .password, password: "demo123"),
            SSHConnection(name: "测试服务器", host: "192.168.1.101", port: 22, 
                         username: "admin", authType: .key, keyPath: "~/.ssh/id_rsa")
        ]
    }
    
    func connect(to connection: SSHConnection) {
        activeConnection = connection
        terminalLines = [
            TerminalLine(text: "正在连接到 \(connection.host)...", type: .system),
            TerminalLine(text: "已连接到 \(connection.name) (\(connection.username)@\(connection.host))", type: .system),
            TerminalLine(text: "\(connection.username)@\(connection.host):~$", type: .prompt)
        ]
        loadDirectory(path: "/home")
    }
    
    func executeCommand() {
        guard let connection = activeConnection, !currentCommand.isEmpty else { return }
        
        let cmd = currentCommand.trimmingCharacters(in: .whitespaces)
        terminalLines.append(TerminalLine(
            text: "\(connection.username)@\(connection.host):\(currentPath)$ \(cmd)",
            type: .command
        ))
        
        handleCommand(cmd, connection: connection)
        
        terminalLines.append(TerminalLine(
            text: "\(connection.username)@\(connection.host):\(currentPath)$",
            type: .prompt
        ))
        
        currentCommand = ""
    }
    
    private func handleCommand(_ cmd: String, connection: SSHConnection) {
        let lowercased = cmd.lowercased()
        
        if lowercased == "ls" || lowercased == "ll" {
            for item in fileTree {
                let prefix = item.type == .directory ? "d" : "-"
                let size = item.size ?? ""
                terminalLines.append(TerminalLine(
                    text: "\(prefix)rwxr-xr-x  \(item.name)  \(size)",
                    type: .output
                ))
            }
        } else if lowercased.hasPrefix("cd ") {
            let target = String(cmd.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if target == ".." {
                let components = currentPath.split(separator: "/")
                if components.count > 1 {
                    currentPath = "/" + components.dropLast().joined(separator: "/")
                } else {
                    currentPath = "/home"
                }
                loadDirectory(path: currentPath)
            } else if ["/home", "/var", "/etc"].contains(target) {
                loadDirectory(path: target)
            } else {
                terminalLines.append(TerminalLine(
                    text: "cd: \(target): 没有那个文件或目录",
                    type: .error
                ))
            }
        } else if lowercased == "pwd" {
            terminalLines.append(TerminalLine(text: currentPath, type: .output))
        } else if lowercased == "clear" {
            terminalLines = [TerminalLine(
                text: "\(connection.username)@\(connection.host):\(currentPath)$",
                type: .prompt
            )]
        } else {
            terminalLines.append(TerminalLine(
                text: "命令执行结果...",
                type: .output
            ))
        }
    }
    
    func loadDirectory(path: String) {
        currentPath = path
        
        switch path {
        case "/home":
            fileTree = [
                FileItem(name: "user", type: .directory, size: nil, children: [
                    FileItem(name: "documents", type: .directory, size: nil, children: [
                        FileItem(name: "report.pdf", type: .file, size: "2.3 MB", children: nil),
                        FileItem(name: "notes.txt", type: .file, size: "15 KB", children: nil)
                    ]),
                    FileItem(name: "downloads", type: .directory, size: nil, children: []),
                    FileItem(name: ".bashrc", type: .file, size: "1.2 KB", children: nil)
                ]),
                FileItem(name: "admin", type: .directory, size: nil, children: [])
            ]
        case "/var":
            fileTree = [
                FileItem(name: "log", type: .directory, size: nil, children: [
                    FileItem(name: "syslog", type: .file, size: "5.6 MB", children: nil),
                    FileItem(name: "auth.log", type: .file, size: "890 KB", children: nil)
                ]),
                FileItem(name: "www", type: .directory, size: nil, children: [])
            ]
        case "/etc":
            fileTree = [
                FileItem(name: "nginx", type: .directory, size: nil, children: []),
                FileItem(name: "hosts", type: .file, size: "450 B", children: nil),
                FileItem(name: "passwd", type: .file, size: "2.1 KB", children: nil)
            ]
        default:
            fileTree = []
        }
    }
    
    func addConnection(_ connection: SSHConnection) {
        connections.append(connection)
        showAddForm = false
    }
    
    func deleteConnection(_ connection: SSHConnection) {
        connections.removeAll { $0.id == connection.id }
        if activeConnection?.id == connection.id {
            activeConnection = nil
            terminalLines = []
            fileTree = []
        }
    }
}

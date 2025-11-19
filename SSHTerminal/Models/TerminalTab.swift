import Foundation

struct TerminalTab: Identifiable {
    let id: UUID
    let connection: SSHConnection
    var terminalLines: [TerminalLine] = []
    var currentCommand: String = ""
    var currentPath: String = "~"
    var fileTree: [FileItem] = []
    var isLoadingFiles: Bool = false
    var sshService: SSHService?
    var sftpService: SFTPService?
    var connectionStatus: String = "正在连接..."
    
    init(id: UUID = UUID(), connection: SSHConnection) {
        self.id = id
        self.connection = connection
    }
    
    var displayName: String {
        connection.name
    }
}

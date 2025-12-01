internal import Foundation

// MARK: - SSH连接模型
struct SSHConnection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    // 注意：密码不存储在模型中，而是存储在 Keychain
    var privateKeyPath: String?
    var notes: String?
    var tags: [String]
    var createdAt: Date
    var lastUsedAt: Date?
    
    enum AuthMethod: String, Codable, CaseIterable {
        case password = "密码"
        case publicKey = "密钥"
        
        var systemImage: String {
            switch self {
            case .password: return "key.fill"
            case .publicKey: return "doc.fill"
            }
        }
    }
    
    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        authMethod: AuthMethod = .password,
        privateKeyPath: String? = nil,
        notes: String? = nil,
        tags: [String] = [],
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.privateKeyPath = privateKeyPath
        self.notes = notes
        self.tags = tags
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
    
    // 生成SSH命令
    var sshCommand: String {
        var command = "ssh \(username)@\(host)"
        
        if port != 22 {
            command += " -p \(port)"
        }
        
        if authMethod == .publicKey, let keyPath = privateKeyPath {
            command += " -i \(keyPath)"
        }
        
        return command
    }
    
    // 用于显示的描述
    var displayDescription: String {
        "\(username)@\(host):\(port)"
    }
    
    // 获取密码（从 Keychain）
    var password: String? {
        KeychainService.shared.getPassword(for: id)
    }
    
    // 设置密码（保存到 Keychain）
    func setPassword(_ password: String?) {
        if let password = password, !password.isEmpty {
            _ = KeychainService.shared.savePassword(password, for: id)
        } else {
            _ = KeychainService.shared.deletePassword(for: id)
        }
    }
}

// MARK: - 示例数据
extension SSHConnection {
    static let examples = [
        SSHConnection(
            name: "生产服务器",
            host: "prod.example.com",
            username: "admin",
            authMethod: .publicKey,
            privateKeyPath: "~/.ssh/id_rsa",
            tags: ["生产", "重要"]
        ),
        SSHConnection(
            name: "开发环境",
            host: "dev.example.com",
            port: 2222,
            username: "developer",
            tags: ["开发"]
        ),
        SSHConnection(
            name: "测试服务器",
            host: "test.example.com",
            username: "tester",
            notes: "用于功能测试",
            tags: ["测试"]
        )
    ]
}

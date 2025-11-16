import Foundation

struct SSHConnection: Identifiable, Codable {
    let id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authType: AuthType
    var password: String
    var keyPath: String
    
    enum AuthType: String, Codable, CaseIterable {
        case password = "密码认证"
        case key = "密钥认证"
    }
    
    init(id: UUID = UUID(), name: String = "", host: String = "", port: Int = 22, 
         username: String = "", authType: AuthType = .password, 
         password: String = "", keyPath: String = "") {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authType = authType
        self.password = password
        self.keyPath = keyPath
    }
}

import Foundation
import Combine

class ConnectionManager: ObservableObject {
    static let shared = ConnectionManager()
    
    @Published var connections: [SSHConnection] = []
    private let userDefaultsKey = "SavedSSHConnections"
    
    private init() {
        loadConnections()
    }
    
    // MARK: - 持久化
    
    func saveConnections() {
        do {
            let data = try JSONEncoder().encode(connections)
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("保存连接失败: \(error)")
        }
    }
    
    func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            loadSampleConnections()
            return
        }
        
        do {
            connections = try JSONDecoder().decode([SSHConnection].self, from: data)
        } catch {
            print("加载连接失败: \(error)")
            loadSampleConnections()
        }
    }
    
    private func loadSampleConnections() {
        connections = [
            SSHConnection(name: "生产服务器", host: "192.168.1.100", port: 22,
                         username: "root", authType: .password, password: "demo123"),
            SSHConnection(name: "测试服务器", host: "192.168.1.101", port: 22,
                         username: "admin", authType: .key, keyPath: "~/.ssh/id_rsa")
        ]
        saveConnections()
    }
    
    // MARK: - CRUD 操作
    
    func addConnection(_ connection: SSHConnection) {
        connections.append(connection)
        saveConnections()
    }
    
    func updateConnection(_ connection: SSHConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            saveConnections()
        }
    }
    
    func deleteConnection(_ connection: SSHConnection) {
        connections.removeAll { $0.id == connection.id }
        saveConnections()
    }
}

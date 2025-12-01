internal import Foundation
internal import Combine
internal import SwiftUI

// MARK: - 连接存储服务
class ConnectionStorage: ObservableObject {
    static let shared = ConnectionStorage()
    
    @Published var connections: [SSHConnection] = []
    
    private let userDefaultsKey = "ssh_connections"
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    private init() {
        loadConnections()
    }
    
    // MARK: - 加载连接
    func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? decoder.decode([SSHConnection].self, from: data) else {
            // 如果没有数据，使用示例数据
            connections = SSHConnection.examples
            saveConnections()
            return
        }
        connections = decoded
    }
    
    // MARK: - 保存连接
    func saveConnections() {
        do {
            let encoded = try encoder.encode(connections)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            UserDefaults.standard.synchronize() // 强制同步
            print("✅ 保存成功: \(connections.count) 个连接")
        } catch {
            print("❌ 保存失败: \(error)")
        }
    }
    
    // MARK: - 添加连接
    func addConnection(_ connection: SSHConnection) {
        print("➕ 添加连接: \(connection.name)")
        print("   ID: \(connection.id.uuidString)")
        print("   认证方式: \(connection.authMethod.rawValue)")
        
        // 调试：列出当前所有 Keychain 项
        KeychainService.shared.listAllPasswords()
        
        // 直接添加，不修改 ID
        connections.append(connection)
        saveConnections()
        objectWillChange.send() // 通知UI更新
        
        print("✅ 连接已添加到列表")
    }
    
    // MARK: - 更新连接
    func updateConnection(_ connection: SSHConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
            saveConnections()
        }
    }
    
    // MARK: - 删除连接
    func deleteConnection(_ connection: SSHConnection) {
        connections.removeAll { $0.id == connection.id }
        saveConnections()
    }
    
    func deleteConnections(at offsets: IndexSet) {
        connections.remove(atOffsets: offsets)
        saveConnections()
    }
    
    // MARK: - 更新最后使用时间
    func updateLastUsed(_ connection: SSHConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index].lastUsedAt = Date()
            saveConnections()
        }
    }
    
    // MARK: - 搜索连接
    func searchConnections(query: String) -> [SSHConnection] {
        guard !query.isEmpty else { return connections }
        
        let lowercasedQuery = query.lowercased()
        return connections.filter { connection in
            connection.name.lowercased().contains(lowercasedQuery) ||
            connection.host.lowercased().contains(lowercasedQuery) ||
            connection.username.lowercased().contains(lowercasedQuery) ||
            connection.tags.contains { $0.lowercased().contains(lowercasedQuery) }
        }
    }
    
    // MARK: - 按标签筛选
    func filterByTag(_ tag: String) -> [SSHConnection] {
        connections.filter { $0.tags.contains(tag) }
    }
    
    // MARK: - 获取所有标签
    var allTags: [String] {
        Array(Set(connections.flatMap { $0.tags })).sorted()
    }
    
    // MARK: - 导出连接
    func exportConnections() -> Data? {
        try? encoder.encode(connections)
    }
    
    // MARK: - 导入连接
    func importConnections(from data: Data) -> Bool {
        guard let imported = try? decoder.decode([SSHConnection].self, from: data) else {
            return false
        }
        
        // 合并连接，避免重复
        for connection in imported {
            if !connections.contains(where: { $0.id == connection.id }) {
                connections.append(connection)
            }
        }
        
        saveConnections()
        return true
    }
}

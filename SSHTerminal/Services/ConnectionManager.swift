import Foundation

class ConnectionManager: ObservableObject {
    static let shared = ConnectionManager()
    
    @Published var connections: [SSHConnection] = []
    private let key = "SSHConnections"
    
    private init() {
        loadConnections()
    }
    
    func saveConnections() {
        if let data = try? JSONEncoder().encode(connections) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    
    func loadConnections() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SSHConnection].self, from: data) else {
            connections = []
            return
        }
        connections = decoded
    }
    
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

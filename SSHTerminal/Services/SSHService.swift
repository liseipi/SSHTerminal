import Foundation
import Combine
import Citadel
import Crypto
import NIOCore

// VERSION: Citadel - 2024-11-21
// 使用 Citadel SSH 库,完全兼容 App Sandbox

class SSHService: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var connectionError: String?
    
    private var sshClient: SSHClient?
    private var connection: SSHConnection?
    private var outputBuffer = ""
    
    var onOutputReceived: ((String, TerminalLine.LineType) -> Void)?
    
    // MARK: - 连接管理
    
    func connect(to connection: SSHConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        print("🔵 [SSH-Citadel] Connecting to \(connection.username)@\(connection.host):\(connection.port)")
        
        guard !isConnected else {
            completion(.failure(SSHError.alreadyConnected))
            return
        }
        
        self.connection = connection
        
        Task {
            do {
                let client: SSHClient
                
                // 根据认证类型连接
                if connection.authType == .password {
                    print("🟡 [SSH-Citadel] Using password authentication")
                    client = try await SSHClient.connect(
                        host: connection.host,
                        port: connection.port,
                        authenticationMethod: .passwordBased(username: connection.username, password: connection.password),
                        hostKeyValidator: .acceptAnything(),
                        reconnect: .never
                    )
                    print("🟢 [SSH-Citadel] Password authentication successful")
                } else {
                    print("🟡 [SSH-Citadel] Using key authentication")
                    let keyPath = NSString(string: connection.keyPath).expandingTildeInPath
                    
                    guard FileManager.default.fileExists(atPath: keyPath) else {
                        throw SSHError.authenticationFailed
                    }
                    
                    // 暂时只支持密码认证
                    // Citadel 的密钥认证 API 比较复杂,需要根据密钥类型选择不同的方法
                    print("⚠️ [SSH-Citadel] Key authentication not yet implemented")
                    throw SSHError.authenticationFailed
                    
                    // TODO: 实现密钥认证
                    // 需要检测密钥类型 (RSA, ECDSA, ED25519) 并使用对应的方法
                }
                
                self.sshClient = client
                
                await MainActor.run {
                    self.isConnected = true
                    print("✅ [SSH-Citadel] Connected successfully!")
                    completion(.success(()))
                }
                
            } catch {
                print("🔴 [SSH-Citadel] Connection failed: \(error)")
                await MainActor.run {
                    self.connectionError = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - 命令执行
    
    func executeCommand(_ command: String, completion: @escaping (String) -> Void) {
        print("🔵 [SSH-Citadel] Executing: \(command)")
        
        guard isConnected, let client = sshClient else {
            print("🔴 [SSH-Citadel] Not connected!")
            completion("Error: Not connected")
            return
        }
        
        Task {
            do {
                let result = try await client.executeCommand(command)
                
                // ByteBuffer 转 String
                var buffer = result
                let output = buffer.readString(length: buffer.readableBytes) ?? ""
                
                print("🟢 [SSH-Citadel] Command completed")
                if !output.isEmpty {
                    print("📤 [SSH-Citadel] Output: \(output)")
                }
                
                await MainActor.run {
                    // 只通过 completion 返回结果,不使用 onOutputReceived
                    // 让 ViewModel 决定如何显示输出
                    completion(output)
                }
                
            } catch {
                print("🔴 [SSH-Citadel] Command failed: \(error)")
                await MainActor.run {
                    completion("Error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - 断开连接
    
    func disconnect() {
        print("🟡 [SSH-Citadel] Disconnecting...")
        
        guard let client = sshClient else { return }
        
        Task {
            try? await client.close()
            await MainActor.run {
                self.isConnected = false
                self.sshClient = nil
                print("✅ [SSH-Citadel] Disconnected")
            }
        }
    }
    
    deinit {
        disconnect()
    }
}

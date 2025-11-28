import Foundation
import Security

// MARK: - Keychain 服务
class KeychainService {
    static let shared = KeychainService()
    
    private let serviceName = "com.sshterminal.passwords"
    
    private init() {}
    
    // MARK: - 保存密码
    func savePassword(_ password: String, for connectionId: UUID) -> Bool {
        guard let passwordData = password.data(using: .utf8) else { return false }
        
        // 先删除旧密码
        _ = deletePassword(for: connectionId)
        
        // 创建访问控制（允许应用始终访问，无需提示）
        var accessControl: SecAccessControl?
        if #available(macOS 10.15, *) {
            accessControl = SecAccessControlCreateWithFlags(
                kCFAllocatorDefault,
                kSecAttrAccessibleWhenUnlocked,
                [],  // 空标志表示不需要用户交互
                nil
            )
        }
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: connectionId.uuidString,
            kSecValueData as String: passwordData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // 添加访问控制
        if let accessControl = accessControl {
            query[kSecAttrAccessControl as String] = accessControl
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✅ 密码已保存到 Keychain")
            return true
        } else {
            print("❌ 保存密码失败: \(status)")
            return false
        }
    }
    
    // MARK: - 获取密码
    func getPassword(for connectionId: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: connectionId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let passwordData = result as? Data,
              let password = String(data: passwordData, encoding: .utf8) else {
            return nil
        }
        
        return password
    }
    
    // MARK: - 删除密码
    func deletePassword(for connectionId: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: connectionId.uuidString
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - 更新密码
    func updatePassword(_ password: String, for connectionId: UUID) -> Bool {
        // 简单实现：删除后重新保存
        return savePassword(password, for: connectionId)
    }
    
    // MARK: - 批量授权所有密码（一次性授权）
    func requestBatchAccess() {
        // 尝试读取一个密码来触发授权提示
        // 之后的访问应该就不会再提示了
        print("🔑 请求 Keychain 批量访问权限...")
    }
}

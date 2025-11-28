import Foundation
import Security

// MARK: - Keychain 服务
class KeychainService {
    static let shared = KeychainService()
    
    private let serviceName = "com.sshterminal.passwords"
    
    private init() {}
    
    // MARK: - 保存密码
    func savePassword(_ password: String, for connectionId: UUID) -> Bool {
        guard let passwordData = password.data(using: .utf8) else {
            print("❌ 密码转换为 Data 失败")
            return false
        }
        
        print("🔐 准备保存密码到 Keychain")
        print("   Service: \(serviceName)")
        print("   Account: \(connectionId.uuidString)")
        print("   密码长度: \(password.count)")
        
        // 先删除旧密码
        let deleteStatus = deletePassword(for: connectionId)
        print("   删除旧密码: \(deleteStatus ? "成功" : "无旧密码")")
        
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
            print("✅ 密码已保存到 Keychain (状态: \(status))")
            return true
        } else {
            print("❌ 保存密码失败 (状态: \(status))")
            print("   错误描述: \(SecCopyErrorMessageString(status, nil) as String? ?? "未知错误")")
            return false
        }
    }
    
    // MARK: - 获取密码
    func getPassword(for connectionId: UUID) -> String? {
        print("🔍 从 Keychain 读取密码")
        print("   Service: \(serviceName)")
        print("   Account: \(connectionId.uuidString)")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: connectionId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            if let passwordData = result as? Data,
               let password = String(data: passwordData, encoding: .utf8) {
                print("✅ 密码读取成功，长度: \(password.count)")
                return password
            } else {
                print("❌ 密码数据转换失败")
                return nil
            }
        } else {
            print("❌ 读取密码失败 (状态: \(status))")
            print("   错误描述: \(SecCopyErrorMessageString(status, nil) as String? ?? "未知错误")")
            return nil
        }
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
    
    // MARK: - 调试：列出所有密码项
    func listAllPasswords() {
        print("\n🔍 列出所有 Keychain 密码项:")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            if let items = result as? [[String: Any]] {
                print("   找到 \(items.count) 个密码项:")
                for (index, item) in items.enumerated() {
                    if let account = item[kSecAttrAccount as String] as? String {
                        print("   [\(index + 1)] Account: \(account)")
                    }
                }
            }
        } else {
            print("   没有找到密码项 (状态: \(status))")
        }
        print("")
    }
}

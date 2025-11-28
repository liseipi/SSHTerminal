import Foundation
import Security

// MARK: - Keychain 服务
class KeychainService {
    static let shared = KeychainService()
    
    private let serviceName = "com.sshterminal.passwords"
    
    // ⭐️ 完全不使用访问组，让系统自动管理
    private var accessGroup: String? {
        return nil
    }
    
    private init() {
        // 启动时检查权限
        checkKeychainAccess()
    }
    
    // MARK: - 检查 Keychain 访问权限
    private func checkKeychainAccess() {
        print("🔐 检查 Keychain 访问权限...")
        print("   Access Group: \(accessGroup ?? "nil (使用默认)")")
        
        // 尝试写入测试项
        let testKey = "test_access_check"
        let testData = "test".data(using: .utf8)!
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: testKey,
            kSecValueData as String: testData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // 只在有访问组时添加
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        
        // 先删除可能存在的测试项
        var deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: testKey
        ]
        if let group = accessGroup {
            deleteQuery[kSecAttrAccessGroup as String] = group
        }
        SecItemDelete(deleteQuery as CFDictionary)
        
        // 尝试添加
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✅ Keychain 访问权限正常")
            // 删除测试项
            SecItemDelete(deleteQuery as CFDictionary)
        } else {
            print("❌ Keychain 访问权限异常 (状态: \(status))")
            print("   错误: \(keychainErrorMessage(status))")
            
            if status == errSecMissingEntitlement || status == -34018 {
                print("⚠️  请检查 Entitlements 配置：")
                print("   1. 确保添加了 Keychain Sharing capability")
                print("   2. 确保 keychain-access-groups 包含正确的 Bundle ID")
            }
        }
    }
    
    // MARK: - 保存密码
    func savePassword(_ password: String, for connectionId: UUID) -> Bool {
        guard let passwordData = password.data(using: .utf8) else {
            print("❌ 密码转换为 Data 失败")
            return false
        }
        
        print("🔐 准备保存密码到 Keychain")
        print("   Service: \(serviceName)")
        print("   Account: \(connectionId.uuidString)")
        print("   Access Group: \(accessGroup ?? "nil (使用默认)")")
        print("   密码长度: \(password.count)")
        
        // 先删除旧密码
        let deleteStatus = deletePassword(for: connectionId)
        print("   删除旧密码: \(deleteStatus ? "成功" : "无旧密码")")
        
        // ⭐️ 简化版本：不使用 AccessControl，直接保存
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: connectionId.uuidString,
            kSecValueData as String: passwordData
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            print("✅ 密码已保存到 Keychain (状态: \(status))")
            return true
        } else {
            print("❌ 保存密码失败 (状态: \(status))")
            print("   错误: \(keychainErrorMessage(status))")
            
            // 提供详细的错误提示
            if status == errSecMissingEntitlement || status == -34018 {
                print("⚠️  可能的解决方案：")
                print("   1. 检查应用是否正确签名：codesign -dv YourApp.app")
                print("   2. 尝试在 Debug 模式下运行（不要 Archive）")
                print("   3. 检查是否有杀毒软件阻止 Keychain 访问")
            }
            
            return false
        }
    }
    
    // MARK: - 获取密码
    func getPassword(for connectionId: UUID) -> String? {
        print("🔍 从 Keychain 读取密码")
        print("   Service: \(serviceName)")
        print("   Account: \(connectionId.uuidString)")
        print("   Access Group: \(accessGroup ?? "nil (使用默认)")")
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: connectionId.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        // ⭐️ 只在有访问组时添加
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        
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
            print("   错误: \(keychainErrorMessage(status))")
            return nil
        }
    }
    
    // MARK: - 删除密码
    func deletePassword(for connectionId: UUID) -> Bool {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: connectionId.uuidString
        ]
        
        // ⭐️ 只在有访问组时添加
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - 更新密码
    func updatePassword(_ password: String, for connectionId: UUID) -> Bool {
        return savePassword(password, for: connectionId)
    }
    
    // MARK: - 列出所有密码项
    func listAllPasswords() {
        print("\n🔍 列出所有 Keychain 密码项:")
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        // ⭐️ 只在有访问组时添加
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        
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
            print("   错误: \(keychainErrorMessage(status))")
        }
        print("")
    }
    
    // MARK: - Keychain 错误信息
    private func keychainErrorMessage(_ status: OSStatus) -> String {
        switch status {
        case errSecSuccess:
            return "成功"
        case errSecItemNotFound:
            return "找不到项目"
        case errSecDuplicateItem:
            return "项目已存在"
        case errSecAuthFailed:
            return "认证失败"
        case errSecMissingEntitlement:
            return "缺少权限配置 (Entitlement)"
        case -34018:
            return "缺少必需的权限 (需要 Keychain Sharing)"
        case errSecInteractionNotAllowed:
            return "用户交互未允许"
        case errSecInvalidRecord:
            return "无效记录"
        default:
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "未知错误 (\(status))"
        }
    }
}

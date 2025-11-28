internal import SwiftUI
internal import UniformTypeIdentifiers

@main
struct SSHTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ConnectionListView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            // 文件菜单
            CommandGroup(replacing: .newItem) {
                Button("新建连接") {
                    NotificationCenter.default.post(name: .addConnection, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            // 编辑菜单
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("导入连接...") {
                    importConnections()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                
                Button("导出连接...") {
                    exportConnections()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            
            // 帮助菜单
            CommandGroup(replacing: .help) {
                Button("SSH 密钥认证指南") {
                    showHelp(.sshKey)
                }
                
                Button("解决 Keychain 重复授权") {
                    showHelp(.keychain)
                }
                
                Button("故障排查") {
                    showHelp(.troubleshooting)
                }
                
                Divider()
                
                Link("查看 GitHub 项目", destination: URL(string: "https://github.com/liseipi/SSHTerminal")!)
            }
        }
        
        Settings {
            SettingsView()
        }
    }
    
    // MARK: - 导入连接
    private func importConnections() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.json]
        panel.message = "选择要导入的连接配置文件"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                if ConnectionStorage.shared.importConnections(from: data) {
                    showAlert(title: "导入成功", message: "连接已成功导入")
                } else {
                    showAlert(title: "导入失败", message: "文件格式不正确")
                }
            } catch {
                showAlert(title: "导入失败", message: error.localizedDescription)
            }
        }
    }
    
    // MARK: - 导出连接
    private func exportConnections() {
        guard let data = ConnectionStorage.shared.exportConnections() else {
            showAlert(title: "导出失败", message: "无法导出连接数据")
            return
        }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ssh_connections_\(Date().timeIntervalSince1970).json"
        panel.message = "导出连接配置"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                showAlert(title: "导出成功", message: "连接配置已导出")
            } catch {
                showAlert(title: "导出失败", message: error.localizedDescription)
            }
        }
    }
    
    // MARK: - 显示警告
    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        alert.runModal()
    }
    
    // MARK: - 显示帮助
    private func showHelp(_ type: HelpType) {
        let alert = NSAlert()
        
        switch type {
        case .sshKey:
            alert.messageText = "SSH 密钥认证指南"
            alert.informativeText = """
            推荐使用 SSH 密钥认证，更安全且无需保存密码。
            
            1. 生成密钥对：
               ssh-keygen -t ed25519 -C "your_email@example.com"
            
            2. 上传公钥到服务器：
               ssh-copy-id user@host
            
            3. 在应用中选择"密钥"认证方式
            
            4. 选择私钥文件（通常在 ~/.ssh/id_ed25519）
            """
            
        case .keychain:
            alert.messageText = "解决 Keychain 重复授权"
            alert.informativeText = """
            每次连接都提示授权？请这样做：
            
            方法 1：在弹窗中点击"始终允许"（而不是"允许"）
            
            方法 2：打开"钥匙串访问"应用
               → 搜索 "com.sshterminal.passwords"
               → 双击密码项
               → 访问控制标签
               → 选择"允许所有应用程序访问此项目"
            
            方法 3：改用 SSH 密钥认证（推荐）
            """
            
        case .troubleshooting:
            alert.messageText = "常见问题解决"
            alert.informativeText = """
            1. 无法打开 Terminal
               → 删除 App Sandbox
               → 授予自动化权限
            
            2. 密码自动登录失败
               → 确认密码正确
               → 检查服务器地址和端口
            
            3. Keychain 重复授权
               → 点击"始终允许"
               → 或改用密钥认证
            
            4. 密码包含特殊字符
               → 已支持所有特殊字符
               → 如有问题请反馈
            """
        }
        
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }
}

enum HelpType {
    case sshKey
    case keychain
    case troubleshooting
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置窗口样式
        if let window = NSApplication.shared.windows.first {
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let addConnection = Notification.Name("addConnection")
}

// MARK: - 设置视图
struct SettingsView: View {
    @AppStorage("defaultTerminal") private var defaultTerminal = TerminalApp.terminal.rawValue
    @AppStorage("autoUpdateLastUsed") private var autoUpdateLastUsed = true
    
    var body: some View {
        TabView {
            // 通用设置
            Form {
                Section("终端") {
                    Picker("默认终端应用", selection: $defaultTerminal) {
                        ForEach(TerminalLauncher.shared.availableTerminals, id: \.rawValue) { terminal in
                            Text(terminal.displayName).tag(terminal.rawValue)
                        }
                    }
                }
                
                Section("行为") {
                    Toggle("自动更新最后使用时间", isOn: $autoUpdateLastUsed)
                        .help("连接到服务器时自动记录使用时间")
                }
            }
            .formStyle(.grouped)
            .frame(width: 400, height: 300)
            .tabItem {
                Label("通用", systemImage: "gear")
            }
            
            // 关于
            VStack(spacing: 16) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
                
                Text("SSH Terminal Manager")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("版本 1.0.0")
                    .foregroundColor(.secondary)
                
                Text("轻量级SSH连接管理工具")
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .frame(width: 400, height: 300)
            .padding()
            .tabItem {
                Label("关于", systemImage: "info.circle")
            }
        }
    }
}

#Preview {
    ConnectionListView()
}

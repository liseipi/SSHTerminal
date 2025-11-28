import Foundation
import AppKit

// MARK: - 终端类型
enum TerminalApp: String, CaseIterable {
    case terminal = "Terminal"
    case iterm = "iTerm"
    
    var displayName: String {
        rawValue
    }
    
    var bundleIdentifier: String {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .iterm: return "com.googlecode.iterm2"
        }
    }
    
    var isInstalled: Bool {
        switch self {
        case .terminal:
            // Terminal 是系统自带的，总是存在
            return true
        case .iterm:
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        }
    }
}

// MARK: - 终端启动器
class TerminalLauncher {
    static let shared = TerminalLauncher()
    
    private init() {}
    
    // 获取可用的终端应用
    var availableTerminals: [TerminalApp] {
        TerminalApp.allCases.filter { $0.isInstalled }
    }
    
    // 在指定终端中打开SSH连接
    func openConnection(_ connection: SSHConnection, in terminal: TerminalApp) -> Bool {
        print("🚀 尝试在 \(terminal.displayName) 中打开连接: \(connection.name)")
        
        let success: Bool
        switch terminal {
        case .terminal:
            success = openInTerminal(connection)
        case .iterm:
            success = openInITerm(connection)
        }
        
        if success {
            print("✅ 成功打开 \(terminal.displayName)")
        } else {
            print("❌ 无法打开 \(terminal.displayName)")
        }
        
        return success
    }
    
    // 在系统Terminal中打开
    private func openInTerminal(_ connection: SSHConnection) -> Bool {
        let sshCommand = generateSSHCommand(connection)
        print("📝 SSH命令: \(connection.sshCommand)")
        if connection.authMethod == .password && connection.password != nil {
            print("🔐 使用密码自动登录")
        }
        
        // 方法1: 直接使用 osascript 命令（最可靠）
        if openInTerminalViaOsascript(sshCommand) {
            return true
        }
        
        print("⚠️ osascript 失败，尝试 NSAppleScript...")
        
        // 方法2: 使用 NSAppleScript
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedForAppleScript(sshCommand))"
        end tell
        """
        
        if executeAppleScript(script) {
            return true
        }
        
        print("⚠️ NSAppleScript 失败，尝试备用方案...")
        
        // 方法3: 使用 .command 文件（最后手段）
        return openWithCommandFile(connection, command: sshCommand)
    }
    
    // 转义 AppleScript 中的特殊字符
    private func escapedForAppleScript(_ command: String) -> String {
        return command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
    
    // 使用 osascript 命令行工具
    private func openInTerminalViaOsascript(_ command: String) -> Bool {
        // 先确保 Terminal 正在运行
        let activateScript = """
        tell application "Terminal"
            activate
        end tell
        """
        
        do {
            // 第一步：启动并激活 Terminal
            let activateProcess = Process()
            activateProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            activateProcess.arguments = ["-e", activateScript]
            
            try activateProcess.run()
            activateProcess.waitUntilExit()
            
            if activateProcess.terminationStatus != 0 {
                print("❌ 无法启动 Terminal")
                return false
            }
            
            // 等待 Terminal 完全启动
            Thread.sleep(forTimeInterval: 0.5)
            
            // 第二步：执行命令
            let executeScript = """
            tell application "Terminal"
                do script "\(escapedForAppleScript(command))"
            end tell
            """
            
            let executeProcess = Process()
            executeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            executeProcess.arguments = ["-e", executeScript]
            
            let pipe = Pipe()
            executeProcess.standardOutput = pipe
            executeProcess.standardError = pipe
            
            try executeProcess.run()
            executeProcess.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                print("📤 osascript 输出: \(output)")
            }
            
            if executeProcess.terminationStatus == 0 {
                print("✅ osascript 执行成功")
                return true
            } else {
                print("❌ osascript 失败，退出码: \(executeProcess.terminationStatus)")
                return false
            }
        } catch {
            print("❌ osascript 执行异常: \(error)")
            return false
        }
    }
    
    // 在iTerm2中打开
    private func openInITerm(_ connection: SSHConnection) -> Bool {
        let sshCommand = generateSSHCommand(connection)
        print("📝 SSH命令: \(connection.sshCommand)")
        if connection.authMethod == .password && connection.password != nil {
            print("🔐 使用密码自动登录")
        }
        
        let script = """
        tell application "iTerm"
            activate
            
            -- 创建新窗口
            create window with default profile
            
            -- 在当前会话中执行SSH命令
            tell current session of current window
                write text "\(escapedForAppleScript(sshCommand))"
            end tell
        end tell
        """
        
        return executeAppleScript(script)
    }
    
    // 生成SSH命令（支持密码自动输入）
    private func generateSSHCommand(_ connection: SSHConnection) -> String {
        var command = ""
        
        // 如果是密码认证，使用 sshpass 或 expect
        if connection.authMethod == .password, let password = connection.password {
            // 检查是否安装了 sshpass
            if isCommandAvailable("sshpass") {
                // 方案1: 使用 sshpass（最简单）
                let escapedPwd = password
                    .replacingOccurrences(of: "'", with: "'\\''")
                command = "sshpass -p '\(escapedPwd)' \(connection.sshCommand)"
            } else {
                // 方案2: 使用 expect 脚本文件（避免密码泄露）
                command = createExpectScriptFile(connection: connection, password: password)
            }
        } else {
            // 密钥认证直接使用 SSH 命令
            command = connection.sshCommand
        }
        
        return command
    }
    
    // 创建 expect 脚本文件
    private func createExpectScriptFile(connection: SSHConnection, password: String) -> String {
        do {
            let tempDir: URL
            if let realTempDir = getenv("TMPDIR") {
                tempDir = URL(fileURLWithPath: String(cString: realTempDir))
            } else {
                tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            }
            
            let timestamp = Int(Date().timeIntervalSince1970)
            let scriptFile = tempDir.appendingPathComponent("ssh_expect_\(timestamp).exp")
            
            // 转义密码（用于 expect）
            let escapedPwd = password
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            
            // 创建 expect 脚本
            let expectScript = """
            #!/usr/bin/expect -f
            set timeout 30
            log_user 0
            
            spawn \(connection.sshCommand)
            
            expect {
                -re "(?i)(are you sure|fingerprint)" {
                    send "yes\\r"
                    exp_continue
                }
                -re "(?i)(password:|password for)" {
                    log_user 1
                    send "\(escapedPwd)\\r"
                }
                timeout {
                    puts "\\n连接超时"
                    exit 1
                }
                eof {
                    puts "\\n连接失败"
                    exit 1
                }
            }
            
            log_user 1
            interact
            """
            
            // 写入脚本文件
            try expectScript.write(to: scriptFile, atomically: true, encoding: .utf8)
            
            // 设置可执行权限
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", scriptFile.path]
            try? chmodProcess.run()
            chmodProcess.waitUntilExit()
            
            // 延迟删除脚本文件
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                try? FileManager.default.removeItem(at: scriptFile)
                print("🗑️ 已删除临时 expect 脚本")
            }
            
            return scriptFile.path
        } catch {
            print("❌ 创建 expect 脚本失败: \(error)")
            // 降级方案：返回普通 SSH 命令
            return connection.sshCommand
        }
    }
    
    // 检查命令是否可用
    private func isCommandAvailable(_ command: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    // 使用.command文件方式（备用方案）
    func openWithCommandFile(_ connection: SSHConnection, command: String) -> Bool {
        do {
            // 创建临时目录（使用用户的真实临时目录，而不是沙盒容器内的）
            let tempDir: URL
            if let realTempDir = getenv("TMPDIR") {
                tempDir = URL(fileURLWithPath: String(cString: realTempDir))
            } else {
                tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            }
            
            let timestamp = Int(Date().timeIntervalSince1970)
            let fileName = "ssh_connect_\(timestamp).command"
            let tempFile = tempDir.appendingPathComponent(fileName)
            
            // 创建脚本内容
            let script = """
            #!/bin/bash
            clear
            echo "=================================="
            echo "  SSH Terminal Manager"
            echo "=================================="
            echo "连接名称: \(connection.name)"
            echo "连接地址: \(connection.displayDescription)"
            echo "=================================="
            echo ""
            echo "正在连接到服务器..."
            echo ""
            \(command)
            """
            
            print("📝 创建临时脚本: \(tempFile.path)")
            
            // 写入文件
            try script.write(to: tempFile, atomically: true, encoding: .utf8)
            
            // 使用 chmod 设置权限（更可靠）
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", tempFile.path]
            try chmodProcess.run()
            chmodProcess.waitUntilExit()
            
            print("✅ 已设置可执行权限")
            
            // 尝试清除隔离属性（如果失败也继续）
            let xattrProcess = Process()
            xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattrProcess.arguments = ["-cr", tempFile.path]
            try? xattrProcess.run()
            xattrProcess.waitUntilExit()
            
            if xattrProcess.terminationStatus == 0 {
                print("✅ 已清除隔离属性")
            } else {
                print("⚠️ 无法清除隔离属性（可能需要额外权限）")
            }
            
            // 直接使用 open 命令打开
            let openProcess = Process()
            openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            openProcess.arguments = ["-a", "Terminal", tempFile.path]
            
            try openProcess.run()
            openProcess.waitUntilExit()
            
            if openProcess.terminationStatus == 0 {
                print("✅ 已通过 open 命令启动 Terminal")
            } else {
                print("❌ open 命令失败")
                return false
            }
            
            // 延迟删除临时文件
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                try? FileManager.default.removeItem(at: tempFile)
                print("🗑️ 已删除临时脚本")
            }
            
            return true
        } catch {
            print("❌ 创建命令文件失败: \(error)")
            return false
        }
    }
    
    // 执行AppleScript
    private func executeAppleScript(_ script: String) -> Bool {
        print("🔧 执行 AppleScript...")
        
        // 先确保 Terminal 已启动
        let activateScript = "tell application \"Terminal\" to activate"
        if let activate = NSAppleScript(source: activateScript) {
            var activateError: NSDictionary?
            activate.executeAndReturnError(&activateError)
            
            if activateError == nil {
                print("✅ Terminal 已启动")
                // 等待 Terminal 完全启动
                Thread.sleep(forTimeInterval: 0.5)
            } else {
                print("⚠️ 启动 Terminal 时出现警告")
            }
        }
        
        // 执行主脚本
        guard let appleScript = NSAppleScript(source: script) else {
            print("❌ 无法创建 AppleScript")
            return false
        }
        
        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ AppleScript 错误:")
            print("   错误代码: \(error["NSAppleScriptErrorNumber"] ?? "未知")")
            print("   错误信息: \(error["NSAppleScriptErrorMessage"] ?? "未知")")
            return false
        }
        
        print("✅ AppleScript 执行成功")
        if let stringValue = result.stringValue {
            print("   返回值: \(stringValue)")
        }
        return true
    }
    
    // 复制SSH命令到剪贴板
    func copyCommandToClipboard(_ connection: SSHConnection) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(connection.sshCommand, forType: .string)
    }
}

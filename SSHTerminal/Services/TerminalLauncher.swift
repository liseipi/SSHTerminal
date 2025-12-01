internal import Foundation
internal import AppKit
internal import SwiftUI
internal import SwiftTerm

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
    
    var availableTerminals: [TerminalApp] {
        TerminalApp.allCases.filter { $0.isInstalled }
    }
    
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
    
    private func openInTerminal(_ connection: SSHConnection) -> Bool {
        let sshCommand = generateSSHCommand(connection)
        
        if openInTerminalViaOsascript(sshCommand) {
            return true
        }
        
        let script = """
        tell application "Terminal"
            activate
            do script "\(escapedForAppleScript(sshCommand))"
        end tell
        """
        
        if executeAppleScript(script) {
            return true
        }
        
        return openWithCommandFile(connection, command: sshCommand)
    }
    
    private func escapedForAppleScript(_ command: String) -> String {
        return command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
    
    private func openInTerminalViaOsascript(_ command: String) -> Bool {
        let activateScript = """
        tell application "Terminal"
            activate
        end tell
        """
        
        do {
            let activateProcess = Process()
            activateProcess.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            activateProcess.arguments = ["-e", activateScript]
            
            try activateProcess.run()
            activateProcess.waitUntilExit()
            
            if activateProcess.terminationStatus != 0 {
                return false
            }
            
            Thread.sleep(forTimeInterval: 0.5)
            
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
            
            return executeProcess.terminationStatus == 0
        } catch {
            print("❌ osascript 执行异常: \(error)")
            return false
        }
    }
    
    private func openInITerm(_ connection: SSHConnection) -> Bool {
        let sshCommand = generateSSHCommand(connection)
        
        let script = """
        tell application "iTerm"
            activate
            create window with default profile
            tell current session of current window
                write text "\(escapedForAppleScript(sshCommand))"
            end tell
        end tell
        """
        
        return executeAppleScript(script)
    }
    
    private func generateSSHCommand(_ connection: SSHConnection) -> String {
        var command = ""
        
        if connection.authMethod == .password, let password = connection.password {
            if isCommandAvailable("sshpass") {
                let escapedPwd = password.replacingOccurrences(of: "'", with: "'\\''")
                command = "sshpass -p '\(escapedPwd)' \(connection.sshCommand)"
            } else {
                command = createExpectScriptFile(connection: connection, password: password)
            }
        } else {
            command = connection.sshCommand
        }
        
        return command
    }
    
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
            
            let escapedPwd = password
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "[", with: "\\[")
                .replacingOccurrences(of: "]", with: "\\]")
            
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
            
            try expectScript.write(to: scriptFile, atomically: true, encoding: .utf8)
            
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", scriptFile.path]
            try? chmodProcess.run()
            chmodProcess.waitUntilExit()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                try? FileManager.default.removeItem(at: scriptFile)
            }
            
            return scriptFile.path
        } catch {
            print("❌ 创建 expect 脚本失败: \(error)")
            return connection.sshCommand
        }
    }
    
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
    
    func openWithCommandFile(_ connection: SSHConnection, command: String) -> Bool {
        do {
            let tempDir: URL
            if let realTempDir = getenv("TMPDIR") {
                tempDir = URL(fileURLWithPath: String(cString: realTempDir))
            } else {
                tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            }
            
            let timestamp = Int(Date().timeIntervalSince1970)
            let fileName = "ssh_connect_\(timestamp).command"
            let tempFile = tempDir.appendingPathComponent(fileName)
            
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
            
            try script.write(to: tempFile, atomically: true, encoding: .utf8)
            
            let chmodProcess = Process()
            chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmodProcess.arguments = ["+x", tempFile.path]
            try chmodProcess.run()
            chmodProcess.waitUntilExit()
            
            let openProcess = Process()
            openProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            openProcess.arguments = ["-a", "Terminal", tempFile.path]
            
            try openProcess.run()
            openProcess.waitUntilExit()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                try? FileManager.default.removeItem(at: tempFile)
            }
            
            return openProcess.terminationStatus == 0
        } catch {
            print("❌ 创建命令文件失败: \(error)")
            return false
        }
    }
    
    private func executeAppleScript(_ script: String) -> Bool {
        let activateScript = "tell application \"Terminal\" to activate"
        if let activate = NSAppleScript(source: activateScript) {
            var activateError: NSDictionary?
            _ = activate.executeAndReturnError(&activateError)
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        guard let appleScript = NSAppleScript(source: script) else {
            return false
        }
        
        var error: NSDictionary?
        _ = appleScript.executeAndReturnError(&error)
        
        if let error = error {
            print("❌ AppleScript 错误: \(error)")
            return false
        }
        
        return true
    }
    
    func copyCommandToClipboard(_ connection: SSHConnection) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(connection.sshCommand, forType: .string)
    }
}

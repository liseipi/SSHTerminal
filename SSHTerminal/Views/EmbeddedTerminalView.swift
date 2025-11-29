internal import SwiftUI
import AppKit

// MARK: - 内嵌终端视图
struct EmbeddedTerminalView: View {
    let connection: SSHConnection
    @ObservedObject var session: SSHSessionManager
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            toolbar
            
            Divider()
            
            // 终端视图 - 使用原生 Terminal 风格
            NativeTerminalView(session: session)
                .onAppear {
                    print("🟣 [Embedded] 终端视图已出现: \(connection.name)")
                    print("🟣 [Embedded] Session 状态 - 连接中: \(session.isConnecting), 已连接: \(session.isConnected)")
                    print("🟣 [Embedded] 当前输出长度: \(session.output.count)")
                }
        }
        .background(Color.black)
    }
    
    // MARK: - 工具栏
    private var toolbar: some View {
        HStack {
            // 连接状态
            HStack(spacing: 8) {
                Circle()
                    .fill(session.isConnected ? Color.green : (session.isConnecting ? Color.yellow : Color.red))
                    .frame(width: 10, height: 10)
                
                Text(connection.name)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(connection.displayDescription)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            // 状态信息
            if session.isConnecting {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    Text("连接中...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else if let error = session.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if session.isConnected {
                Text("已连接")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            
            // 操作按钮
            HStack(spacing: 8) {
                Button(action: { session.output = "" }) {
                    Image(systemName: "trash")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .help("清空输出")
                
                Button(action: reconnect) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .help("重新连接")
                
                Button(action: { session.disconnect() }) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("断开连接")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(white: 0.15))
    }
    
    private func reconnect() {
        session.disconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            session.connect(to: connection)
        }
    }
}

// MARK: - 原生风格终端视图
struct NativeTerminalView: NSViewRepresentable {
    @ObservedObject var session: SSHSessionManager
    @State private var isInitialized = false
    
    func makeNSView(context: Context) -> NSScrollView {
        print("🟣 [View] makeNSView 开始，线程: \(Thread.current)")
        
        let scrollView = NSScrollView()
        let textView = NativeTerminalTextView()
        
        // 配置 TextView - 完全模拟 Terminal
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = NSColor.white
        textView.backgroundColor = NSColor.black
        textView.insertionPointColor = NSColor.white
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.autoresizingMask = [.width, .height]
        
        // 禁用所有自动替换
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = true
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        
        // 配置 TextContainer
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        
        // 配置 ScrollView
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.backgroundColor = NSColor.black
        scrollView.drawsBackground = true
        
        // ⭐️ 简化：不使用自定义 TextStorage，直接使用默认的
        // 设置 coordinator
        textView.terminalDelegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.session = session
        
        print("🟣 [View] makeNSView 完成")
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NativeTerminalTextView else {
            print("⚠️ [View] updateNSView - textView 为空")
            return
        }
        
        // 更新输出 - 简化版本
        let newOutput = session.output
        let oldOutput = context.coordinator.lastOutput
        
        guard newOutput != oldOutput else { return }
        
        print("🔄 [View] 更新文本，旧: \(oldOutput.count), 新: \(newOutput.count)")
        
        context.coordinator.lastOutput = newOutput
        
        // ⭐️ 直接设置文本，不使用复杂的 TextStorage
        let cleanOutput = ANSICleaner.clean(newOutput)
        
        if let textStorage = textView.textStorage {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.white
            ]
            
            let attributedString = NSAttributedString(string: cleanOutput, attributes: attributes)
            
            textStorage.setAttributedString(attributedString)
            
            print("🔄 [View] 文本已更新，长度: \(textStorage.length)")
            
            // 滚动到底部
            let range = NSRange(location: textStorage.length, length: 0)
            textView.scrollRangeToVisible(range)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, TerminalTextViewDelegate {
        var textView: NativeTerminalTextView?
        var session: SSHSessionManager?
        var lastOutput = ""
        
        func terminalTextView(_ textView: NativeTerminalTextView, didReceiveInput input: String) {
            session?.sendInput(input)
        }
    }
}

// MARK: - 原生风格 NSTextView
protocol TerminalTextViewDelegate: AnyObject {
    func terminalTextView(_ textView: NativeTerminalTextView, didReceiveInput input: String)
}

class NativeTerminalTextView: NSTextView {
    weak var terminalDelegate: TerminalTextViewDelegate?
    
    override func keyDown(with event: NSEvent) {
        handleKeyEvent(event)
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags
        
        // 处理特殊按键
        switch keyCode {
        case 36: // Enter/Return
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\r")
            
        case 48: // Tab
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\t")
            
        case 51: // Delete/Backspace
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{007F}")
            
        case 53: // Escape
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}")
            
        case 123: // Left Arrow
            if modifiers.contains(.option) {
                terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}b")
            } else {
                terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[D")
            }
            
        case 124: // Right Arrow
            if modifiers.contains(.option) {
                terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}f")
            } else {
                terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[C")
            }
            
        case 125: // Down Arrow
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[B")
            
        case 126: // Up Arrow
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[A")
            
        case 117: // Forward Delete (Fn+Delete)
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[3~")
            
        case 115: // Home (Fn+Left)
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[H")
            
        case 119: // End (Fn+Right)
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[F")
            
        case 116: // Page Up
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[5~")
            
        case 121: // Page Down
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[6~")
            
        default:
            // 检查 Ctrl 组合键
            if modifiers.contains(.control) {
                handleControlKey(event)
            } else if let chars = event.characters, !chars.isEmpty {
                // 普通字符
                terminalDelegate?.terminalTextView(self, didReceiveInput: chars)
            }
        }
    }
    
    private func handleControlKey(_ event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return }
        
        if let char = chars.first, let ascii = char.asciiValue {
            if ascii >= 97 && ascii <= 122 { // a-z
                let controlChar = Character(UnicodeScalar(ascii - 96))
                terminalDelegate?.terminalTextView(self, didReceiveInput: String(controlChar))
            }
        }
    }
    
    // 禁用文本编辑
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        return false
    }
    
    override func insertText(_ string: Any, replacementRange: NSRange) {
        // 不做任何事
    }
    
    override func deleteBackward(_ sender: Any?) {
        // 不做任何事
    }
    
    override func deleteForward(_ sender: Any?) {
        // 不做任何事
    }
    
    // 处理粘贴
    override func paste(_ sender: Any?) {
        if let pasteboardString = NSPasteboard.general.string(forType: .string) {
            terminalDelegate?.terminalTextView(self, didReceiveInput: pasteboardString)
        }
    }
    
    // 菜单验证
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action
        
        if action == #selector(paste(_:)) {
            return NSPasteboard.general.string(forType: .string) != nil
        }
        if action == #selector(copy(_:)) {
            return selectedRange().length > 0
        }
        if action == #selector(selectAll(_:)) {
            return true
        }
        
        return false
    }
    
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
}

#Preview {
    EmbeddedTerminalView(
        connection: SSHConnection.examples[0],
        session: SSHSessionManager()
    )
    .frame(height: 600)
}

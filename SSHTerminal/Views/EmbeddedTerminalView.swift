import SwiftUI
import AppKit

// MARK: - 内嵌终端视图
struct EmbeddedTerminalView: View {
    @StateObject private var session = SSHSessionManager()
    let connection: SSHConnection
    
    var body: some View {
        VStack(spacing: 0) {
            // 工具栏
            toolbar
            
            Divider()
            
            // 终端视图
            TerminalTextView(session: session)
        }
        .background(Color.black)
        .onAppear {
            session.connect(to: connection)
        }
        .onDisappear {
            session.disconnect()
        }
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

// MARK: - 终端 TextView（完整交互）
struct TerminalTextView: NSViewRepresentable {
    @ObservedObject var session: SSHSessionManager
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = TerminalNSTextView()
        
        // 配置 TextView - 设置为只读显示模式
        textView.isEditable = false  // 改为不可编辑，只响应键盘事件
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = NSColor.green
        textView.backgroundColor = NSColor.black
        textView.insertionPointColor = NSColor.green
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width, .height]
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.usesFindBar = true
        
        // 配置 TextContainer
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        
        // 配置 ScrollView
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.backgroundColor = NSColor.black
        
        // 设置 coordinator
        textView.terminalDelegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.session = session
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? TerminalNSTextView else { return }
        
        // 更新输出
        if context.coordinator.lastOutput != session.output {
            let oldOutput = context.coordinator.lastOutput
            let newOutput = session.output
            
            // 清理 ANSI 转义序列
            let cleanedNewOutput = ANSICleaner.clean(newOutput)
            let cleanedOldOutput = ANSICleaner.clean(oldOutput)
            
            context.coordinator.lastOutput = newOutput
            
            // 保存当前的选择范围
            let selectedRange = textView.selectedRange()
            let hasSelection = selectedRange.length > 0
            
            // 检查是否在底部（用于决定是否自动滚动）
            let visibleRect = scrollView.documentVisibleRect
            let contentHeight = textView.frame.height
            let scrollPosition = visibleRect.origin.y + visibleRect.height
            let isNearBottom = contentHeight - scrollPosition < 50
            
            // 只追加新内容
            if cleanedNewOutput.count > cleanedOldOutput.count &&
               cleanedNewOutput.hasPrefix(cleanedOldOutput) {
                let newText = String(cleanedNewOutput.dropFirst(cleanedOldOutput.count))
                let attributed = NSAttributedString(
                    string: newText,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                        .foregroundColor: NSColor.green
                    ]
                )
                textView.textStorage?.append(attributed)
            } else {
                // 完全替换
                let attributed = NSAttributedString(
                    string: cleanedNewOutput,
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                        .foregroundColor: NSColor.green
                    ]
                )
                textView.textStorage?.setAttributedString(attributed)
            }
            
            // 恢复选择或滚动到底部
            if hasSelection {
                // 如果有选中内容，保持选中
                textView.setSelectedRange(selectedRange)
                textView.scrollRangeToVisible(selectedRange)
            } else if isNearBottom {
                // 如果在底部附近，滚动到最底部
                let range = NSRange(location: textView.string.count, length: 0)
                textView.scrollRangeToVisible(range)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, TerminalTextViewDelegate {
        var textView: TerminalNSTextView?
        var session: SSHSessionManager?
        var lastOutput = ""
        
        func terminalTextView(_ textView: TerminalNSTextView, didReceiveInput input: String) {
            session?.sendInput(input)
        }
    }
}

// MARK: - 自定义 NSTextView
protocol TerminalTextViewDelegate: AnyObject {
    func terminalTextView(_ textView: TerminalNSTextView, didReceiveInput input: String)
}

class TerminalNSTextView: NSTextView {
    weak var terminalDelegate: TerminalTextViewDelegate?
    private var isProcessingInput = false
    
    override func keyDown(with event: NSEvent) {
        // 防止重复处理
        guard !isProcessingInput else {
            print("⚠️ 阻止重复输入")
            return
        }
        
        isProcessingInput = true
        defer {
            isProcessingInput = false
        }
        
        // 不调用 super.keyDown，完全自己处理
        handleKeyEvent(event)
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        
        // 处理特殊按键
        switch keyCode {
        case 36: // Enter/Return
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\n")
            
        case 48: // Tab
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\t")
            
        case 51: // Delete/Backspace
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{007F}")
            
        case 53: // Escape
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}")
            
        case 123: // Left Arrow
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[D")
            
        case 124: // Right Arrow
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[C")
            
        case 125: // Down Arrow
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[B")
            
        case 126: // Up Arrow
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[A")
            
        case 117: // Forward Delete
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[3~")
            
        case 115: // Home
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[H")
            
        case 119: // End
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[F")
            
        case 116: // Page Up
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[5~")
            
        case 121: // Page Down
            terminalDelegate?.terminalTextView(self, didReceiveInput: "\u{001B}[6~")
            
        default:
            // 检查 Ctrl 组合键
            if event.modifierFlags.contains(.control) {
                handleControlKey(event)
            } else if let chars = event.characters, !chars.isEmpty {
                // 普通字符
                terminalDelegate?.terminalTextView(self, didReceiveInput: chars)
            }
        }
    }
    
    private func handleControlKey(_ event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return }
        
        // Ctrl+A-Z 映射到控制字符 0x01-0x1A
        if let char = chars.first, let ascii = char.asciiValue {
            if ascii >= 97 && ascii <= 122 { // a-z
                let controlChar = Character(UnicodeScalar(ascii - 96))
                terminalDelegate?.terminalTextView(self, didReceiveInput: String(controlChar))
            }
        }
    }
    
    // 完全禁用文本编辑
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        return false
    }
    
    // 禁用插入文本
    override func insertText(_ string: Any, replacementRange: NSRange) {
        // 不做任何事
    }
    
    // 禁用删除
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
    
    // 禁用拼写检查等
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
    
    // 允许成为第一响应者
    override var acceptsFirstResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool {
        return true
    }
}

#Preview {
    EmbeddedTerminalView(connection: SSHConnection.examples[0])
        .frame(height: 600)
}

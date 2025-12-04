internal import SwiftUI
internal import SwiftTerm
internal import Combine
internal import AppKit

// MARK: - SwiftTerm 终端视图
struct SwiftTerminalView: View {
    let connection: SSHConnection
    @ObservedObject var session: SwiftTermSSHManager
    
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            SwiftTermViewWrapper(session: session)
        }
        .background(Color.black)
        .onAppear {
            print("🟣 [SwiftTerm] 终端视图已出现: \(connection.name)")
        }
    }
    
    private var toolbar: some View {
        HStack {
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
            
            HStack(spacing: 8) {
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

// MARK: - 自定义 TerminalView 类
class CustomTerminalView: TerminalView {
    
    // ⭐️ 拦截快捷键
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // 检查 Cmd+C
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            print("⌨️ 检测到 Cmd+C")
            handleCopy()
            return true
        }
        
        // 检查 Cmd+V
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "v" {
            print("⌨️ 检测到 Cmd+V")
            handlePaste()
            return true
        }
        
        return super.performKeyEquivalent(with: event)
    }
    
    // ⭐️ 处理复制
    private func handleCopy() {
        print("📋 handleCopy 被调用")
        
        guard let selection = getSelection() else {
            print("⚠️ 没有选中内容")
            return
        }
        
        print("✅ 有选中内容，开始提取")
        
        // 使用反射获取 selection 的属性
        let mirror = Mirror(reflecting: selection)
        var startRow = 0, startCol = 0, endRow = 0, endCol = 0
        
        for child in mirror.children {
            if let label = child.label {
                if label == "start" {
                    let startMirror = Mirror(reflecting: child.value)
                    for startChild in startMirror.children {
                        if startChild.label == "row", let row = startChild.value as? Int {
                            startRow = row
                        }
                        if startChild.label == "col", let col = startChild.value as? Int {
                            startCol = col
                        }
                    }
                }
                if label == "end" {
                    let endMirror = Mirror(reflecting: child.value)
                    for endChild in endMirror.children {
                        if endChild.label == "row", let row = endChild.value as? Int {
                            endRow = row
                        }
                        if endChild.label == "col", let col = endChild.value as? Int {
                            endCol = col
                        }
                    }
                }
            }
        }
        
        print("📋 选中范围: row[\(startRow):\(endRow)] col[\(startCol):\(endCol)]")
        
        // 提取文本
        guard let term = self.terminal else {
            print("⚠️ terminal 为 nil")
            return
        }
        
        var selectedText = ""
        
        for row in startRow...endRow {
            let lineStart = (row == startRow) ? startCol : 0
            let lineEnd = (row == endRow) ? endCol : term.cols
            
            for col in lineStart..<lineEnd {
                if let charData = term.getCharData(col: col, row: row) {
                    let character = charData.getCharacter()
                    selectedText.append(character)
                }
            }
            
            if row < endRow {
                selectedText.append("\n")
            }
        }
        
        // 去除尾部空格
        selectedText = selectedText.trimmingCharacters(in: .whitespaces)
        
        if !selectedText.isEmpty {
            print("📋 提取到文本: \(selectedText.prefix(100))...")
            
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(selectedText, forType: .string)
            
            print("✅ 已复制到剪贴板")
            NSSound.beep()
        } else {
            print("⚠️ 提取的文本为空")
        }
    }
    
    // ⭐️ 处理粘贴
    private func handlePaste() {
        print("📋 handlePaste 被调用")
        
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else {
            print("⚠️ 剪贴板中没有文本")
            return
        }
        
        print("📋 粘贴文本: \(text.prefix(50))...")
        
        if let data = text.data(using: .utf8) {
            let bytes = [UInt8](data)
            send(data: bytes[...])
            print("✅ 已发送到终端")
        }
    }
}

// MARK: - SwiftTerm View Wrapper
struct SwiftTermViewWrapper: NSViewRepresentable {
    @ObservedObject var session: SwiftTermSSHManager
    
    func makeNSView(context: Context) -> CustomTerminalView {
        let terminalView = CustomTerminalView()
        
        // ⭐️ 基本配置
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.caretColor = NSColor.white
        terminalView.selectedTextBackgroundColor = NSColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 0.5)
        terminalView.nativeBackgroundColor = NSColor.black
        terminalView.nativeForegroundColor = NSColor.white
        
        // ⭐️ 关键：禁用鼠标报告，启用本地选择
        terminalView.allowMouseReporting = false
        
        print("✅ [Terminal] allowMouseReporting = \(terminalView.allowMouseReporting)")
        
        // 设置 delegate
        terminalView.terminalDelegate = context.coordinator
        
        // 保存引用
        context.coordinator.terminalView = terminalView
        context.coordinator.sshSession = session
        
        // 设置数据接收闭包
        let coordinator = context.coordinator
        session.onDataReceived = { [weak coordinator] data in
            coordinator?.feedData(data)
        }
        
        print("✅ [Wrapper] SwiftTerm 视图已创建")
        
        // 确保视图可以成为第一响应者
        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
            print("✅ [Wrapper] 设置为第一响应者")
        }
        
        return terminalView
    }
    
    func updateNSView(_ terminalView: CustomTerminalView, context: Context) {
        // 确保视图保持为第一响应者
        if terminalView.window?.firstResponder != terminalView {
            DispatchQueue.main.async {
                terminalView.window?.makeFirstResponder(terminalView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, TerminalViewDelegate {
        weak var terminalView: CustomTerminalView?
        weak var sshSession: SwiftTermSSHManager?
        
        // MARK: - TerminalViewDelegate
        
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let dataArray = Data(data)
            sshSession?.send(data: dataArray)
        }
        
        func scrolled(source: TerminalView, position: Double) {
        }
        
        func setTerminalTitle(source: TerminalView, title: String) {
            print("📝 终端标题: \(title)")
        }
        
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            print("📐 终端尺寸: \(newCols)x\(newRows)")
        }
        
        func setTerminalIconTitle(source: TerminalView, title: String) {
        }
        
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            if let dir = directory {
                print("📁 当前目录: \(dir)")
            }
        }
        
        // ⭐️ SwiftTerm 的 clipboardCopy 回调
        func clipboardCopy(source: TerminalView, content: Data) {
            print("📋 [clipboardCopy] 被调用！数据大小: \(content.count) 字节")
            
            if let text = String(data: content, encoding: .utf8) ??
                          String(data: content, encoding: .ascii) ??
                          String(data: content, encoding: .isoLatin1) {
                
                print("📋 [clipboardCopy] 文本: \(text.prefix(100))...")
                
                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    print("✅ [clipboardCopy] 已复制到剪贴板")
                    NSSound.beep()
                }
            }
        }
        
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        }
        
        func bell(source: TerminalView) {
            NSSound.beep()
        }
        
        // MARK: - 数据接收
        func feedData(_ data: Data) {
            guard let terminalView = terminalView else { return }
            
            let buffer = Array(data)
            let arraySlice = buffer[...]
            
            DispatchQueue.main.async {
                terminalView.feed(byteArray: arraySlice)
            }
        }
    }
}

#Preview {
    SwiftTerminalView(
        connection: SSHConnection.examples[0],
        session: SwiftTermSSHManager()
    )
    .frame(height: 600)
}

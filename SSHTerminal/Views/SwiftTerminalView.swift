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

// MARK: - SwiftTerm View Wrapper
struct SwiftTermViewWrapper: NSViewRepresentable {
    @ObservedObject var session: SwiftTermSSHManager
    
    func makeNSView(context: Context) -> NSView {
        let terminalView = TerminalView()
        
        // ⭐️ 基本配置
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        terminalView.caretColor = NSColor.white
        terminalView.selectedTextBackgroundColor = NSColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 0.5)
        terminalView.nativeBackgroundColor = NSColor.black
        terminalView.nativeForegroundColor = NSColor.white
        
        // ⭐️ 关键：禁用鼠标报告，启用文本选择
        terminalView.allowMouseReporting = false
        terminalView.optionAsMetaKey = true
        
        // 设置 delegate
        terminalView.terminalDelegate = context.coordinator
        
        // 保存引用
        context.coordinator.terminalView = terminalView
        context.coordinator.sshSession = session
        
        // 设置容器视图
        let containerView = TerminalContainerView()
        containerView.coordinator = context.coordinator
        containerView.terminalView = terminalView
        containerView.addSubview(terminalView)
        
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: containerView.topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // 设置数据接收闭包
        session.onDataReceived = { [weak terminalView] data in
            guard let terminalView = terminalView else { return }
            let bytes = [UInt8](data)
            DispatchQueue.main.async {
                terminalView.feed(byteArray: bytes[...])
            }
        }
        
        print("✅ [Wrapper] SwiftTerm 视图已创建")
        
        return containerView
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let containerView = nsView as? TerminalContainerView,
              let terminalView = containerView.terminalView else { return }
        
        // 确保视图可以接收键盘事件
        DispatchQueue.main.async {
            if terminalView.window?.firstResponder != terminalView {
                terminalView.window?.makeFirstResponder(terminalView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, TerminalViewDelegate {
        weak var terminalView: TerminalView?
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
            print("📐 终端尺寸变化: \(newCols)x\(newRows)")
            
            Task { @MainActor in
                self.sshSession?.updateTerminalSize(cols: newCols, rows: newRows)
            }
        }
        
        func setTerminalIconTitle(source: TerminalView, title: String) {
        }
        
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            if let dir = directory {
                print("📁 当前目录: \(dir)")
            }
        }
        
        func clipboardCopy(source: TerminalView, content: Data) {
            print("📋 [clipboardCopy] SwiftTerm 调用，数据大小: \(content.count)")
            
            if let text = String(data: content, encoding: .utf8) {
                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    print("✅ [clipboardCopy] 已复制: \(text.prefix(100))...")
                    NSSound.beep()
                }
            }
        }
        
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        }
        
        func bell(source: TerminalView) {
            NSSound.beep()
        }
        
        // MARK: - 复制粘贴处理
        
        func handleCopy() {
            print("📋 [handleCopy] 开始处理...")
            
            guard let terminalView = terminalView else {
                print("❌ terminalView 为 nil")
                return
            }
            
            // ⭐️ 方法 1: 使用 SwiftTerm 的 getSelection
            if let selection = terminalView.getSelection() {
                print("📋 使用 getSelection() 获取选中内容")
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(selection, forType: .string)
                print("✅ 复制成功: \(selection.prefix(100))...")
                NSSound.beep()
                return
            }
            
            // ⭐️ 方法 2: 尝试调用 SwiftTerm 的内置 copy
            if terminalView.responds(to: #selector(NSText.copy(_:))) {
                print("📋 使用 SwiftTerm 内置 copy(_:)")
                terminalView.perform(#selector(NSText.copy(_:)), with: nil)
                
                // 等待一下，检查剪贴板
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let pasteboard = NSPasteboard.general
                    if let text = pasteboard.string(forType: .string), !text.isEmpty {
                        print("✅ 内置复制成功: \(text.prefix(100))...")
                        NSSound.beep()
                    } else {
                        print("⚠️ 内置复制未产生结果")
                    }
                }
                return
            }
            
            // ⭐️ 方法 3: 手动从终端缓冲区读取选中的内容
            print("📋 尝试手动读取选中内容...")
            if let selectedText = extractSelectedText(from: terminalView) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(selectedText, forType: .string)
                print("✅ 手动提取成功: \(selectedText.prefix(100))...")
                NSSound.beep()
                return
            }
            
            print("❌ 所有复制方法都失败了")
        }
        
        // ⭐️ 手动提取选中的文本
        private func extractSelectedText(from terminalView: TerminalView) -> String? {
            guard let terminal = terminalView.terminal else {
                print("⚠️ terminal 为 nil")
                return nil
            }
            
            // 尝试访问 selection 属性
            let mirror = Mirror(reflecting: terminalView)
            for child in mirror.children {
                if child.label == "selection" || child.label == "_selection" {
                    print("🔍 找到 selection 属性: \(child.value)")
                    
                    // 如果是 SelectionRange 类型，尝试提取
                    let selectionMirror = Mirror(reflecting: child.value)
                    var startCol = 0, startRow = 0, endCol = 0, endRow = 0
                    
                    for prop in selectionMirror.children {
                        print("  - \(prop.label ?? "?"): \(prop.value)")
                        
                        if prop.label == "start" {
                            let startMirror = Mirror(reflecting: prop.value)
                            for startProp in startMirror.children {
                                if startProp.label == "col" { startCol = startProp.value as? Int ?? 0 }
                                if startProp.label == "row" { startRow = startProp.value as? Int ?? 0 }
                            }
                        }
                        if prop.label == "end" {
                            let endMirror = Mirror(reflecting: prop.value)
                            for endProp in endMirror.children {
                                if endProp.label == "col" { endCol = endProp.value as? Int ?? 0 }
                                if endProp.label == "row" { endRow = endProp.value as? Int ?? 0 }
                            }
                        }
                    }
                    
                    if startRow != endRow || startCol != endCol {
                        print("📋 选区: (\(startRow),\(startCol)) -> (\(endRow),\(endCol))")
                        return extractText(from: terminal, startRow: startRow, startCol: startCol, endRow: endRow, endCol: endCol)
                    }
                }
            }
            
            return nil
        }
        
        private func extractText(from terminal: Terminal, startRow: Int, startCol: Int, endRow: Int, endCol: Int) -> String? {
            var text = ""
            
            for row in startRow...endRow {
                let lineStart = (row == startRow) ? startCol : 0
                let lineEnd = (row == endRow) ? endCol : terminal.cols - 1
                
                var lineText = ""
                for col in lineStart...lineEnd {
                    if let charData = terminal.getCharData(col: col, row: row) {
                        lineText.append(charData.getCharacter())
                    }
                }
                
                text += lineText.trimmingCharacters(in: .whitespaces)
                if row < endRow {
                    text += "\n"
                }
            }
            
            return text.isEmpty ? nil : text
        }
        
        func handlePaste() {
            guard let terminalView = terminalView else { return }
            
            let pasteboard = NSPasteboard.general
            guard let text = pasteboard.string(forType: .string) else {
                print("⚠️ 剪贴板中没有文本")
                return
            }
            
            print("📋 粘贴文本: \(text.prefix(50))...")
            
            if let data = text.data(using: .utf8) {
                let bytes = [UInt8](data)
                terminalView.send(data: bytes[...])
            }
        }
    }
}

// MARK: - 容器视图
class TerminalContainerView: NSView {
    weak var coordinator: SwiftTermViewWrapper.Coordinator?
    weak var terminalView: TerminalView?
    
    private var eventMonitor: Any?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupKeyHandling()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupKeyHandling()
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    private func setupKeyHandling() {
        // ⭐️ 使用本地事件监听器，优先级更高
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            let isCmd = event.modifierFlags.contains(.command)
            let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
            
            // Cmd+C - 复制
            if isCmd && char == "c" {
                print("⌨️ [Container] 拦截 Cmd+C")
                self.coordinator?.handleCopy()
                return nil // 阻止事件继续传播
            }
            
            // Cmd+V - 粘贴
            if isCmd && char == "v" {
                print("⌨️ [Container] 拦截 Cmd+V")
                self.coordinator?.handlePaste()
                return nil
            }
            
            // 其他按键传递给 TerminalView
            return event
        }
        
        print("✅ [Container] 键盘监听已设置")
    }
    
    // ⭐️ 覆盖 keyDown 作为备用方案
    override func keyDown(with event: NSEvent) {
        let isCmd = event.modifierFlags.contains(.command)
        let char = event.charactersIgnoringModifiers?.lowercased() ?? ""
        
        if isCmd && char == "c" {
            print("⌨️ [Container.keyDown] 处理 Cmd+C")
            coordinator?.handleCopy()
            return
        }
        
        if isCmd && char == "v" {
            print("⌨️ [Container.keyDown] 处理 Cmd+V")
            coordinator?.handlePaste()
            return
        }
        
        super.keyDown(with: event)
    }
    
    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
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

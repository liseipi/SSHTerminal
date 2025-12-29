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
            
            // ⭐️ 方法 1: 深度反射提取 selection 对象
            if let text = deepExtractSelection(from: terminalView), !text.isEmpty {
                print("✅ [深度提取] 成功，长度: \(text.count)")
                copyToClipboard(text)
                return
            }
            
            // ⭐️ 方法 2: 使用 SwiftTerm 的 getSelection
            if let selection = terminalView.getSelection(), !selection.isEmpty {
                print("✅ [getSelection] 成功，长度: \(selection.count)")
                copyToClipboard(selection)
                return
            }
            
            // ⭐️ 方法 3: 尝试从 Terminal 对象直接读取
            if let text = extractFromTerminalBuffer(terminalView), !text.isEmpty {
                print("✅ [Terminal缓冲区] 成功，长度: \(text.count)")
                copyToClipboard(text)
                return
            }
            
            print("❌ 所有复制方法都失败了")
            print("💡 提示：请确保用鼠标选中了文本")
            
            // 发出错误提示音
            DispatchQueue.main.async {
                NSSound(named: NSSound.Name("Basso"))?.play()
            }
        }
        
        // ⭐️ 深度反射提取 selection
        private func deepExtractSelection(from terminalView: TerminalView) -> String? {
            print("🔍 [深度提取] 开始...")
            
            let mirror = Mirror(reflecting: terminalView)
            
            for child in mirror.children {
                guard let label = child.label else { continue }
                
                // 找到 selection 属性
                if label == "selection" {
                    print("  找到 selection 属性")
                    
                    // 检查 selection 的类型
                    let selectionMirror = Mirror(reflecting: child.value)
                    print("  selection 类型: \(type(of: child.value))")
                    print("  selection 子属性数量: \(selectionMirror.children.count)")
                    
                    // 列出所有子属性
                    for selChild in selectionMirror.children {
                        let selLabel = selChild.label ?? "未知"
                        print("    - \(selLabel): \(type(of: selChild.value))")
                        
                        // 尝试提取 start 和 end
                        if selLabel == "start" {
                            let startMirror = Mirror(reflecting: selChild.value)
                            for startProp in startMirror.children {
                                print("      start.\(startProp.label ?? "?"): \(startProp.value)")
                            }
                        }
                        
                        if selLabel == "end" {
                            let endMirror = Mirror(reflecting: selChild.value)
                            for endProp in endMirror.children {
                                print("      end.\(endProp.label ?? "?"): \(endProp.value)")
                            }
                        }
                    }
                    
                    // 尝试提取选择范围
                    if let range = extractSelectionRange(from: child.value) {
                        print("  成功提取范围: \(range)")
                        
                        // 验证范围是否有效
                        if range.startRow == range.endRow && range.startCol == range.endCol {
                            print("  ⚠️ 选择范围为空（起点等于终点）")
                            return nil
                        }
                        
                        return extractTextFromRange(terminalView: terminalView, range: range)
                    } else {
                        print("  ⚠️ 无法提取选择范围")
                    }
                }
            }
            
            return nil
        }
        
        // ⭐️ 从 Terminal 缓冲区直接提取
        private func extractFromTerminalBuffer(_ terminalView: TerminalView) -> String? {
            print("🔍 [Terminal缓冲区] 尝试直接读取...")
            
            guard let terminal = terminalView.terminal else {
                print("  ⚠️ terminal 对象为 nil")
                return nil
            }
            
            // 尝试读取 terminal 的内部属性
            let terminalMirror = Mirror(reflecting: terminal)
            
            for child in terminalMirror.children {
                guard let label = child.label else { continue }
                
                if label.lowercased().contains("select") || label.lowercased().contains("buffer") {
                    print("  找到属性: \(label)")
                    
                    // 如果是 selection，尝试提取
                    if label.lowercased().contains("select") {
                        if let range = extractSelectionRange(from: child.value) {
                            print("  提取到选择范围")
                            return extractTextFromRange(terminalView: terminalView, range: range)
                        }
                    }
                }
            }
            
            print("  ⚠️ 未找到有用的属性")
            return nil
        }
        
        // 提取选择范围（增强版）
        private func extractSelectionRange(from value: Any) -> SelectionRange? {
            let mirror = Mirror(reflecting: value)
            
            // 检查是否是 Optional
            if mirror.displayStyle == .optional {
                // 如果是 nil，直接返回
                if mirror.children.count == 0 {
                    print("    selection 为 nil")
                    return nil
                }
                
                // 提取 Optional 的值
                if let firstChild = mirror.children.first {
                    return extractSelectionRange(from: firstChild.value)
                }
            }
            
            var startCol: Int?
            var startRow: Int?
            var endCol: Int?
            var endRow: Int?
            
            for child in mirror.children {
                let label = child.label ?? ""
                
                if label == "start" || label.contains("start") {
                    if let pos = extractPosition(from: child.value) {
                        startCol = pos.col
                        startRow = pos.row
                        print("    提取到 start: (\(pos.row), \(pos.col))")
                    }
                }
                
                if label == "end" || label.contains("end") {
                    if let pos = extractPosition(from: child.value) {
                        endCol = pos.col
                        endRow = pos.row
                        print("    提取到 end: (\(pos.row), \(pos.col))")
                    }
                }
                
                // 有些实现可能用不同的字段名
                if label == "startCol" { startCol = child.value as? Int }
                if label == "startRow" { startRow = child.value as? Int }
                if label == "endCol" { endCol = child.value as? Int }
                if label == "endRow" { endRow = child.value as? Int }
            }
            
            if let sc = startCol, let sr = startRow, let ec = endCol, let er = endRow {
                return SelectionRange(
                    startCol: sc,
                    startRow: sr,
                    endCol: ec,
                    endRow: er
                )
            }
            
            return nil
        }
        
        // 提取位置信息（增强版）
        private func extractPosition(from value: Any) -> (col: Int, row: Int)? {
            let mirror = Mirror(reflecting: value)
            
            // 检查是否是 Optional
            if mirror.displayStyle == .optional {
                if mirror.children.count == 0 {
                    return nil
                }
                if let firstChild = mirror.children.first {
                    return extractPosition(from: firstChild.value)
                }
            }
            
            var col: Int?
            var row: Int?
            
            for child in mirror.children {
                let label = child.label ?? ""
                
                if label == "col" || label == "column" || label == "x" {
                    col = child.value as? Int
                }
                
                if label == "row" || label == "line" || label == "y" {
                    row = child.value as? Int
                }
            }
            
            if let c = col, let r = row {
                return (c, r)
            }
            
            return nil
        }
        
        // 从范围提取文本（增强版）
        private func extractTextFromRange(terminalView: TerminalView, range: SelectionRange) -> String? {
            guard let terminal = terminalView.terminal else {
                print("  ⚠️ terminal 为 nil")
                return nil
            }
            
            print("  从范围提取文本: (\(range.startRow),\(range.startCol)) -> (\(range.endRow),\(range.endCol))")
            
            var text = ""
            let startRow = min(range.startRow, range.endRow)
            let endRow = max(range.startRow, range.endRow)
            
            for row in startRow...endRow {
                let lineStart: Int
                let lineEnd: Int
                
                if startRow == endRow {
                    // 单行选择
                    lineStart = min(range.startCol, range.endCol)
                    lineEnd = max(range.startCol, range.endCol)
                } else if row == startRow {
                    // 起始行
                    lineStart = range.startCol
                    lineEnd = terminal.cols - 1
                } else if row == endRow {
                    // 结束行
                    lineStart = 0
                    lineEnd = range.endCol
                } else {
                    // 中间行
                    lineStart = 0
                    lineEnd = terminal.cols - 1
                }
                
                var lineText = ""
                for col in lineStart...lineEnd {
                    if let charData = terminal.getCharData(col: col, row: row) {
                        let char = charData.getCharacter()
                        lineText.append(char)
                    }
                }
                
                // 保留行尾空格，但移除末尾的大量空格
                let trimmed = lineText.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
                text += trimmed
                
                if row < endRow {
                    text += "\n"
                }
            }
            
            let finalText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            print("  提取的文本长度: \(finalText.count)")
            
            return finalText.isEmpty ? nil : finalText
        }
        
        // 复制到剪贴板
        private func copyToClipboard(_ text: String) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let success = pasteboard.setString(text, forType: .string)
            
            if success {
                print("✅ 已复制到剪贴板，长度: \(text.count)")
                print("   内容前100字符: '\(text.prefix(100))'")
                
                // 验证
                if let verified = pasteboard.string(forType: .string) {
                    print("✅ 剪贴板验证成功，长度: \(verified.count)")
                }
                
                NSSound.beep()
            } else {
                print("❌ 复制到剪贴板失败")
            }
        }
        
        func handlePaste() {
            guard let terminalView = terminalView else { return }
            
            let pasteboard = NSPasteboard.general
            guard let text = pasteboard.string(forType: .string) else {
                print("⚠️ 剪贴板中没有文本")
                return
            }
            
            print("📋 粘贴文本长度: \(text.count)")
            
            if let data = text.data(using: .utf8) {
                let bytes = [UInt8](data)
                terminalView.send(data: bytes[...])
            }
        }
    }
}

// MARK: - 辅助结构
private struct SelectionRange: CustomStringConvertible {
    let startCol: Int
    let startRow: Int
    let endCol: Int
    let endRow: Int
    
    var description: String {
        "(\(startRow),\(startCol)) -> (\(endRow),\(endCol))"
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

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

// MARK: - 自定义 TerminalView 包装器，支持选择追踪
class SelectableTerminalView: NSView {
    let terminalView: TerminalView
    weak var coordinator: SwiftTermViewWrapper.Coordinator?
    
    // 追踪选择状态
    private var selectionStart: Position?
    private var selectionEnd: Position?
    private var isSelecting = false
    
    // 鼠标事件监听器
    private var mouseMonitor: Any?
    
    struct Position {
        let row: Int
        let col: Int
    }
    
    init(terminalView: TerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        
        addSubview(terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        setupMouseTracking()
        
        print("✅ [SelectableTerminalView] 已创建")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // ⭐️ 使用全局鼠标监听器来捕获事件
    private func setupMouseTracking() {
        // 监听鼠标按下事件
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self = self,
                  let window = self.window,
                  let eventWindow = event.window,
                  window == eventWindow else {
                return event
            }
            
            // 检查事件是否在我们的视图范围内
            let locationInWindow = event.locationInWindow
            let locationInView = self.convert(locationInWindow, from: nil)
            
            guard self.bounds.contains(locationInView) else {
                return event
            }
            
            switch event.type {
            case .leftMouseDown:
                if let pos = self.locationToTerminalPosition(locationInView) {
                    self.selectionStart = pos
                    self.selectionEnd = pos
                    self.isSelecting = true
                    print("🖱️ 开始选择: row=\(pos.row), col=\(pos.col)")
                }
                
            case .leftMouseDragged:
                if self.isSelecting, let pos = self.locationToTerminalPosition(locationInView) {
                    self.selectionEnd = pos
                    print("🖱️ 拖动选择到: row=\(pos.row), col=\(pos.col)")
                }
                
            case .leftMouseUp:
                if self.isSelecting, let pos = self.locationToTerminalPosition(locationInView) {
                    self.selectionEnd = pos
                    self.isSelecting = false
                    print("🖱️ 结束选择: start=(\(self.selectionStart?.row ?? 0),\(self.selectionStart?.col ?? 0)) end=(\(pos.row),\(pos.col))")
                }
                
            default:
                break
            }
            
            // 仍然将事件传递给 TerminalView 以保持正常功能
            return event
        }
        
        print("✅ [SelectableTerminalView] 鼠标追踪已设置")
    }
    
    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    // 将屏幕坐标转换为终端坐标
    private func locationToTerminalPosition(_ location: NSPoint) -> Position? {
        guard let terminal = terminalView.terminal else {
            print("⚠️ terminal 为 nil")
            return nil
        }
        
        let font = terminalView.font
        let charWidth = font.maximumAdvancement.width
        let charHeight = font.boundingRectForFont.height
        
        print("🔍 字符尺寸: width=\(charWidth), height=\(charHeight)")
        print("🔍 鼠标位置: x=\(location.x), y=\(location.y)")
        
        let col = Int(location.x / charWidth)
        let row = Int((bounds.height - location.y) / charHeight)
        
        print("🔍 计算坐标: col=\(col), row=\(row)")
        print("🔍 终端尺寸: cols=\(terminal.cols), rows=\(terminal.rows)")
        
        // 确保坐标在有效范围内
        let validCol = max(0, min(col, terminal.cols - 1))
        let validRow = max(0, min(row, terminal.rows - 1))
        
        print("🔍 有效坐标: col=\(validCol), row=\(validRow)")
        
        return Position(row: validRow, col: validCol)
    }
    
    // 获取选中的文本
    func getSelectedText() -> String? {
        guard let start = selectionStart,
              let end = selectionEnd,
              let terminal = terminalView.terminal else {
            print("⚠️ 没有选择或 terminal 为 nil")
            return nil
        }
        
        // 确保 start 在 end 之前
        let (actualStart, actualEnd) = start.row < end.row || (start.row == end.row && start.col <= end.col)
            ? (start, end)
            : (end, start)
        
        print("📋 提取选中文本: start=(\(actualStart.row),\(actualStart.col)) end=(\(actualEnd.row),\(actualEnd.col))")
        
        var selectedText = ""
        
        for row in actualStart.row...actualEnd.row {
            let lineStart = (row == actualStart.row) ? actualStart.col : 0
            let lineEnd = (row == actualEnd.row) ? actualEnd.col : terminal.cols - 1
            
            for col in lineStart...lineEnd {
                if let charData = terminal.getCharData(col: col, row: row) {
                    selectedText.append(charData.getCharacter())
                }
            }
            
            if row < actualEnd.row {
                selectedText.append("\n")
            }
        }
        
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("📋 提取到文本: '\(trimmed.prefix(100))...'")
        
        return trimmed.isEmpty ? nil : trimmed
    }
    
    // 清除选择
    func clearSelection() {
        selectionStart = nil
        selectionEnd = nil
        isSelecting = false
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
        
        // ⭐️ 关键配置
        terminalView.allowMouseReporting = false
        terminalView.optionAsMetaKey = true
        
        // 设置 delegate
        terminalView.terminalDelegate = context.coordinator
        
        // ⭐️ 使用自定义包装器来追踪选择
        let selectableView = SelectableTerminalView(terminalView: terminalView)
        selectableView.coordinator = context.coordinator
        
        // 保存引用
        context.coordinator.selectableView = selectableView
        context.coordinator.terminalView = terminalView
        context.coordinator.sshSession = session
        
        // 设置容器
        let containerView = TerminalContainerView()
        containerView.coordinator = context.coordinator
        containerView.addSubview(selectableView)
        
        selectableView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            selectableView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            selectableView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            selectableView.topAnchor.constraint(equalTo: containerView.topAnchor),
            selectableView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
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
              let selectableView = context.coordinator.selectableView else { return }
        
        // 确保视图可以接收键盘事件
        DispatchQueue.main.async {
            if selectableView.terminalView.window?.firstResponder != selectableView.terminalView {
                selectableView.terminalView.window?.makeFirstResponder(selectableView.terminalView)
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, TerminalViewDelegate {
        weak var selectableView: SelectableTerminalView?
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
            print("📋 [clipboardCopy] 被 SwiftTerm 调用，数据大小: \(content.count)")
            
            if let text = String(data: content, encoding: .utf8) {
                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    print("✅ [clipboardCopy] 已复制到剪贴板: \(text.prefix(50))...")
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
            print("📋 开始处理复制...")
            
            // ⭐️ 使用我们自己追踪的选择
            if let text = selectableView?.getSelectedText() {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
                print("✅ 复制成功: \(text.prefix(50))...")
                NSSound.beep()
                return
            }
            
            // 备用方案：尝试 SwiftTerm 的内置复制
            if let terminalView = terminalView,
               terminalView.responds(to: #selector(NSText.copy(_:))) {
                print("📋 尝试使用 SwiftTerm 内置复制...")
                terminalView.perform(#selector(NSText.copy(_:)), with: nil)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let pasteboard = NSPasteboard.general
                    if let text = pasteboard.string(forType: .string), !text.isEmpty {
                        print("✅ SwiftTerm 内置复制成功: \(text.prefix(50))...")
                        NSSound.beep()
                    } else {
                        print("❌ 复制失败：没有选中内容")
                    }
                }
                return
            }
            
            print("❌ 复制失败：没有找到可用的方法")
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
    
    private var eventMonitor: Any?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupKeyHandling()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupKeyHandling()
    }
    
    private func setupKeyHandling() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Cmd+C - 复制
            if event.modifierFlags.contains(.command) &&
               event.charactersIgnoringModifiers == "c" {
                print("⌨️ 检测到 Cmd+C")
                self.coordinator?.handleCopy()
                return nil
            }
            
            // Cmd+V - 粘贴
            if event.modifierFlags.contains(.command) &&
               event.charactersIgnoringModifiers == "v" {
                print("⌨️ 检测到 Cmd+V")
                self.coordinator?.handlePaste()
                return nil
            }
            
            return event
        }
        
        print("✅ [Container] 键盘监听已设置")
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

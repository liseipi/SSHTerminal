internal import SwiftUI
internal import SwiftTerm
internal import Combine

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
    
    func makeNSView(context: Context) -> TerminalView {
        let terminalView = TerminalView()
        
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalView.caretColor = NSColor.white
        terminalView.selectedTextBackgroundColor = NSColor(red: 0.3, green: 0.4, blue: 0.6, alpha: 0.5)
        
        // 设置 SwiftTerm 的 delegate
        terminalView.terminalDelegate = context.coordinator
        
        // 保存引用
        context.coordinator.terminalView = terminalView
        context.coordinator.sshSession = session
        
        // 设置数据接收闭包
        let coordinator = context.coordinator
        session.onDataReceived = { [weak coordinator] data in
            coordinator?.feedData(data)
        }
        
        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
        }
        
        print("✅ SwiftTerm 视图已创建")
        
        return terminalView
    }
    
    func updateNSView(_ terminalView: TerminalView, context: Context) {
        // SwiftTerm 自动处理
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, TerminalViewDelegate {
        weak var terminalView: TerminalView?
        weak var sshSession: SwiftTermSSHManager?
        
        // MARK: - TerminalViewDelegate (SwiftTerm 必需方法)
        
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
        
        func clipboardCopy(source: TerminalView, content: Data) {
            if let text = String(data: content, encoding: .utf8) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }
        
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        }
        
        func bell(source: TerminalView) {
            NSSound.beep()
        }
        
        // MARK: - 接收 SSH 输出
        func feedData(_ data: Data) {
            guard let terminalView = terminalView else { return }
            let buffer = Array(data)
            let arraySlice = buffer[...]
            terminalView.feed(byteArray: arraySlice)
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

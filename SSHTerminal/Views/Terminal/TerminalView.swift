import SwiftUI

struct TerminalView: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部
            HStack {
                Label(viewModel.activeConnection?.name ?? "未连接", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                
                if viewModel.activeConnection != nil {
                    // 当前路径显示
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.caption)
                        Text(viewModel.currentPath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(4)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 终端区域（完全模拟真实 Terminal）
            TerminalContentView(viewModel: viewModel, isInputFocused: $isInputFocused)
                .background(Color.black)
        }
    }
}

struct TerminalContentView: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    @FocusState.Binding var isInputFocused: Bool
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.activeConnection == nil {
                        // 未连接状态
                        VStack(spacing: 16) {
                            Image(systemName: "terminal")
                                .font(.system(size: 48))
                                .foregroundColor(.gray)
                            Text("请从左侧选择一个连接")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    } else {
                        // 终端内容
                        ForEach(viewModel.terminalLines) { line in
                            TerminalLineView(line: line)
                                .id(line.id)
                        }
                        
                        // 当前输入行（光标在当前位置）
                        if viewModel.activeConnection != nil {
                            CurrentInputLine(
                                viewModel: viewModel,
                                isInputFocused: $isInputFocused
                            )
                            .id("currentInput")
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: viewModel.terminalLines.count) { _ in
                withAnimation {
                    proxy.scrollTo("currentInput", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.currentCommand) { _ in
                proxy.scrollTo("currentInput", anchor: .bottom)
            }
        }
        .onAppear {
            isInputFocused = true
        }
        .onTapGesture {
            isInputFocused = true
        }
    }
}

struct TerminalLineView: View {
    let line: TerminalLine
    
    var body: some View {
        Text(line.text)
            .font(.system(size: 13, design: .monospaced))
            .foregroundColor(line.type.color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CurrentInputLine: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    @FocusState.Binding var isInputFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // 提示符
            if let connection = viewModel.activeConnection {
                Text("\(connection.username)@\(connection.host):\(viewModel.currentPath)$ ")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.blue)
            }
            
            // 输入框
            ZStack(alignment: .leading) {
                // 占位文本
                if viewModel.currentCommand.isEmpty {
                    Text("输入命令...")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.5))
                }
                
                // 实际输入
                TextField("", text: $viewModel.currentCommand)
                    .font(.system(size: 13, design: .monospaced))
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .focused($isInputFocused)
                    .onSubmit {
                        viewModel.executeCommand()
                        isInputFocused = true
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

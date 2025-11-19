import SwiftUI

struct TerminalView: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab 栏
            if !viewModel.tabs.isEmpty {
                TerminalTabBar(viewModel: viewModel)
                Divider()
            }
            
            // 终端内容
            if let activeTab = viewModel.activeTab {
                TerminalContentViewWithTab(
                    viewModel: viewModel,
                    tab: activeTab
                )
            } else {
                EmptyTerminalView()
            }
        }
    }
}

struct EmptyTerminalView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.5))
            
            VStack(spacing: 8) {
                Text("没有打开的终端")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("双击左侧连接打开新标签页")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

struct TerminalContentViewWithTab: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    let tab: TerminalTab
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部信息栏
            HStack {
                Label(tab.displayName, systemImage: "terminal")
                    .font(.headline)
                
                Spacer()
                
                // 当前路径显示
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption)
                    Text(tab.currentPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(4)
                
                // 连接状态
                HStack(spacing: 4) {
                    if tab.connectionStatus == "已连接" {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                    } else if tab.connectionStatus == "正在连接..." {
                        ProgressView()
                            .controlSize(.small)
                    } else if tab.connectionStatus == "连接失败" {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                    }
                    Text(tab.connectionStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(4)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // 终端区域
            TerminalContentArea(
                viewModel: viewModel,
                tab: tab,
                isInputFocused: $isInputFocused
            )
            .background(Color.black)
        }
    }
}

struct TerminalContentArea: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    let tab: TerminalTab
    @FocusState.Binding var isInputFocused: Bool
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 终端内容
                    ForEach(tab.terminalLines) { line in
                        TerminalLineView(line: line)
                            .id(line.id)
                    }
                    
                    // 当前输入行
                    if tab.connectionStatus == "已连接" {
                        CurrentInputLineWithTab(
                            viewModel: viewModel,
                            tab: tab,
                            isInputFocused: $isInputFocused
                        )
                        .id("currentInput")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: tab.terminalLines.count) { _ in
                withAnimation {
                    proxy.scrollTo("currentInput", anchor: .bottom)
                }
            }
            .onChange(of: tab.currentCommand) { _ in
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

struct CurrentInputLineWithTab: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    let tab: TerminalTab
    @FocusState.Binding var isInputFocused: Bool
    
    var body: some View {
        HStack(spacing: 0) {
            // 提示符
            Text("\(tab.connection.username)@\(tab.connection.host):\(tab.currentPath)$ ")
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.blue)
            
            // 输入框
            ZStack(alignment: .leading) {
                // 占位文本
                if tab.currentCommand.isEmpty {
                    Text("输入命令...")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.gray.opacity(0.5))
                }
                
                // 实际输入
                TextField("", text: binding(for: tab))
                    .font(.system(size: 13, design: .monospaced))
                    .textFieldStyle(.plain)
                    .foregroundColor(.white)
                    .focused($isInputFocused)
                    .onSubmit {
                        viewModel.executeCommand(tabId: tab.id)
                        isInputFocused = true
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func binding(for tab: TerminalTab) -> Binding<String> {
        Binding(
            get: {
                if let index = viewModel.tabs.firstIndex(where: { $0.id == tab.id }) {
                    return viewModel.tabs[index].currentCommand
                }
                return ""
            },
            set: { newValue in
                if let index = viewModel.tabs.firstIndex(where: { $0.id == tab.id }) {
                    viewModel.tabs[index].currentCommand = newValue
                }
            }
        )
    }
}

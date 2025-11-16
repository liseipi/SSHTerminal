import SwiftUI

struct TerminalView: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(viewModel.activeConnection?.name ?? "未连接", systemImage: "terminal")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if viewModel.activeConnection == nil {
                            Text("请从左侧选择一个连接")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.top, 100)
                        } else {
                            ForEach(viewModel.terminalLines) { line in
                                Text(line.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(line.type.color)
                                    .textSelection(.enabled)
                                    .id(line.id)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color.black)
                .onChange(of: viewModel.terminalLines.count) { _ in
                    if let lastLine = viewModel.terminalLines.last {
                        withAnimation {
                            proxy.scrollTo(lastLine.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            if viewModel.activeConnection != nil {
                Divider()
                HStack(spacing: 8) {
                    if let connection = viewModel.activeConnection {
                        Text("\(connection.username)@\(connection.host):\(viewModel.currentPath)$")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.blue)
                    }
                    
                    TextField("输入命令...", text: $viewModel.currentCommand)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .onSubmit {
                            viewModel.executeCommand()
                        }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
    }
}

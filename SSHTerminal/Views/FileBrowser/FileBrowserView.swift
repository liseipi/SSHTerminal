import SwiftUI

struct FileBrowserView: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                HStack {
                    Label("文件浏览", systemImage: "folder")
                        .font(.headline)
                    Spacer()
                }
                
                if viewModel.activeConnection != nil {
                    HStack {
                        Image(systemName: "house")
                            .font(.caption)
                        Text(viewModel.currentPath)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(4)
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                if viewModel.activeConnection == nil {
                    Text("连接服务器后查看文件")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                } else if viewModel.fileTree.isEmpty {
                    Text("目录为空")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.fileTree) { item in
                            FileItemRow(item: item, level: 0)
                        }
                    }
                }
            }
            
            if viewModel.activeConnection != nil {
                Divider()
                HStack(spacing: 8) {
                    Button("/home") { viewModel.loadDirectory(path: "/home") }
                        .buttonStyle(.bordered)
                    Button("/var") { viewModel.loadDirectory(path: "/var") }
                        .buttonStyle(.bordered)
                    Button("/etc") { viewModel.loadDirectory(path: "/etc") }
                        .buttonStyle(.bordered)
                }
                .padding()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
}

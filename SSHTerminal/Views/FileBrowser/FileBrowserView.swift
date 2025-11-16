import SwiftUI

struct FileBrowserView: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    @State private var selectedFile: FileItem?
    
    var body: some View {
        VStack(spacing: 0) {
            // 头部
            headerView
            
            Divider()
            
            // 主内容
            if viewModel.activeConnection == nil {
                disconnectedView
            } else {
                fileListView
            }
            
            // 底部快捷导航
            if viewModel.activeConnection != nil {
                Divider()
                QuickNavigationBar(viewModel: viewModel)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - 子视图
    
    private var headerView: some View {
        VStack(spacing: 8) {
            HStack {
                Label("服务器目录", systemImage: "folder")
                    .font(.headline)
                Spacer()
                
                if viewModel.activeConnection != nil {
                    Button(action: {
                        viewModel.loadDirectory(path: viewModel.currentPath)
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("刷新")
                }
            }
            
            if viewModel.activeConnection != nil {
                PathBreadcrumbView(viewModel: viewModel)
            }
        }
        .padding()
    }
    
    private var disconnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.gray)
            Text("连接服务器后查看目录")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var fileListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // 返回上级目录
                if shouldShowParentDirectory {
                    ParentDirectoryRow {
                        viewModel.navigateToParent()
                    }
                    Divider()
                }
                
                // 文件列表内容
                fileListContent
            }
        }
    }
    
    private var shouldShowParentDirectory: Bool {
        viewModel.currentPath != "~" && viewModel.currentPath != "/"
    }
    
    @ViewBuilder
    private var fileListContent: some View {
        if viewModel.fileTree.isEmpty && !viewModel.isLoadingFiles {
            emptyDirectoryView
        } else if viewModel.isLoadingFiles {
            loadingView
        } else {
            filesView
        }
    }
    
    private var emptyDirectoryView: some View {
        Text("目录为空")
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding()
    }
    
    private var loadingView: some View {
        HStack {
            ProgressView()
                .controlSize(.small)
            Text("加载中...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    private var filesView: some View {
        ForEach(viewModel.fileTree) { item in
            FileItemRowView(
                item: item,
                isSelected: selectedFile?.id == item.id
            ) {
                selectedFile = item
                if item.type == .directory {
                    viewModel.navigateToDirectory(item.name)
                }
            } onDoubleClick: {
                if item.type == .file {
                    viewModel.openFile(item.name)
                }
            }
            Divider()
        }
    }
}

// MARK: - 面包屑导航
struct PathBreadcrumbView: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    
    private var pathComponents: [String] {
        let path = viewModel.currentPath
        if path == "~" {
            return ["~"]
        }
        return path.split(separator: "/").map(String.init)
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                ForEach(Array(pathComponents.enumerated()), id: \.offset) { index, component in
                    breadcrumbItem(component: component, index: index)
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(4)
        }
    }
    
    private func breadcrumbItem(component: String, index: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Button(component) {
                let targetPath = buildPath(upTo: index)
                viewModel.loadDirectory(path: targetPath)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundColor(index == pathComponents.count - 1 ? .primary : .blue)
        }
    }
    
    private func buildPath(upTo index: Int) -> String {
        if pathComponents[0] == "~" {
            return "~" + "/" + pathComponents[1...index].joined(separator: "/")
        }
        return "/" + pathComponents[0...index].joined(separator: "/")
    }
}

// MARK: - 上级目录行
struct ParentDirectoryRow: View {
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.up.left")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                
                Text("..")
                    .font(.system(size: 13, design: .monospaced))
                
                Spacer()
                
                Text("返回上级")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 文件项行
struct FileItemRowView: View {
    let item: FileItem
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleClick: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                fileIcon
                fileName
                Spacer()
                fileSize
                directoryIndicator
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
    }
    
    private var fileIcon: some View {
        Image(systemName: item.type == .directory ? "folder.fill" : "doc.fill")
            .foregroundColor(item.type == .directory ? .yellow : .blue)
            .frame(width: 20)
    }
    
    private var fileName: some View {
        Text(item.name)
            .font(.system(size: 13))
            .lineLimit(1)
    }
    
    @ViewBuilder
    private var fileSize: some View {
        if let size = item.size {
            Text(size)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var directoryIndicator: some View {
        if item.type == .directory {
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.blue.opacity(0.1)
        } else if isHovering {
            return Color.gray.opacity(0.1)
        } else {
            return Color.clear
        }
    }
}

// MARK: - 快捷导航栏
struct QuickNavigationBar: View {
    @ObservedObject var viewModel: SSHTerminalViewModel
    
    private let quickPaths: [(String, String, String)] = [
        ("~", "house.fill", "主目录"),
        ("/", "folder.fill", "根目录"),
        ("/home", "person.2.fill", "用户"),
        ("/var", "externaldrive.fill", "系统"),
        ("/etc", "gearshape.fill", "配置"),
        ("/tmp", "trash.fill", "临时")
    ]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickPaths, id: \.0) { path, icon, label in
                    quickButton(path: path, icon: icon, label: label)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    private func quickButton(path: String, icon: String, label: String) -> some View {
        Button(action: {
            viewModel.loadDirectory(path: path)
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 50)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

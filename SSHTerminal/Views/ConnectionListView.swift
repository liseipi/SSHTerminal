import SwiftUI

struct ConnectionListView: View {
    @StateObject private var storage = ConnectionStorage.shared
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var selectedConnection: SSHConnection?
    @State private var showingAddSheet = false
    @State private var editingConnection: SSHConnection?
    @State private var selectedTerminal: TerminalApp = .terminal
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showKeychainTip = false
    @State private var useEmbeddedTerminal = true
    
    var filteredConnections: [SSHConnection] {
        var result = storage.connections
        
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }
        
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(query) ||
                $0.host.lowercased().contains(query) ||
                $0.username.lowercased().contains(query)
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            connectionListContent
        } detail: {
            terminalDetail
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showingAddSheet) {
            AddConnectionSheet(onSave: { connection in
                storage.addConnection(connection)
            })
        }
        .sheet(item: $editingConnection) { connection in
            EditConnectionSheet(connection: connection, onSave: { updated in
                storage.updateConnection(updated)
            })
        }
        .alert("提示", isPresented: $showAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("Keychain 访问提示", isPresented: $showKeychainTip) {
            Button("知道了", role: .cancel) {
                UserDefaults.standard.set(true, forKey: "hasShownKeychainTip")
            }
            Button("查看详细说明") {
                UserDefaults.standard.set(true, forKey: "hasShownKeychainTip")
            }
        } message: {
            Text("""
            首次使用密码认证时，系统会要求访问 Keychain。
            
            请点击"始终允许"，这样以后就不会再提示了。
            
            提示：使用 SSH 密钥认证更安全，且无需此权限。
            """)
        }
        .onAppear {
            if !UserDefaults.standard.bool(forKey: "hasShownKeychainTip") {
                let hasPasswordAuth = storage.connections.contains { $0.authMethod == .password }
                if hasPasswordAuth {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        showKeychainTip = true
                    }
                }
            }
        }
    }
    
    // MARK: - 侧边栏
    private var sidebar: some View {
        List(selection: $selectedTag) {
            Section("标签") {
                NavigationLink(value: nil as String?) {
                    Label("全部连接", systemImage: "square.grid.2x2")
                }
                
                ForEach(storage.allTags, id: \.self) { tag in
                    NavigationLink(value: tag) {
                        Label(tag, systemImage: "tag")
                    }
                }
            }
        }
        .navigationTitle("SSH Manager")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
    }
    
    // MARK: - 连接列表内容
    private var connectionListContent: some View {
        VStack(spacing: 0) {
            connectionListToolbar
            
            Divider()
            
            if filteredConnections.isEmpty {
                emptyState
            } else {
                List(selection: $selectedConnection) {
                    ForEach(filteredConnections) { connection in
                        ConnectionRowCompact(connection: connection)
                            .tag(connection)
                            .contextMenu {
                                Button("连接") {
                                    connectToServer(connection)
                                }
                                Button("在系统终端打开") {
                                    openInSystemTerminal(connection)
                                }
                                Divider()
                                Button("编辑") {
                                    editingConnection = connection
                                }
                                Button("删除", role: .destructive) {
                                    storage.deleteConnection(connection)
                                }
                            }
                    }
                    .onDelete { indexSet in
                        storage.deleteConnections(at: indexSet)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle(selectedTag ?? "所有连接")
        .frame(minWidth: 300, idealWidth: 350)
    }
    
    // MARK: - 终端详情视图
    private var terminalDetail: some View {
        Group {
            if let connection = selectedConnection {
                EmbeddedTerminalView(connection: connection)
            } else {
                terminalPlaceholder
            }
        }
        .frame(minWidth: 600)
    }
    
    // MARK: - 终端占位符
    private var terminalPlaceholder: some View {
        VStack(spacing: 20) {
            Image(systemName: "terminal")
                .font(.system(size: 80))
                .foregroundColor(.secondary)
            
            Text("选择一个连接")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("在左侧列表中点击连接以开始")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - 连接列表工具栏
    private var connectionListToolbar: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索连接...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            
            Button(action: { showingAddSheet = true }) {
                Label("添加", systemImage: "plus")
            }
        }
        .padding()
    }
    
    // MARK: - 空状态
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("没有连接")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(searchText.isEmpty ? "点击上方 + 按钮添加SSH连接" : "没有找到匹配的连接")
                .foregroundColor(.secondary)
            
            if searchText.isEmpty {
                Button(action: { showingAddSheet = true }) {
                    Label("添加连接", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - 连接到服务器
    private func connectToServer(_ connection: SSHConnection) {
        if useEmbeddedTerminal {
            selectedConnection = connection
            storage.updateLastUsed(connection)
        } else {
            openInSystemTerminal(connection)
        }
    }
    
    // MARK: - 在系统终端打开
    private func openInSystemTerminal(_ connection: SSHConnection) {
        let success = TerminalLauncher.shared.openConnection(connection, in: selectedTerminal)
        
        if success {
            storage.updateLastUsed(connection)
        } else {
            alertMessage = "无法打开\(selectedTerminal.displayName)，请检查应用是否已安装"
            showAlert = true
        }
    }
}

// MARK: - 紧凑连接行视图
struct ConnectionRowCompact: View {
    let connection: SSHConnection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(connection.name)
                .font(.headline)
            
            Text(connection.displayDescription)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if !connection.tags.isEmpty {
                HStack(spacing: 4) {
                    ForEach(connection.tags.prefix(2), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(3)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    ConnectionListView()
        .frame(width: 1200, height: 800)
}

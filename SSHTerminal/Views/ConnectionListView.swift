internal import SwiftUI
internal import Combine
internal import SwiftTerm

struct ConnectionListView: View {
    @StateObject private var storage = ConnectionStorage.shared
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var showingAddSheet = false
    @State private var editingConnection: SSHConnection?
    @State private var selectedTerminal: TerminalApp = .terminal
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showKeychainTip = false
    @State private var openTabs: [TerminalTab] = []
    @State private var selectedTabId: UUID?
    
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
        HSplitView {
            connectionListPanel
                .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
            
            terminalTabsPanel
                .frame(minWidth: 600)
        }
        .frame(minWidth: 800, minHeight: 600)
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
    
    // MARK: - 连接列表面板
    private var connectionListPanel: some View {
        VStack(spacing: 0) {
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
                    Image(systemName: "plus")
                }
                .help("添加连接")
            }
            .padding()
            
            Divider()
            
            if !storage.allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        TagFilterButton(
                            title: "全部",
                            isSelected: selectedTag == nil,
                            action: { selectedTag = nil }
                        )
                        
                        ForEach(storage.allTags, id: \.self) { tag in
                            TagFilterButton(
                                title: tag,
                                isSelected: selectedTag == tag,
                                action: { selectedTag = tag }
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                Divider()
            }
            
            if filteredConnections.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredConnections) { connection in
                        ConnectionRowCompact(connection: connection)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                // 双击打开连接
                                openConnectionInNewTab(connection)
                            }
                            .contextMenu {
                                Button("在新标签页打开") {
                                    openConnectionInNewTab(connection)
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
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("SSH 连接")
    }
    
    // MARK: - 终端标签页面板
    private var terminalTabsPanel: some View {
        VStack(spacing: 0) {
            if !openTabs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(openTabs) { tab in
                            TabButton(
                                tab: tab,
                                isSelected: selectedTabId == tab.id,
                                onSelect: { selectedTabId = tab.id },
                                onClose: { closeTab(tab) }
                            )
                        }
                    }
                }
                .frame(height: 36)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
            }
            
            if openTabs.isEmpty {
                welcomeView
            } else {
                ZStack {
                    ForEach(openTabs) { tab in
                        SwiftTerminalView(
                            connection: tab.connection,
                            session: tab.session
                        )
                        .opacity(selectedTabId == tab.id ? 1 : 0)
                        .zIndex(selectedTabId == tab.id ? 1 : 0)
                        .id(tab.id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - 欢迎视图
    private var welcomeView: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("SSH Terminal Manager")
                .font(.title)
                .fontWeight(.bold)
            
            Text("选择左侧的连接开始")
                .font(.title3)
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button(action: { showingAddSheet = true }) {
                    Label("添加连接", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                
                Button(action: { /* 打开帮助 */ }) {
                    Label("使用指南", systemImage: "book.fill")
                        .font(.headline)
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
                .frame(height: 40)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "1.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("点击左侧 + 按钮添加 SSH 连接")
                }
                
                HStack {
                    Image(systemName: "2.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("点击连接名称在新标签页中打开终端")
                }
                
                HStack {
                    Image(systemName: "3.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("支持多个标签页同时连接不同服务器")
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
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
    
    // MARK: - 操作方法
    private func openConnectionInNewTab(_ connection: SSHConnection) {
        if connection.authMethod == .password {
            DispatchQueue.global(qos: .userInitiated).async {
                let _ = connection.password
                DispatchQueue.main.async {
                    self.createAndConnectTab(connection)
                }
            }
        } else {
            createAndConnectTab(connection)
        }
    }
    
    private func createAndConnectTab(_ connection: SSHConnection) {
        let session = SwiftTermSSHManager()
        let newTab = TerminalTab(connection: connection, session: session)
        openTabs.append(newTab)
        selectedTabId = newTab.id
        
        session.connect(to: connection)
        storage.updateLastUsed(connection)
    }
    
    private func closeTab(_ tab: TerminalTab) {
        tab.session.disconnect()
        
        if let index = openTabs.firstIndex(where: { $0.id == tab.id }) {
            openTabs.remove(at: index)
            
            if selectedTabId == tab.id {
                if index < openTabs.count {
                    selectedTabId = openTabs[index].id
                } else if !openTabs.isEmpty {
                    selectedTabId = openTabs.last?.id
                } else {
                    selectedTabId = nil
                }
            }
        }
    }
    
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

// MARK: - 终端标签页模型
class TerminalTab: Identifiable, ObservableObject {
    let id = UUID()
    let connection: SSHConnection
    let session: SwiftTermSSHManager
    
    var title: String {
        connection.name
    }
    
    init(connection: SSHConnection, session: SwiftTermSSHManager) {
        self.connection = connection
        self.session = session
    }
}

// MARK: - 标签按钮
struct TabButton: View {
    let tab: TerminalTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tab.session.isConnected ? Color.green :
                     (tab.session.isConnecting ? Color.yellow : Color.red))
                .frame(width: 8, height: 8)
            
            Text(tab.title)
                .font(.system(size: 13))
                .lineLimit(1)
            
            if isHovered || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - 标签筛选按钮
struct TagFilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 紧凑连接行视图
struct ConnectionRowCompact: View {
    let connection: SSHConnection
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "server.rack")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(connection.name)
                    .font(.headline)
                
                Text(connection.displayDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !connection.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(connection.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(3)
                        }
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    ConnectionListView()
        .frame(width: 1200, height: 800)
}

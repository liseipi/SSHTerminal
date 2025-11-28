#基于macOS自带的Terminal的连接工具，安全可靠

内嵌 SSH 终端
密码自动登录
连接保活（30秒）
Keychain 安全存储
无第三方依赖

项目目录结构
SSHTerminal/
├── SSHTerminal.xcodeproj
│   └── project.pbxproj
│
├── SSHTerminal/
│   ├── SSHTerminalApp.swift                 # 应用入口
│   │
│   ├── Models/
│   │   └── SSHConnection.swift              # SSH 连接数据模型
│   │
│   ├── ViewModels/
│   │   └── SSHSessionManager.swift          # SSH 会话管理器
│   │
│   ├── Services/
│   │   ├── TerminalLauncher.swift           # 系统终端启动服务
│   │   ├── ConnectionStorage.swift          # 连接存储服务
│   │   └── KeychainService.swift            # Keychain 密码存储
│   │
│   ├── Views/
│   │   ├── ConnectionListView.swift         # 主界面（三栏布局）
│   │   ├── AddConnectionSheet.swift         # 添加/编辑连接表单
│   │   └── EmbeddedTerminalView.swift       # 内嵌终端视图
│   │
│   ├── Utilities/
│   │   └── ANSITextStorage.swift            # ANSI 转义序列处理
│   │
│   ├── Resources/
│   │   └── Assets.xcassets/
│   │       ├── AppIcon.appiconset/
│   │       │   └── Contents.json
│   │       └── AccentColor.colorset/
│   │           └── Contents.json
│   │
│   ├── SSHTerminal.entitlements             # 应用权限配置
│   └── Info.plist                            # 应用配置
│
├── SSHTerminalTests/
│   └── SSHTerminalTests.swift
│
└── SSHTerminalUITests/
    └── SSHTerminalUITests.swift

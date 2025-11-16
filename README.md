项目结构：
```
SSHTerminal/
├── SSHTerminal.xcodeproj
│   ├── project.pbxproj
│   ├── project.xcworkspace/
│   │   ├── contents.xcworkspacedata
│   │   └── xcshareddata/
│   │       └── swiftpm/
│   │           └── Package.resolved
│   └── xcuserdata/
│       └── [username].xcuserdatad/
│           └── xcschemes/
│               └── SSHTerminal.xcscheme
│
├── SSHTerminal/
│   ├── SSHTerminalApp.swift          # App 入口
│   ├── Models/
│   │   ├── SSHConnection.swift       # SSH 连接模型
│   │   ├── TerminalLine.swift        # 终端行模型
│   │   └── FileItem.swift            # 文件项模型
│   │
│   ├── ViewModels/
│   │   └── SSHTerminalViewModel.swift # 主视图模型
│   │
│   ├── Views/
│   │   ├── SSHTerminalView.swift     # 主视图
│   │   ├── ConnectionList/
│   │   │   ├── ConnectionListView.swift
│   │   │   ├── ConnectionRow.swift
│   │   │   └── AddConnectionForm.swift
│   │   ├── Terminal/
│   │   │   ├── TerminalView.swift
│   │   │   └── TerminalOutputView.swift
│   │   └── FileBrowser/
│   │       ├── FileBrowserView.swift
│   │       └── FileItemRow.swift
│   │
│   ├── Services/
│   │   ├── SSHService.swift          # SSH 连接服务
│   │   ├── FileSystemService.swift   # 文件系统服务
│   │   └── CommandExecutor.swift     # 命令执行器
│   │
│   ├── Utilities/
│   │   ├── Extensions.swift          # 扩展
│   │   └── Constants.swift           # 常量
│   │
│   ├── Resources/
│   │   └── Assets.xcassets/
│   │       ├── AppIcon.appiconset/
│   │       │   └── Contents.json
│   │       └── AccentColor.colorset/
│   │           └── Contents.json
│   │
│   ├── SSHTerminal.entitlements      # App 权限配置
│   └── Info.plist                     # App 配置
│
├── SSHTerminalTests/
│   ├── SSHTerminalTests.swift
│   └── Info.plist
│
└── SSHTerminalUITests/
├── SSHTerminalUITests.swift
└── Info.plist
```

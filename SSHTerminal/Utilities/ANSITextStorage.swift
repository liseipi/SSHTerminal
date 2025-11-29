import AppKit

// MARK: - ANSI 文本存储（线程安全版）
class ANSITextStorage: NSTextStorage {
    private let storage = NSMutableAttributedString()
    private let baseFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let boldFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
    
    // ⭐️ 添加锁保护
    private let lock = NSRecursiveLock()
    
    // 当前渲染状态
    private var currentForeground = NSColor.white
    private var currentBackground = NSColor.black
    private var isBold = false
    private var isUnderline = false
    private var isReverse = false
    
    override var string: String {
        lock.lock()
        defer { lock.unlock() }
        return storage.string
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
        lock.lock()
        defer { lock.unlock() }
        
        guard location >= 0 && location < storage.length else {
            return [
                .font: baseFont,
                .foregroundColor: NSColor.white
            ]
        }
        
        return storage.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in range: NSRange, with str: String) {
        lock.lock()
        defer { lock.unlock() }
        
        beginEditing()
        storage.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }
    
    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
        lock.lock()
        defer { lock.unlock() }
        
        beginEditing()
        storage.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }
    
    // MARK: - 追加原始文本（保留 ANSI）
    func appendRawText(_ text: String) {
        // ⭐️ 如果文本太大，分批处理
        if text.count > 10000 {
            let chunks = text.chunked(into: 5000)
            for chunk in chunks {
                if Thread.isMainThread {
                    performAppend(chunk)
                } else {
                    DispatchQueue.main.sync { [weak self] in
                        self?.performAppend(chunk)
                    }
                }
            }
        } else {
            if Thread.isMainThread {
                performAppend(text)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.performAppend(text)
                }
            }
        }
    }
    
    private func performAppend(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let parsed = parseANSI(text)
        beginEditing()
        storage.append(parsed)
        let range = NSRange(location: storage.length - parsed.length, length: parsed.length)
        edited(.editedCharacters, range: range, changeInLength: parsed.length)
        endEditing()
    }
    
    // MARK: - 替换所有文本
    func replaceAllText(_ text: String) {
        // ⭐️ 如果已经在主线程，直接执行；否则异步到主线程
        if Thread.isMainThread {
            performReplace(text)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performReplace(text)
            }
        }
    }
    
    private func performReplace(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let parsed = parseANSI(text)
        beginEditing()
        let oldLength = storage.length
        storage.setAttributedString(parsed)
        edited(.editedCharacters, range: NSRange(location: 0, length: oldLength), changeInLength: parsed.length - oldLength)
        endEditing()
    }
    
    // MARK: - 解析 ANSI 转义序列
    private func parseANSI(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = text.startIndex
        var pendingText = ""
        
        // 重置状态
        currentForeground = NSColor.white
        currentBackground = NSColor.black
        isBold = false
        isUnderline = false
        isReverse = false
        
        while index < text.endIndex {
            let char = text[index]
            
            // 检测 ESC 序列
            if char == "\u{001B}" && text.index(after: index) < text.endIndex {
                // 先输出待处理的文本
                if !pendingText.isEmpty {
                    result.append(createAttributedString(pendingText))
                    pendingText = ""
                }
                
                // 解析 ANSI 序列
                if let (newIndex, _) = parseANSISequence(text, startIndex: index) {
                    index = newIndex
                    continue
                }
            }
            
            // 累积普通字符
            pendingText.append(char)
            index = text.index(after: index)
        }
        
        // 输出剩余文本
        if !pendingText.isEmpty {
            result.append(createAttributedString(pendingText))
        }
        
        return result
    }
    
    // MARK: - 解析单个 ANSI 序列
    private func parseANSISequence(_ text: String, startIndex: String.Index) -> (String.Index, Bool)? {
        guard text[startIndex] == "\u{001B}" else { return nil }
        
        var index = text.index(after: startIndex)
        guard index < text.endIndex else { return nil }
        
        let nextChar = text[index]
        
        // CSI 序列: ESC [
        if nextChar == "[" {
            index = text.index(after: index)
            var params: [Int] = []
            var currentParam = ""
            
            while index < text.endIndex {
                let char = text[index]
                
                if char.isNumber {
                    currentParam.append(char)
                } else if char == ";" {
                    if let param = Int(currentParam) {
                        params.append(param)
                    }
                    currentParam = ""
                } else if char.isLetter || char == "m" {
                    // 结束符
                    if !currentParam.isEmpty, let param = Int(currentParam) {
                        params.append(param)
                    }
                    
                    // 应用 SGR (Select Graphic Rendition)
                    if char == "m" {
                        applySGR(params.isEmpty ? [0] : params)
                    }
                    
                    return (text.index(after: index), true)
                } else {
                    // 未知字符，结束解析
                    return (text.index(after: index), false)
                }
                
                index = text.index(after: index)
            }
        }
        // OSC 序列: ESC ]
        else if nextChar == "]" {
            // 跳过 OSC 序列（通常用于设置标题等）
            index = text.index(after: index)
            while index < text.endIndex {
                let char = text[index]
                if char == "\u{0007}" || (char == "\u{001B}" && text.index(after: index) < text.endIndex && text[text.index(after: index)] == "\\") {
                    return (text.index(after: index), true)
                }
                index = text.index(after: index)
            }
        }
        
        return (index, false)
    }
    
    // MARK: - 应用 SGR 参数
    private func applySGR(_ params: [Int]) {
        var i = 0
        while i < params.count {
            let param = params[i]
            
            switch param {
            case 0: // Reset
                currentForeground = NSColor.white
                currentBackground = NSColor.black
                isBold = false
                isUnderline = false
                isReverse = false
                
            case 1: // Bold
                isBold = true
                
            case 4: // Underline
                isUnderline = true
                
            case 7: // Reverse
                isReverse = true
                
            case 22: // Normal intensity
                isBold = false
                
            case 24: // Not underlined
                isUnderline = false
                
            case 27: // Not reversed
                isReverse = false
                
            // Foreground colors (30-37)
            case 30: currentForeground = NSColor(red: 0, green: 0, blue: 0, alpha: 1)
            case 31: currentForeground = NSColor(red: 0.8, green: 0, blue: 0, alpha: 1)
            case 32: currentForeground = NSColor(red: 0, green: 0.8, blue: 0, alpha: 1)
            case 33: currentForeground = NSColor(red: 0.8, green: 0.8, blue: 0, alpha: 1)
            case 34: currentForeground = NSColor(red: 0, green: 0, blue: 0.8, alpha: 1)
            case 35: currentForeground = NSColor(red: 0.8, green: 0, blue: 0.8, alpha: 1)
            case 36: currentForeground = NSColor(red: 0, green: 0.8, blue: 0.8, alpha: 1)
            case 37: currentForeground = NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
            case 39: currentForeground = NSColor.white // Default
            
            // Background colors (40-47)
            case 40: currentBackground = NSColor(red: 0, green: 0, blue: 0, alpha: 1)
            case 41: currentBackground = NSColor(red: 0.8, green: 0, blue: 0, alpha: 1)
            case 42: currentBackground = NSColor(red: 0, green: 0.8, blue: 0, alpha: 1)
            case 43: currentBackground = NSColor(red: 0.8, green: 0.8, blue: 0, alpha: 1)
            case 44: currentBackground = NSColor(red: 0, green: 0, blue: 0.8, alpha: 1)
            case 45: currentBackground = NSColor(red: 0.8, green: 0, blue: 0.8, alpha: 1)
            case 46: currentBackground = NSColor(red: 0, green: 0.8, blue: 0.8, alpha: 1)
            case 47: currentBackground = NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)
            case 49: currentBackground = NSColor.black // Default
            
            // Bright foreground colors (90-97)
            case 90: currentForeground = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            case 91: currentForeground = NSColor(red: 1, green: 0, blue: 0, alpha: 1)
            case 92: currentForeground = NSColor(red: 0, green: 1, blue: 0, alpha: 1)
            case 93: currentForeground = NSColor(red: 1, green: 1, blue: 0, alpha: 1)
            case 94: currentForeground = NSColor(red: 0.4, green: 0.4, blue: 1, alpha: 1)
            case 95: currentForeground = NSColor(red: 1, green: 0, blue: 1, alpha: 1)
            case 96: currentForeground = NSColor(red: 0, green: 1, blue: 1, alpha: 1)
            case 97: currentForeground = NSColor(red: 1, green: 1, blue: 1, alpha: 1)
            
            // Bright background colors (100-107)
            case 100: currentBackground = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
            case 101: currentBackground = NSColor(red: 1, green: 0, blue: 0, alpha: 1)
            case 102: currentBackground = NSColor(red: 0, green: 1, blue: 0, alpha: 1)
            case 103: currentBackground = NSColor(red: 1, green: 1, blue: 0, alpha: 1)
            case 104: currentBackground = NSColor(red: 0.4, green: 0.4, blue: 1, alpha: 1)
            case 105: currentBackground = NSColor(red: 1, green: 0, blue: 1, alpha: 1)
            case 106: currentBackground = NSColor(red: 0, green: 1, blue: 1, alpha: 1)
            case 107: currentBackground = NSColor(red: 1, green: 1, blue: 1, alpha: 1)
            
            // 256 color mode: ESC[38;5;n or ESC[48;5;n
            case 38, 48:
                if i + 2 < params.count && params[i + 1] == 5 {
                    let colorIndex = params[i + 2]
                    let color = color256(colorIndex)
                    if param == 38 {
                        currentForeground = color
                    } else {
                        currentBackground = color
                    }
                    i += 2
                }
            
            default:
                break
            }
            
            i += 1
        }
    }
    
    // MARK: - 256 色调色板
    private func color256(_ index: Int) -> NSColor {
        // 基础 16 色
        if index < 16 {
            let colors: [NSColor] = [
                NSColor(red: 0, green: 0, blue: 0, alpha: 1),
                NSColor(red: 0.8, green: 0, blue: 0, alpha: 1),
                NSColor(red: 0, green: 0.8, blue: 0, alpha: 1),
                NSColor(red: 0.8, green: 0.8, blue: 0, alpha: 1),
                NSColor(red: 0, green: 0, blue: 0.8, alpha: 1),
                NSColor(red: 0.8, green: 0, blue: 0.8, alpha: 1),
                NSColor(red: 0, green: 0.8, blue: 0.8, alpha: 1),
                NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1),
                NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
                NSColor(red: 1, green: 0, blue: 0, alpha: 1),
                NSColor(red: 0, green: 1, blue: 0, alpha: 1),
                NSColor(red: 1, green: 1, blue: 0, alpha: 1),
                NSColor(red: 0.4, green: 0.4, blue: 1, alpha: 1),
                NSColor(red: 1, green: 0, blue: 1, alpha: 1),
                NSColor(red: 0, green: 1, blue: 1, alpha: 1),
                NSColor(red: 1, green: 1, blue: 1, alpha: 1)
            ]
            return colors[index]
        }
        
        // 216 色立方体 (16-231)
        if index >= 16 && index < 232 {
            let i = index - 16
            let r = CGFloat((i / 36) * 51) / 255.0
            let g = CGFloat(((i / 6) % 6) * 51) / 255.0
            let b = CGFloat((i % 6) * 51) / 255.0
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        }
        
        // 灰度 (232-255)
        if index >= 232 {
            let gray = CGFloat(8 + (index - 232) * 10) / 255.0
            return NSColor(red: gray, green: gray, blue: gray, alpha: 1)
        }
        
        return NSColor.white
    }
    
    // MARK: - 创建带属性的字符串
    private func createAttributedString(_ text: String) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: isBold ? boldFont : baseFont,
            .foregroundColor: isReverse ? currentBackground : currentForeground
        ]
        
        if isReverse && currentBackground != NSColor.black {
            attributes[.backgroundColor] = currentForeground
        } else if currentBackground != NSColor.black {
            attributes[.backgroundColor] = currentBackground
        }
        
        if isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        
        return NSAttributedString(string: text, attributes: attributes)
    }
}

// MARK: - ANSI 清理器（简化版，用于需要纯文本的场景）
class ANSICleaner {
    static func clean(_ text: String) -> String {
        var cleaned = text
        
        // 移除 CSI 序列 (ESC [ ... [letter])
        cleaned = cleaned.replacingOccurrences(
            of: "\u{001B}\\[[0-9;?]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        
        // 移除 OSC 序列 (ESC ] ... BEL 或 ESC \)
        cleaned = cleaned.replacingOccurrences(
            of: "\u{001B}\\].*?(\u{0007}|\u{001B}\\\\)",
            with: "",
            options: .regularExpression
        )
        
        // 移除其他 ESC 序列
        cleaned = cleaned.replacingOccurrences(
            of: "\u{001B}[^\\[\\]][^a-zA-Z]*[a-zA-Z]?",
            with: "",
            options: .regularExpression
        )
        
        return cleaned
    }
}

// MARK: - String 扩展
extension String {
    func chunked(into size: Int) -> [String] {
        var chunks: [String] = []
        var currentIndex = startIndex
        
        while currentIndex < endIndex {
            let endIndex = index(currentIndex, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[currentIndex..<endIndex]))
            currentIndex = endIndex
        }
        
        return chunks
    }
}

import AppKit

// MARK: - ANSI 文本存储和渲染
class ANSITextStorage: NSTextStorage {
    private let storage = NSMutableAttributedString()
    
    override var string: String {
        return storage.string
    }
    
    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
        return storage.attributes(at: location, effectiveRange: range)
    }
    
    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        storage.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: str.count - range.length)
        endEditing()
    }
    
    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
        beginEditing()
        storage.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }
    
    // 追加原始文本并解析 ANSI 序列
    func appendANSIText(_ text: String) {
        let parsed = parseANSI(text)
        beginEditing()
        storage.append(parsed)
        edited(.editedCharacters, range: NSRange(location: storage.length - parsed.length, length: parsed.length), changeInLength: parsed.length)
        endEditing()
    }
    
    // 解析 ANSI 转义序列
    private func parseANSI(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var currentIndex = text.startIndex
        
        // 当前文本属性
        var currentColor = NSColor.green
        var isBold = false
        
        let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
        
        while currentIndex < text.endIndex {
            // 查找下一个 ESC 字符
            if text[currentIndex] == "\u{001B}" {
                // 尝试解析 ANSI 序列
                if let (sequence, newIndex) = parseANSISequence(text, startIndex: currentIndex) {
                    // 应用序列效果
                    if let color = colorFromANSI(sequence) {
                        currentColor = color
                    }
                    if sequence.contains("1") {
                        isBold = true
                    }
                    if sequence.contains("0") {
                        // 重置
                        currentColor = NSColor.green
                        isBold = false
                    }
                    currentIndex = newIndex
                    continue
                }
            }
            
            // 普通字符
            let char = String(text[currentIndex])
            let attributes: [NSAttributedString.Key: Any] = [
                .font: isBold ? boldFont : baseFont,
                .foregroundColor: currentColor
            ]
            result.append(NSAttributedString(string: char, attributes: attributes))
            currentIndex = text.index(after: currentIndex)
        }
        
        return result
    }
    
    // 解析单个 ANSI 序列
    private func parseANSISequence(_ text: String, startIndex: String.Index) -> (String, String.Index)? {
        guard text[startIndex] == "\u{001B}" else { return nil }
        
        var index = text.index(after: startIndex)
        guard index < text.endIndex, text[index] == "[" else { return nil }
        
        index = text.index(after: index)
        var sequence = ""
        
        // 读取直到字母结束符
        while index < text.endIndex {
            let char = text[index]
            if char.isLetter || char == "m" {
                sequence.append(char)
                return (sequence, text.index(after: index))
            } else if char.isNumber || char == ";" {
                sequence.append(char)
            } else {
                break
            }
            index = text.index(after: index)
        }
        
        return nil
    }
    
    // 从 ANSI 代码获取颜色
    private func colorFromANSI(_ sequence: String) -> NSColor? {
        let codes = sequence.replacingOccurrences(of: "m", with: "")
            .split(separator: ";")
            .compactMap { Int($0) }
        
        for code in codes {
            switch code {
            case 30: return NSColor(red: 0, green: 0, blue: 0, alpha: 1)        // Black
            case 31: return NSColor(red: 0.8, green: 0, blue: 0, alpha: 1)      // Red
            case 32: return NSColor(red: 0, green: 0.8, blue: 0, alpha: 1)      // Green
            case 33: return NSColor(red: 0.8, green: 0.8, blue: 0, alpha: 1)    // Yellow
            case 34: return NSColor(red: 0, green: 0, blue: 0.8, alpha: 1)      // Blue
            case 35: return NSColor(red: 0.8, green: 0, blue: 0.8, alpha: 1)    // Magenta
            case 36: return NSColor(red: 0, green: 0.8, blue: 0.8, alpha: 1)    // Cyan
            case 37: return NSColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1)  // White
            case 90: return NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)  // Bright Black
            case 91: return NSColor(red: 1, green: 0, blue: 0, alpha: 1)        // Bright Red
            case 92: return NSColor(red: 0, green: 1, blue: 0, alpha: 1)        // Bright Green
            case 93: return NSColor(red: 1, green: 1, blue: 0, alpha: 1)        // Bright Yellow
            case 94: return NSColor(red: 0.4, green: 0.4, blue: 1, alpha: 1)    // Bright Blue
            case 95: return NSColor(red: 1, green: 0, blue: 1, alpha: 1)        // Bright Magenta
            case 96: return NSColor(red: 0, green: 1, blue: 1, alpha: 1)        // Bright Cyan
            case 97: return NSColor(red: 1, green: 1, blue: 1, alpha: 1)        // Bright White
            default: break
            }
        }
        
        return nil
    }
}

// MARK: - ANSI 文本清理器（简化版）
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
        
        // 处理回车和换行
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")
        
        // 移除 NULL 字符
        cleaned = cleaned.replacingOccurrences(of: "\0", with: "")
        
        return cleaned
    }
}

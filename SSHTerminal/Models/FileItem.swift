import Foundation

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let type: FileType
    let size: String?
    var children: [FileItem]?
    var isExpanded: Bool = false
    
    enum FileType {
        case directory, file
    }
}

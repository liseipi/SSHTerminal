import Foundation

class PTYHelper {
    static func createPTY() -> (master: FileHandle?, slave: FileHandle?) {
        var masterFD: Int32 = 0
        var slaveFD: Int32 = 0
        
        // 使用 openpty 创建伪终端
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            return (nil, nil)
        }
        
        let master = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        let slave = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        
        return (master, slave)
    }
    
    static func configureTerminal(_ fileHandle: FileHandle) {
        var term = termios()
        tcgetattr(fileHandle.fileDescriptor, &term)
        
        // 设置为原始模式
        term.c_lflag &= ~UInt(ICANON | ECHO | ECHOE | ISIG)
        term.c_iflag &= ~UInt(IXON | IXOFF)
        term.c_oflag &= ~UInt(OPOST)
        
        tcsetattr(fileHandle.fileDescriptor, TCSANOW, &term)
    }
}

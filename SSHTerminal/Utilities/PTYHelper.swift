import Foundation

class PTYHelper {
    static func createPTY() -> (master: FileHandle?, slave: FileHandle?) {
        var masterFD: Int32 = 0
        var slaveFD: Int32 = 0
        
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            return (nil, nil)
        }
        
        let master = FileHandle(fileDescriptor: masterFD, closeOnDealloc: true)
        let slave = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
        
        return (master, slave)
    }
}

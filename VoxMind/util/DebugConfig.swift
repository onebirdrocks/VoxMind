// MARK: - Debug Configuration
struct DebugConfig {
    static let isLocalDebug: Bool = {
#if DEBUG
        return true
#else
        return false
#endif
    }()
    
    static func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        if isLocalDebug {
            print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
        }
    }
}



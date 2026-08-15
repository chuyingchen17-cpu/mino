import OSLog

public enum MinoLog {
    public static let lifecycle = Logger(subsystem: "com.mino.app", category: "lifecycle")
    public static let backend = Logger(subsystem: "com.mino.app", category: "backend")
    public static let runtime = Logger(subsystem: "com.mino.app", category: "runtime")
}

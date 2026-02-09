import Foundation
import os.log

enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO" 
    case warning = "WARN"
    case error = "ERROR"
    
    var emoji: String {
        switch self {
        case .debug: return "[DEBUG]"
        case .info: return "[INFO]"
        case .warning: return "[WARN]"
        case .error: return "[ERROR]"
        }
    }
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}

class Logger {
    static let shared = Logger()
    
    private let subsystem = "com.oneclip.app"
    private let category = "main"
    private let osLogger: os.Logger
    
    // 控制日志级别
    private var currentLogLevel: LogLevel = .info
    private var enableConsoleOutput = true
    private var enableFileLogging = false
    
    private init() {
        osLogger = os.Logger(subsystem: subsystem, category: category)
        
        // 在 Debug 模式下启用更详细的日志
        #if DEBUG
        currentLogLevel = .debug
        enableConsoleOutput = true
        #else
        currentLogLevel = .info
        enableConsoleOutput = false
        #endif
    }
    
    // MARK: - Public Methods
    
    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.debug, message: message, file: file, function: function, line: line)
    }
    
    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.info, message: message, file: file, function: function, line: line)
    }
    
    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.warning, message: message, file: file, function: function, line: line)
    }
    
    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(.error, message: message, file: file, function: function, line: line)
    }
    
    // MARK: - Configuration
    
    func setLogLevel(_ level: LogLevel) {
        currentLogLevel = level
    }
    
    func setConsoleOutput(_ enabled: Bool) {
        enableConsoleOutput = enabled
    }
    
    func setFileLogging(_ enabled: Bool) {
        enableFileLogging = enabled
    }
    
    // MARK: - Private Methods
    
    private func log(_ level: LogLevel, message: String, file: String, function: String, line: Int) {
        // 检查是否应该记录此级别的日志
        guard shouldLog(level) else { return }
        
        let fileName = (file as NSString).lastPathComponent
        let timestamp = DateFormatter.logFormatter.string(from: Date())
        
        // 格式化消息
        let formattedMessage = "[\(timestamp)] [\(level.rawValue)] \(message)"
        let detailedMessage = "[\(timestamp)] [\(level.rawValue)] [\(fileName):\(line)] \(function) - \(message)"
        
        // 控制台输出
        if enableConsoleOutput {
            print("\(level.emoji) \(formattedMessage)")
        }
        
        // 系统日志
        osLogger.log(level: level.osLogType, "\(message, privacy: .public)")
        
        // 文件日志 (如果需要)
        if enableFileLogging {
            writeToFile(detailedMessage)
        }
    }
    
    private func shouldLog(_ level: LogLevel) -> Bool {
        let levels: [LogLevel] = [.debug, .info, .warning, .error]
        guard let currentIndex = levels.firstIndex(of: currentLogLevel),
              let messageIndex = levels.firstIndex(of: level) else {
            return false
        }
        return messageIndex >= currentIndex
    }
    
    private func writeToFile(_ message: String) {
        // 实现文件日志记录 (可选)
        guard let logURL = getLogFileURL() else { return }
        
        do {
            let data = (message + "\n").data(using: .utf8) ?? Data()
            
            if FileManager.default.fileExists(atPath: logURL.path) {
                let fileHandle = try FileHandle(forWritingTo: logURL)
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try data.write(to: logURL)
            }
        } catch {
            // 静默处理文件写入错误，避免无限递归
            osLogger.error("Failed to write log to file: \(error.localizedDescription)")
        }
    }
    
    private func getLogFileURL() -> URL? {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let logsDir = appSupportURL.appendingPathComponent("OneClip/Logs")
        
        // 创建日志目录
        try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: Date())
        
        return logsDir.appendingPathComponent("oneclip-\(todayString).log")
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let logFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}

// MARK: - Convenience Global Functions

func logDebug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.debug(message, file: file, function: function, line: line)
}

func logInfo(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.info(message, file: file, function: function, line: line)
}

func logWarning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.warning(message, file: file, function: function, line: line)
}

func logError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
    Logger.shared.error(message, file: file, function: function, line: line)
}
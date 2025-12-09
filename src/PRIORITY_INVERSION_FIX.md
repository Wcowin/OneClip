# OneClip 优先级倒置问题修复

## 问题分析

在ClipboardManager.swift第3398行附近发现了优先级倒置问题：

**根本原因：**
- User-initiated级别的Task在等待Background级别的队列操作
- DispatchQueue的QoS级别与Task优先级不匹配
- 信号量等待操作在低优先级队列中执行

## 已修复的问题

### 1. ImageLoadingQueueManager优先级倒置

**问题：**
```swift
// 原代码 - 有问题
Task(priority: .userInitiated) {
    await withCheckedContinuation { continuation in
        loadingQueue.async { // loadingQueue可能是较低优先级
            self.semaphore.wait()
            continuation.resume()
        }
    }
}
```

**修复：**
```swift
// 修复后 - 动态匹配QoS
Task(priority: priority) {
    let qosClass: DispatchQoS.QoSClass = {
        switch priority {
        case .userInteractive: return .userInteractive
        case .userInitiated: return .userInitiated
        default: return .utility
        }
    }()
    
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: qosClass).async {
            self.semaphore.wait()
            continuation.resume()
        }
    }
}
```

### 2. 队列QoS级别统一

**修复：**
- activeLoadsLock队列设置为`.userInitiated` QoS
- 所有异步操作使用匹配的QoS级别

## 需要进一步检查的潜在问题

### 1. optimizeImageDataAsync中的优先级问题

**位置：** 第2463行
```swift
Task.detached(priority: .userInitiated) { [weak self] in
    // 图片处理逻辑
}
```

**潜在问题：** 如果调用者是更高优先级，可能造成倒置

### 2. 预加载图片的优先级

**位置：** 第3286行
```swift
Task.detached(priority: .background) {
    let nsImage = NSImage(data: imageData)
    continuation.resume(returning: nsImage)
}
```

**建议：** 使用caller的优先级而不是固定background

## 建议的进一步优化

### 1. 创建优先级感知的图片处理器

```swift
private func optimizeImageDataAsync(_ data: Data, callerPriority: TaskPriority = .userInitiated) async throws -> Data {
    return try await withCheckedThrowingContinuation { continuation in
        Task.detached(priority: callerPriority) { [weak self] in
            // 图片处理逻辑...
        }
    }
}
```

### 2. 统一的QoS管理器

```swift
struct QoSManager {
    static func dispatchQoS(for taskPriority: TaskPriority) -> DispatchQoS.QoSClass {
        switch taskPriority {
        case .userInteractive: return .userInteractive
        case .userInitiated: return .userInitiated
        case .utility: return .utility
        case .background: return .background
        default: return .utility
        }
    }
}
```

### 3. Actor-based图片管理

考虑使用Actor来避免队列优先级问题：

```swift
actor ImageProcessor {
    func processImage(_ data: Data) async throws -> Data {
        // 处理逻辑，自动继承调用者优先级
    }
}
```

## 测试建议

1. **性能测试：** 使用Instruments的Time Profiler检查优先级倒置
2. **负载测试：** 同时进行多个不同优先级的图片加载
3. **响应性测试：** 确保UI操作不被后台任务阻塞

## 总结

已修复ImageLoadingQueueManager中的主要优先级倒置问题，但建议进一步检查其他异步操作的优先级设置，确保整个应用的优先级管理一致性。

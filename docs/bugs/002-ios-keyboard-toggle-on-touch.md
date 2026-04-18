# Bug 002: iOS 触摸终端屏幕触发键盘弹出/隐藏

## 现象

1. 点击终端屏幕会弹出键盘（即使用户不想输入）
2. 滑动滚动时会隐藏键盘
3. 长按选择文字时会触发键盘弹出

用户期望：键盘只能通过工具栏中的键盘按钮来切换显示/隐藏。

## 根因分析

### 1. handleTap 中调用 becomeFirstResponder（已修复）

`iOSMetalTerminalView.handleTap` 在每次点击时调用 `becomeFirstResponder()`，这会触发 UIKit 自动显示键盘（因为 `iOSMetalTerminalView` 实现了 `UITextInput` 协议）。

### 2. handlePan 中调用 resignFirstResponder（已修复）

`iOSMetalTerminalView.handlePan` 在滑动开始时调用 `resignFirstResponder()`，这会隐藏键盘。用户在查看历史输出时滑动，键盘会意外消失。

### 3. handleLongPress / handleDoubleTap 中调用 becomeFirstResponder（已修复）

选择文字的手势中也调用了 `becomeFirstResponder()`，导致长按或双击选择文字时键盘弹出。

## 修复方案

从所有手势处理器中移除 `becomeFirstResponder()` 和 `resignFirstResponder()` 调用：

- `handleTap`: 移除 `becomeFirstResponder()` — 点击只处理鼠标事件或清除选区
- `handlePan`: 移除 `resignFirstResponder()` — 滑动只处理滚动
- `handleDoubleTap`: 移除 `becomeFirstResponder()` — 双击只选择单词
- `handleLongPress`: 移除 `becomeFirstResponder()` — 长按只选择文本

键盘的显示/隐藏完全由工具栏按钮控制：

```
工具栏键盘按钮 → onKeyboardToggle 闭包
  ├─ 显示键盘: context.termInterface.activateKeyboard()
  │    → STerminalView.activateKeyboard()
  │    → SwiftTerminalView.makeTerminalFirstResponder()
  │    → metalView.becomeFirstResponder()
  │    → UIKit 自动显示键盘
  │
  └─ 隐藏键盘: context.termInterface.dismissKeyboard()
       → STerminalView.dismissKeyboard()
       → SwiftTerminalView.resignTerminalFirstResponder()
       → metalView.resignFirstResponder()
       → UIKit 自动隐藏键盘
```

键盘状态通过 `UIResponder.keyboardWillShowNotification` / `keyboardWillHideNotification` 追踪，
存储在 `@State private var isKeyboardVisible` 中。

## 修改文件

- `External/SwiftTerm/Sources/SwiftTerm/iOS/iOSMetalTerminalView.swift`
  - `handleTap`: 移除 `becomeFirstResponder()`
  - `handlePan`: 移除 `resignFirstResponder()`
  - `handleDoubleTap`: 移除 `becomeFirstResponder()`（之前已修复）
  - `handleLongPress`: 移除 `becomeFirstResponder()`（之前已修复）

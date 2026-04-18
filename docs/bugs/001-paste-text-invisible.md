# Bug 001: 粘贴后文字与背景色相同，无法看清

## 现象

在终端中粘贴文本后，回显的文字颜色与背景色一致，导致无法看清。macOS 和 iOS 均存在此问题。更换主题后问题依然存在。

## 根因

**`TerminalCellRenderer` 的 background pass 没有处理 `inverse` 样式。**

终端中带有 `inverse`（反显）样式的字符，前景色和背景色应该互换。glyph pass（文字渲染）正确地做了 `swap(&fgColor, &bgColor)`，但 background pass（背景渲染）完全忽略了 inverse 样式，仍然用原始的 `attribute.bg` 颜色画背景。

结果：
- background pass 画出浅灰色背景（原始 bg）
- glyph pass swap 后，文字前景色变成浅灰色（原始 bg），背景色变成蓝色（原始 fg）
- 但 glyph pass 的 bgColor 只用于 inverse 判断后的 swap，不影响已经画好的背景
- 最终：浅灰色文字画在浅灰色背景上 → 不可见

### 诊断日志确认

```
termFG=(14135,24672,49087)  termBG=(57825,58082,59367)
char='T' attrFg=defaultColor attrBg=defaultColor style=CharacterStyle(rawValue: 8)
  resolvedFG=(0.22, 0.38, 0.75)  resolvedBG=(0.88, 0.89, 0.91)
```

`rawValue: 8` = `.inverse` 样式。glyph pass 会 swap fg/bg，导致文字用 (0.88, 0.89, 0.91) 画在 (0.88, 0.89, 0.91) 背景上。

## 修复

在 `TerminalCellRenderer` 的两个 background pass（`buildFrame` 和 `buildRowVertices`）中，
检查 `inverse` 样式并使用 `attribute.fg` 作为背景色：

```swift
var bgColor = resolveColor(charData.attribute.bg, terminal: terminal, isFg: false, isBold: false)
if charData.attribute.style.contains(.inverse) {
    bgColor = resolveColor(charData.attribute.fg, terminal: terminal, isFg: true, isBold: charData.attribute.style.contains(.bold))
}
```

## 修改文件

- `External/SwiftTerm/Sources/SwiftTerm/Metal/TerminalCellRenderer.swift`
  - `buildFrame` 的 background pass：增加 inverse 处理
  - `buildRowVertices` 的 background pass：增加 inverse 处理

## 附加修复

- `TerminalRenderer.draw(in:)`: 修复 clearColor 设置时序（移到 encoder 创建之前）
- `SwiftTerminalView+UIKit/AppKit.feed(data:)`: 增加立即刷新调用
- 粘贴方法：增加多次延迟刷新

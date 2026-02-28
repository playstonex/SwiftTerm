# Lessons

## Swift 6 Concurrency

### Main Actor Isolation Warning Fix
When a `@MainActor` class has a `static let shared` property, accessing it from a non-isolated context causes warnings:

**Problem Pattern:**
```swift
@MainActor
public class AIAssistant {
    public static let shared = AIAssistant()
}

public class SkillAnalyzer {
    // ❌ Warning: default param is non-isolated
    public init(aiAssistant: AIAssistant = .shared) { ... }
}
```

**Solution:**
Use a designated initializer with the parameter, and a `@MainActor` convenience initializer:
```swift
@MainActor
public class SkillAnalyzer {
    // ✅ Designated init requires explicit parameter
    public init(aiAssistant: AIAssistant) {
        self.aiAssistant = aiAssistant
    }

    // ✅ Convenience init provides default on main actor
    public convenience init() {
        self.init(aiAssistant: .shared)
    }
}
```

**For non-`@MainActor` classes:**
```swift
public class RayonStore {
    // ❌ Stored property can't access @MainActor.shared
    private let skillRegistry = SkillRegistry.shared

    // ✅ Computed property with @MainActor
    @MainActor private var skillRegistry: SkillRegistry {
        .shared
    }
}
```

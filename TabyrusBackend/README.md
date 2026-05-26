# TabyrusBackend

A Swift package that provides native access to the Rust-based Otto autocomplete backend.

## Overview

TabyrusBackend wraps the Rust FFI functions from `tabyrus_backend` into a clean, type-safe Swift interface. It handles:

- **Library Loading**: Automatically finds and loads the compiled Rust dylib
- **FFI Bridge**: Safe conversion between Swift and C types
- **Memory Management**: Proper cleanup of C strings and resources
- **Error Handling**: Graceful fallbacks when the Rust library isn't available

## Usage

```swift
import TabyrusBackend

// Initialize the backend
let backend = TabyrusBackend()

// Get completion for text
if let result = backend.getCompletion(for: "the") {
    print("Prefix: \(result.prefix)")
    print("Suggestion: \(result.suggestion)")
    print("Confidence: \(result.confidence)")
    print("ML-based: \(result.isMLBased)")
}
```

## Architecture

### Rust Side (`src/lib.rs`)
- **FFI Functions**: `otto_initialize_completions()`, `otto_get_completion()`, `otto_free_completion_result()`
- **ML Integration**: Placeholder for MLX model loading and inference
- **Memory Safety**: All string handling uses proper Rust ownership

### Swift Side (`TabyrusBackend.swift`)
- **Library Loading**: Uses `dlopen()` to load the Rust dylib
- **Symbol Resolution**: `dlsym()` to find Rust functions
- **Type Safety**: Swift structs wrap unsafe C FFI calls
- **Resource Cleanup**: Automatic memory management

## Integration with SwiftUI

```swift
struct ContentView: View {
    @State private var backend: TabyrusBackend?

    var body: some View {
        // Your UI here
        TextField("Type here...", text: $text)
            .onChange(of: text) { newValue in
                if let result = backend?.getCompletion(for: newValue) {
                    suggestion = result.suggestion
                }
            }
    }

    // Initialize in onAppear
    .onAppear {
        backend = TabyrusBackend()
    }
}
```

## Building

### Rust Library
```bash
# Build the Rust backend
cargo build --release

# The library will be at: target/release/libtabyrus_backend.dylib
```

### Swift Package
```swift
// Add to Package.swift dependencies
.package(path: "./TabyrusBackend")

// Add to target dependencies
.executableTarget(
    name: "MyApp",
    dependencies: ["TabyrusBackend"]
)
```

## Future ML Integration

When MLX build issues are resolved, the Rust backend will automatically use ML inference:

```rust
// In src/lib.rs
fn get_ml_completion(text: &str) -> Option<CompletionResult> {
    // Load MLX model
    let model = mlx_rs::transformers::AutoModelForCausalLM::from_pretrained(
        "Jackrong/MLX-Qwen3.5-2B-Claude-4.6-Opus-Reasoning-Distilled-4bit"
    )?;
    
    // Tokenize and generate
    let tokens = tokenizer.encode(text, true)?;
    let outputs = model.generate(&tokens, max_new_tokens: 10)?;
    
    // Return Swift-compatible result
    Some(CompletionResult { ... })
}
```

The Swift package will automatically detect ML-based completions via the `isMLBased` flag.
# Tabyrus — System-wide AI Autocomplete for macOS

Tabyrus is a macOS daemon that provides AI-powered autocomplete, grammar checking, and code reshaping in any text field across all applications. All inference runs locally via Apple's MLX framework.

## Features

- **System-wide autocomplete** — Works in any text field via accessibility monitoring
- **Grammar checking** — AI-powered corrections and suggestions as you type
- **Code reshaping** — Transform, refactor, or restructure code with AI
- **Clipboard analysis** — Contextual completions based on recent clipboard content
- **Per-app customization** — AI instruction generation tailored to each application
- **Hardware-adaptive** — Automatically selects models based on available RAM
- **Status bar control** — Full menu bar interface with model download/switch
- **Local only** — All processing happens on-device; nothing leaves your machine

## Architecture

```
┌─────────────────────────────────────┐
│  Swift Frontend (macOS daemon)      │
│  • AX monitoring                    │
│  • Event taps                       │
│  • Suggestion overlay               │
│  • Menu bar UI                      │
├─────────────────────────────────────┤
│  Rust Backend (FFI via dlopen)      │
│  • MLX inference (mlx_lm.generate)  │
│  • Completions / Grammar / Reshape  │
│  • Clipboard analysis               │
│  • Hardware detection               │
│  • Model download (Hugging Face)    │
└─────────────────────────────────────┘
```

All ML logic lives in Rust. Swift is a thin layer handling macOS-native concerns: accessibility monitoring, event taps, suggestion overlays, and the menu bar.

## Requirements

- **macOS 14+** (Sonoma or later)
- **Apple Silicon** (MLX requires M-series chip)
- **8GB+ RAM** (16GB recommended for Gemma 4)
- **Accessibility permissions** (required for text monitoring)
- **MLX-LM CLI** (`mlx_lm.generate` on `PATH`)

## Quick Start

```bash
# Install brisk build tool (if not installed)
wax install brisk

# Build and run
brisk run
```

On first launch, Tabyrus will prompt you to download an AI model. Choose **Gemma 4** (recommended, ~3.6GB) or **Qwen 3.5** (lightweight, ~0.5GB).

## Models

| Model | Size | Description |
|-------|------|-------------|
| Gemma 4 | ~3.6 GB | Google's instruction-tuned model. Best quality. |
| Qwen 3.5 0.8B | ~0.5 GB | Fast, lightweight. Good for lower-end machines. |
| Zeta-2 | ~0.8 GB | Code editing specialist with next-edit-prediction. |

Models are downloaded from Hugging Face and cached at `~/Library/Caches/tabyrus/models/`.

## Manual Build

```bash
# Build Rust backend
cargo build --features mlx

# Build Swift app
swift build
# or: brisk build
```

## Backend Check

Tabyrus is valid from `~/projects/tabyrus`. The old `~/projects/otto` path can leave stale SwiftPM module cache entries behind; if Swift reports a module cache path containing `otto`, remove `.build/` and rebuild.

The Rust backend is `tabyrus-backend` in `src/lib.rs`. Build it with the default `mlx` feature, then run the Swift shell against the produced `libtabyrus_backend.dylib`:

```bash
cargo fmt --check
cargo check --all-targets --all-features
cargo test --all-targets --all-features
cargo build --features mlx
swift build
swift test
brisk build
```

Autocomplete, grammar checking, code reshaping, clipboard classification, and clipboard summarization all route through the Rust FFI boundary and invoke `mlx_lm.generate` against models cached under `~/Library/Caches/tabyrus/models/`. Without a downloaded model, autocomplete and autocorrect return no ML suggestion instead of falling back to cloud inference.

## Local Sibling Dependencies

- **SwiftUI surface**: use `../aurorality` for future SwiftUI/Aurorality rendering work. The current app shell remains AppKit-based for AX overlays and menu bar control.
- **EqSwift bridge**: `TabyrusBackend/Package.swift` resolves EqSwift from `../eqswift/swift` at the project level.

## Cotabby Benchmark Baseline

Cotabby is the comparison target at `~/projects/cotabby-fork`. Benchmark Tabyrus against Cotabby on the same machine by measuring:

- Build health: Tabyrus `cargo check`, `cargo test`, `swift build`, and `brisk build`; Cotabby `xcodebuild -project Cotabby.xcodeproj -scheme Cotabby -destination 'platform=macOS' build`.
- Suggestion cleanup: prompt echo stripping, chat marker stripping, repeated-tail stripping, newline clipping, and whitespace preservation.
- Acceptance behavior: Tabyrus inserts accepted autocomplete text at the caret through AX selected text first, then falls back to selected-range replacement. Cotabby keeps a fuller multi-step suggestion session with partial acceptance and live AX reconciliation.
- Inference latency: Tabyrus MLX subprocess time for `mlx_lm.generate`; Cotabby Apple Intelligence or llama.cpp engine time. Report model name, macOS version, CPU, memory, warmup count, sample count, and whether models were already loaded.

Latest local baseline, measured on macOS 26.5 (25F71), Apple M5 Pro, 48 GB RAM, 15 CPU threads:

| Check | Tabyrus | Cotabby |
|-------|---------|---------|
| App build | `brisk build`: 3.54s real | `xcodebuild ... build CODE_SIGNING_ALLOWED=NO`: 9.39s real |
| Focused autocomplete tests | `swift test`: 6 tests, 0 failures, 0.40s real | `xcodebuild ... test -only-testing:SuggestionTextNormalizerTests -only-testing:SuggestionSessionReconcilerTests`: 30 tests, 0 failures, 2.04s real |
| Backend tests | `cargo test --all-targets --all-features`: 9 tests, 0 failures | Not applicable; Cotabby runtime is Swift/C++ through `CotabbyInference` |
| Local model state | Tabyrus MLX model directories present; `mlx_lm.generate` missing on `PATH` | Cotabby test launch reported 0 GGUF models and Foundation model engine available |

The numbers above are build and deterministic suggestion-policy checks. They are not an inference-latency claim because the Tabyrus MLX CLI was not available on `PATH` during the run.

Practical desktop smoke test: launched `.build/debug/Tabyrus.app`, typed into TextEdit through macOS UI automation, and pressed Tab. TextEdit received the literal Tab and no ghost overlay appeared while `mlx_lm.generate` was unavailable on `PATH`.

## Project Structure

```
Cargo.toml                               # Rust backend crate manifest
src/
├── lib.rs                               # Rust MLX backend and C FFI exports
├── App/
│   ├── AppDelegate.swift              # Menu bar, status, downloads
│   ├── AutoCompleteApp.swift          # NSApplication entry point
│   ├── Coordinators/
│   │   ├── SettingsCoordinator.swift   # Settings sync
│   │   └── SuggestionCoordinator.swift # Completion pipeline
│   └── Core/
│       └── TabyrusEnvironment.swift    # Dependency container
├── Services/
│   ├── Focus/FocusTracker.swift       # Active app tracking
│   ├── Input/InputMonitor.swift       # Keyboard event monitoring
│   ├── Runtime/
│   │   ├── ModelManager.swift          # Download/status management
│   │   ├── TabyrusBackend.swift        # Rust FFI wrapper
│   │   └── TabyrusSuggestionEngine.swift # Suggestion generation
│   ├── ClipboardMonitor.swift         # Clipboard content capture
│   ├── ScreenshotMonitor.swift        # Screen capture
│   └── PermissionManager.swift        # Accessibility/input permissions
├── Support/
│   ├── AIService.swift                # AI service abstraction
│   ├── AppCustomizationManager.swift  # Per-app learning
│   ├── CodeReshapeService.swift       # Code transformation
│   ├── HardwareDetector.swift         # System capability detection
│   ├── SuggestionRequestFactory.swift  # Prompt construction
│   ├── SuggestionTextNormalizer.swift  # Output cleanup
│   └── TabyrusSettings.swift          # Settings + models
├── UI/
│   ├── CompletionOverlay.swift        # Ghost-text overlay
│   └── GrammarWidget.swift            # Grammar suggestion panel
TabyrusBackend/
├── Package.swift                       # Swift package wrapper for backend bridge
└── Sources/TabyrusBackend/
    └── TabyrusBackend.swift            # Reusable Rust FFI Swift wrapper
Tests/
└── TabyrusTests/                       # Swift policy tests for autocomplete cleanup
```

## Permissions

Tabyrus requires **Accessibility** permissions to monitor text input across applications. On first run, it will prompt you to enable this in System Settings.

Optional: **Screen Recording** permission for screenshot-based context (disabled by default).

## How It Works

1. **Focus tracking** — Detects the active application and text field
2. **Input monitoring** — Captures keystrokes via accessibility API
3. **Context gathering** — Collects clipboard content, app context
4. **AI inference** — Sends prompt to MLX model subprocess
5. **Suggestion display** — Shows ghost-text overlay with Tab-to-accept

## Privacy

- All inference runs locally on your device
- No data is sent to external servers
- Clipboard and screenshot monitoring are individually toggleable
- Model downloads happen directly from Hugging Face (no proxy)

## Contributing

The codebase is designed to be modular:

- Add new models in `TabyrusSettings.swift` and `lib.rs` (CompletionModel enum)
- Extend AI capabilities in Rust backend (completion, grammar, code reshape)
- Add new monitoring sources in `Services/`
- Improve UI in `src/UI/`

## License

MPL-2.0 — See [LICENSE](LICENSE)

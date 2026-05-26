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

## Quick Start

```bash
# Install brisk build tool (if not installed)
brew install brisk

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
cargo build

# Build Swift app
swift build
# or: brisk build
```

## Project Structure

```
src/
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
└── lib.rs                             # Rust backend (~700 lines)
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

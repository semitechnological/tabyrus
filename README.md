# Otto - Advanced System-wide AI Autocomplete

A sophisticated macOS daemon that provides system-wide AI-powered autocomplete with multimodal capabilities, per-app customization, and hardware-adaptive model selection.

## Features

- **System-wide monitoring**: Works in any text input field across all macOS applications
- **Multimodal AI**: Combines text, clipboard, and visual context for intelligent suggestions
- **Clipboard monitoring**: Captures and analyzes clipboard contents for contextual completions
- **Screenshot capture**: Periodically captures screen content for visual AI processing
- **Per-app customization**: AI-generated instructions tailored to each application's behavior
- **Hardware adaptation**: Automatically selects appropriate models based on RAM/CPU capabilities
- **Apple Intelligence integration**: Uses Apple's local FoundationModels when available
- **Background daemon**: Runs invisibly with comprehensive status bar controls
- **Tab acceptance**: Accept completions with Tab key
- **Privacy-conscious**: All processing happens locally on-device

## Architecture

- **Swift frontend**: macOS daemon with accessibility monitoring, clipboard tracking, and screenshot capture
- **Rust backend**: FFI interface supporting multiple AI backends (Apple Intelligence, Qwen, etc.)
- **Hardware detector**: Adaptive model selection based on system capabilities
- **App customization manager**: Per-application AI instruction generation and storage
- **Combined AI service**: Intelligent fallback between different AI providers

## Core Components

### Monitoring Systems
- **AccessibilityMonitor**: System-wide text input and keyboard event monitoring
- **ClipboardMonitor**: Periodic clipboard content capture and analysis
- **ScreenshotMonitor**: Screen capture for visual context (privacy-controlled)

### AI & Customization
- **AIService**: Unified interface for multiple AI backends
- **AppleAIService**: Integration with Apple's FoundationModels (when available)
- **DictionaryAIService**: Fast dictionary-based completions as fallback
- **AppCustomizationManager**: Per-app AI instruction generation and storage
- **HardwareDetector**: System capability detection for model selection

### Data Management
- **Persistent storage**: UserDefaults-based storage for app customizations
- **Pattern analysis**: Learning from clipboard and interaction patterns
- **Context generation**: Creating rich prompts from multimodal data

## Requirements

- **macOS**: 13.0+ (14.0+ recommended for full screenshot capabilities)
- **Hardware**: Apple Silicon preferred for Apple Intelligence
- **Permissions**: Accessibility permissions required for text monitoring
- **Memory**: 8GB+ RAM recommended for larger models

## Building

```bash
# Add Rust dependencies
cargo add rusty_foundationmodels

# Build Swift package
swift build
```

## Running

```bash
./.build/debug/otto
```

## Permissions Setup

1. **Accessibility**: Required for system-wide text monitoring
   - Run Otto once, it will open System Preferences
   - Enable Otto in Security & Privacy > Accessibility

2. **Screen Recording**: Optional, for screenshot features
   - Enable in Security & Privacy > Screen Recording

## Usage

### Status Bar Menu
- **Otto** (main icon): Access all controls
- **Monitoring: On/Off**: Toggle accessibility monitoring
- **Clipboard: On/Off**: Control clipboard monitoring
- **Screenshots: Off/On**: Toggle screenshot capture (default off for privacy)
- **Clear Data**: Remove all stored customizations and history
- **About Otto**: Show application information
- **Quit**: Exit the daemon

### AI Model Selection
Otto automatically selects the best available AI backend:

1. **Apple Intelligence** (if available on Apple Silicon with sufficient RAM)
2. **Qwen models** (if integrated)
3. **Dictionary fallback** (always available)

### Per-App Customization
Otto learns from each application's usage patterns:

- **Clipboard analysis**: Identifies common content types
- **Interaction patterns**: Learns typical workflows
- **AI instruction generation**: Creates customized prompts for better completions
- **Contextual suggestions**: Tailors completions to app-specific behaviors

## Technical Implementation

### Multimodal Processing
- **Text input**: Primary completion source
- **Clipboard context**: Recent copied content for suggestions
- **Visual context**: Screenshot analysis for UI-aware completions
- **App-specific rules**: Learned behavior patterns

### Hardware Adaptation
- **RAM detection**: Models selected based on available memory
- **CPU capabilities**: Performance optimization for different processors
- **Apple Silicon detection**: Enables Apple Intelligence features

### Privacy & Security
- **Local processing**: All AI inference happens on-device
- **No data transmission**: Nothing leaves the user's device
- **User control**: Individual toggles for each monitoring feature
- **Data retention**: Configurable history limits and clear options

## Model Capabilities

### Apple Intelligence (Primary)
- **≈3B parameters**: Large local model
- **Multi-turn conversations**: Context-aware completions
- **Structured generation**: Schema-based responses
- **Tool calling**: Function execution capabilities

### Qwen Models (Alternative)
- **800M parameters**: Chinese-optimized model
- **Fast inference**: Optimized for real-time use
- **Dictionary integration**: Pattern-based completions

### Dictionary Fallback
- **Instant response**: No AI inference delay
- **Pattern matching**: Learned from usage data
- **Always available**: Works without AI dependencies

## Development

### Project Structure
```
src/
├── AccessibilityMonitor.swift    # System-wide text monitoring
├── ClipboardMonitor.swift        # Clipboard content capture
├── ScreenshotMonitor.swift       # Screen capture system
├── AIService.swift               # AI backend abstraction
├── AppCustomizationManager.swift # Per-app customization
├── HardwareDetector.swift        # System capability detection
├── CompletionWindow.swift        # Suggestion UI overlay
└── AppDelegate.swift            # Main application logic
```

### Adding New AI Backends
1. Implement the `AIService` protocol
2. Add to `CombinedAIService` for automatic fallback
3. Update hardware detection for capability requirements

### Extending Monitoring
- Add new data sources to monitoring systems
- Update `AppCustomizationManager` for new pattern types
- Modify AI prompts to utilize additional context

## Future Enhancements

- **Full multimodal models**: Vision-language models for UI understanding
- **Advanced screenshot analysis**: OCR and UI element recognition
- **Cross-app context**: Learning from interactions across applications
- **Custom model training**: Personalization based on user behavior
- **Cloud synchronization**: Optional cross-device customization sync

## Limitations

- **Accessibility permissions**: Required for core functionality
- **Screenshot API**: Limited on older macOS versions
- **Apple Intelligence**: Requires compatible hardware and OS version
- **Modal completions**: Current UI shows floating suggestions (not inline)
- **Memory usage**: Larger models require significant RAM

## Contributing

The system is designed to be modular and extensible:

1. **Add monitoring sources**: Implement new data collection systems
2. **Extend AI backends**: Integrate additional local AI models
3. **Improve customization**: Enhance per-app learning algorithms
4. **Optimize performance**: Add caching and performance improvements

## License

See individual component licenses (Swift code, Rust dependencies).
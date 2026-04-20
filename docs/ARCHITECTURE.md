# VoiceInk Architecture & Logic Documentation

## Overview

**VoiceInk** is a native macOS voice-to-text application that transcribes speech almost instantly. It uses AI models (local and cloud-based) to convert audio to text with high accuracy, while keeping all data private through offline processing.

---

## Table of Contents

1. [Core Architecture](#core-architecture)
2. [Recording Flow](#recording-flow)
3. [Transcription Pipeline](#transcription-pipeline)
4. [AI Enhancement System](#ai-enhancement-system)
5. [Model Providers](#model-providers)
6. [Language Configuration](#language-configuration)
7. [Power Mode System](#power-mode-system)
8. [Hotkey System](#hotkey-system)
9. [Common Issues & Solutions](#common-issues--solutions)

---

## Core Architecture

### Main Entry Point

**File:** `VoiceInk.swift`

The app is built with SwiftUI and uses the `@main` attribute. Key components initialized at startup:

```
VoiceInkApp
├── WhisperState          # Central state management for recording/transcription
├── AIService             # Handles AI provider connections (OpenAI, Anthropic, etc.)
├── AIEnhancementService  # Post-transcription AI enhancement
├── HotkeyManager         # Global keyboard shortcut handling
├── MenuBarManager        # Menu bar icon and controls
├── ModelPrewarmService   # Optimizes model loading
└── ModelContainer        # SwiftData storage for transcriptions
```

### State Machine

**File:** `Whisper/WhisperState.swift`

The app uses a simple state machine for recording:

```swift
enum RecordingState {
    case idle         // Ready to record
    case recording    // Currently recording audio
    case transcribing // Converting audio to text
    case enhancing    // AI is enhancing the text
    case busy         // Processing
}
```

---

## Recording Flow

### 1. User Triggers Recording

**Files:** `HotkeyManager.swift`, `WhisperState.swift`

Recording can be triggered by:
- **Hotkey press** (configurable: Right Option, Right Command, etc.)
- **Custom keyboard shortcut**
- **Middle mouse click**
- **UI button click**

### 2. Audio Capture

**Files:** `Recorder.swift`, `AudioEngineRecorder.swift`

```
User Press Hotkey
        ↓
HotkeyManager → toggleMiniRecorder notification
        ↓
WhisperState.toggleRecord()
        ↓
Recorder.startRecording(toOutputFile: URL)
        ↓
AudioEngineRecorder (using AVAudioEngine)
        ↓
Audio saved as .wav file in ~/Library/Application Support/com.prakashjoshipax.VoiceInk/Recordings/
```

**Key Logic in `AudioEngineRecorder.swift`:**
- Creates `AVAudioEngine` instance
- Installs tap on input node to capture audio buffers
- Converts audio format to 16kHz mono (required by Whisper)
- Writes audio data to file in real-time
- Monitors audio levels for "No Audio Detected" warnings

### 3. Recording Stop & Transcription

When user releases the hotkey or presses again:

```
stopRecording()
        ↓
Create Transcription object (SwiftData)
        ↓
transcribeAudio(on: transcription)
```

---

## Transcription Pipeline

### Service Registry

**File:** `Services/TranscriptionServiceRegistry.swift`

The registry routes transcription requests to the appropriate service based on the model provider:

```swift
func service(for provider: ModelProvider) -> TranscriptionService {
    switch provider {
    case .local:       return localTranscriptionService
    case .parakeet:    return parakeetTranscriptionService
    case .nativeApple: return nativeAppleTranscriptionService
    default:           return cloudTranscriptionService  // Groq, Deepgram, etc.
    }
}
```

### Local Transcription (Whisper)

**Files:** `Services/LocalTranscriptionService.swift`, `Whisper/LibWhisper.swift`

```
Audio File (.wav)
        ↓
Read audio samples (16-bit PCM → Float array)
        ↓
Load Whisper model (if not loaded)
        ↓
Set language parameter from UserDefaults["SelectedLanguage"]
        ↓
whisper_full() - Core transcription
        ↓
Get transcription segments
        ↓
Return text
```

**Important Language Logic in `LibWhisper.swift`:**

```swift
let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
if selectedLanguage != "auto" {
    languageCString = Array(selectedLanguage.utf8CString)
    params.language = languageCString?.withUnsafeBufferPointer { $0.baseAddress }
} else {
    params.language = nil  // Auto-detect
}
```

### Post-Processing Pipeline

**File:** `WhisperState.swift` (lines 245-414)

```
Raw Transcription Text
        ↓
TranscriptionOutputFilter.filter()  # Remove unwanted output
        ↓
Trim whitespace
        ↓
WhisperTextFormatter.format()  # Text formatting (if enabled)
        ↓
WordReplacementService.applyReplacements()  # Custom word replacements
        ↓
[Optional] AI Enhancement
        ↓
CursorPaster.pasteAtCursor()  # Paste to active app
```

---

## AI Enhancement System

**File:** `Services/AIEnhancement/AIEnhancementService.swift`

AI Enhancement is an **optional** post-processing step that uses LLMs to improve transcription.

### Flow

```
Raw Transcription
        ↓
Check if enhancement is enabled (isEnhancementEnabled)
        ↓
Check if API is configured (isConfigured)
        ↓
Get active prompt (custom or predefined)
        ↓
Build system message with context:
  - Screen context (if screen capture enabled)
  - Clipboard context
  - Selected text context
  - Custom vocabulary
        ↓
Send to AI provider (Anthropic, OpenAI, Google, Ollama)
        ↓
Enhanced Text
```

### Supported AI Providers

- **Anthropic (Claude)**
- **OpenAI (GPT-4, etc.)**
- **Google (Gemini)**
- **Ollama (Local LLMs)**

---

## Model Providers

**File:** `Models/TranscriptionModel.swift`, `Models/PredefinedModels.swift`

### Provider Types

```swift
enum ModelProvider {
    case local        // Whisper models (ggml-tiny, ggml-base, ggml-large, etc.)
    case parakeet     // NVIDIA Parakeet models
    case groq         // Groq cloud transcription
    case elevenLabs   // ElevenLabs Scribe
    case deepgram     // Deepgram Nova
    case mistral      // Mistral Voxtral
    case gemini       // Google Gemini
    case soniox       // Soniox
    case custom       // User-defined OpenAI-compatible endpoints
    case nativeApple  // Apple Speech framework (macOS 26+)
}
```

### Model Selection Logic

The current model is stored in `UserDefaults` and loaded by `WhisperState.loadCurrentTranscriptionModel()`.

---

## Language Configuration - Code Flow

### 1. Language Storage & Retrieval

**Storage Location:** `UserDefaults["SelectedLanguage"]`

```swift
// Default value varies by component:
// - UI components: "en" (English)
// - Whisper engine: "auto" (auto-detect)
```

### 2. UI Layer - Language Selection

**File:** `Views/AI Models/LanguageSelectionView.swift`

**Key Components:**

```swift
struct LanguageSelectionView: View {
    @AppStorage("SelectedLanguage") private var selectedLanguage: String = "en"
    
    // Line 16-26: UpdateLanguage function
    private func updateLanguage(_ language: String) {
        selectedLanguage = language  // @AppStorage saves to UserDefaults automatically
        whisperPrompt.updateTranscriptionPrompt()  // Refresh prompts
        
        // Notify other components
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }
    
    // Line 96-110: Language picker
    Picker("Select Language", selection: $selectedLanguage) {
        ForEach(currentModel.supportedLanguages...) { key, value in
            Text(value).tag(key)
        }
    }
    .onChange(of: selectedLanguage) { oldValue, newValue in
        updateLanguage(newValue)
    }
}
```

**Logic Flow:**
1. User selects language from dropdown → `onChange` triggers
2. `updateLanguage()` called → `@AppStorage` saves to UserDefaults
3. Notification posted → Other components react

**Model-Specific Handling (Lines 79-143):**
- **Parakeet/Gemini models:** Auto-detect only (disabled selection)
- **Multilingual models:** Show full language picker
- **English-only models:** Force `"en"`, disable picker

---

### 3. Transcription Layer - Language Application

**File:** `Whisper/LibWhisper.swift`

**Core Logic (Lines 31-47):**

```swift
func fullTranscribe(samples: [Float]) -> Bool {
    guard let context = context else { return false }
    
    var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
    
    // Line 38: Read language from UserDefaults
    let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
    
    // Line 39-47: Apply language to Whisper parameters
    if selectedLanguage != "auto" {
        // Convert Swift String to C string
        languageCString = Array(selectedLanguage.utf8CString)
        
        // Set language pointer for Whisper C library
        params.language = languageCString?.withUnsafeBufferPointer { ptr in
            ptr.baseAddress
        }
    } else {
        // Auto-detect: Pass nil to Whisper
        languageCString = nil
        params.language = nil
    }
    
    // Line 92: Execute transcription with language param
    samples.withUnsafeBufferPointer { samplesBuffer in
        whisper_full(context, params, samplesBuffer.baseAddress, Int32(samplesBuffer.count))
    }
}
```

**How it works:**
1. **Read:** Fetch language code from UserDefaults
2. **Convert:** Transform to C-compatible string (Whisper is C++)
3. **Apply:** Set `params.language` pointer
4. **Execute:** Pass params to `whisper_full()` C function

**Why Vietnamese might become English:**
- If `selectedLanguage = "en"` → Whisper interprets audio as English
- If `selectedLanguage = "auto"` → Whisper's ML model guesses (can fail)
- Short audio + auto-detect = higher error rate

---

### 4. Cloud Transcription Services

**Files:** `Services/CloudTranscription/*.swift`

Each cloud provider reads the same UserDefaults key:

**Example - Groq (Line 123):**
```swift
let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"
```

**Example - Deepgram (Line 54):**
```swift
let selectedLanguage = UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "auto"

// Build API request
var urlComponents = URLComponents(string: "\(apiEndpoint)/listen")
urlComponents?.queryItems = [
    URLQueryItem(name: "language", value: selectedLanguage),
    URLQueryItem(name: "model", value: modelName)
]
```

**How it works:**
- Read from same UserDefaults key
- Append as API query parameter
- Cloud service handles language-specific processing

---

### 5. Power Mode Integration

**File:** `PowerMode/PowerModeSessionManager.swift`

**Language Override Logic (Lines 122-123):**

```swift
func applyConfiguration(_ config: PowerModeConfig) {
    if let language = config.selectedLanguage {
        // Override global language with Power Mode setting
        UserDefaults.standard.set(language, forKey: "SelectedLanguage")
    }
}
```

**How it works:**
1. Power Mode activates (app/URL match)
2. `applyConfiguration()` called
3. Overwrites `UserDefaults["SelectedLanguage"]`
4. Next transcription uses new language

**Restoration (Lines 157):**
```swift
func restoreSettings() {
    if let originalLanguage = originalSettings.selectedLanguage {
        UserDefaults.standard.set(language, forKey: "SelectedLanguage")
    }
}
```

---

### 6. Available Languages

**File:** `Models/PredefinedModels.swift` (Lines 311-413)

```swift
static let allLanguages = [
    "auto": "Auto-detect",
    "vi": "Vietnamese",      // ← Vietnamese support
    "en": "English",
    "zh": "Chinese",
    "ja": "Japanese",
    // ... 100+ languages
]
```

**Model-Specific Languages:**

```swift
static func getLanguageDictionary(isMultilingual: Bool, provider: ModelProvider) -> [String: String] {
    if !isMultilingual {
        return ["en": "English"]  // English-only models
    } else {
        if provider == .nativeApple {
            // Filter to Apple-supported languages
            let appleSupportedCodes = ["ar", "de", "en", "es", "fr", "it", "ja", "ko", "pt", "yue", "zh"]
            return allLanguages.filter { appleSupportedCodes.contains($0.key) }
        }
        return allLanguages  // All languages for Whisper multilingual
    }
}
```

---

### 7. Data Flow Diagram

```
┌──────────────────────────────────────────┐
│  LanguageSelectionView.swift             │
│  @AppStorage("SelectedLanguage")         │
│                                          │
│  User Action: Select "vi" from dropdown  │
└────────────────┬─────────────────────────┘
                 │
                 │ @AppStorage automatic save
                 ↓
┌──────────────────────────────────────────┐
│  UserDefaults.standard                   │
│  ["SelectedLanguage"] = "vi"             │
└────┬─────────────────────────────────┬───┘
     │                                 │
     │ PowerMode Override              │ Direct Read
     ↓                                 ↓
┌──────────────────┐         ┌──────────────────────┐
│ PowerMode        │         │ LibWhisper.swift     │
│ SessionManager   │         │ Line 38: Read        │
│ Line 122         │         │ Line 40: Convert     │
│                  │         │ Line 92: Execute     │
└──────────────────┘         └──────────────────────┘
                                      │
                                      ↓
                            ┌──────────────────────┐
                            │ whisper_full(params) │
                            │ [C++ Library]        │
                            │ params.language="vi" │
                            └──────────────────────┘
```

---

## Power Mode System

**Files:** `PowerMode/PowerModeConfig.swift`, `PowerMode/PowerModeSessionManager.swift`

Power Mode allows automatic configuration changes based on the active application or URL.

### Configuration Options

Each Power Mode config includes:
- **App matching** (bundle identifier)
- **URL matching** (for browsers)
- **Language selection**
- **Transcription model**
- **AI Enhancement toggle**
- **Prompt selection**
- **Auto-send toggle**

### Activation Logic

```
User starts recording
        ↓
ActiveWindowService.applyConfigurationForCurrentApp()
        ↓
Check current app bundle ID
        ↓
Match against PowerModeConfig.appConfigs
        ↓
Apply matching configuration (language, model, AI settings)
```

---

## Hotkey System

**File:** `HotkeyManager.swift`

### Available Hotkey Types

```swift
enum HotkeyOption {
    case none
    case rightOption / leftOption
    case leftControl / rightControl
    case rightCommand / leftCommand
    case rightShift / leftShift
    case custom  // User-defined shortcut
}
```

### Recording Modes

1. **Toggle Mode** (default): Press once to start, press again to stop
2. **Hands-Free Mode**: Hold key for 2+ seconds, release to stop
3. **Push-to-Talk**: Hold key to record, release to stop

### Detection Logic

- Uses `NSEvent.addGlobalMonitorForEvents` to detect hotkey presses
- Tracks key press duration to distinguish between toggle and hands-free modes
- Middle-click support via separate monitor

---

## Common Issues & Solutions

### Issue: Wrong Language Detection

**Symptoms:** 
- Vietnamese speech transcribed as English
- Mixed languages in output

**Solutions:**
1. Set explicit language in settings (`vi` for Vietnamese)
2. Use multilingual models (not `.en` models)
3. Check Power Mode settings if using app-specific configs

### Issue: No Audio Detected

**Symptoms:**
- Warning notification appears
- Empty transcription

**Solutions:**
1. Check microphone permissions
2. Verify correct input device is selected in AudioDeviceManager
3. Check system audio input settings

### Issue: Slow Transcription

**Solutions:**
1. Use smaller models (`ggml-base` instead of `ggml-large-v3`)
2. Use Parakeet models for English-only content
3. Consider cloud providers (Groq, Deepgram) for faster processing

---

## File Structure Summary

```
VoiceInk/
├── VoiceInk.swift                    # Main app entry point
├── Whisper/
│   ├── WhisperState.swift            # Central state management
│   ├── LibWhisper.swift              # Whisper C++ interface
│   └── WhisperState+*.swift          # State extensions
├── Services/
│   ├── TranscriptionServiceRegistry.swift
│   ├── LocalTranscriptionService.swift
│   ├── CloudTranscription/           # Cloud provider implementations
│   └── AIEnhancement/                # AI enhancement services
├── Models/
│   ├── TranscriptionModel.swift      # Model protocols
│   └── PredefinedModels.swift        # Built-in models & languages
├── PowerMode/
│   ├── PowerModeConfig.swift         # Configuration structure
│   └── PowerModeSessionManager.swift # Session management
├── Recorder.swift                    # High-level recording interface
├── AudioEngineRecorder.swift         # Low-level audio capture
└── HotkeyManager.swift               # Keyboard shortcut handling
```

---

## Summary

VoiceInk follows a clean pipeline architecture:

```
Hotkey Press → Audio Recording → Transcription Service → Post-Processing → AI Enhancement → Paste to App
```

The Vietnamese-to-English issue is a **configuration problem**, not a bug. Set the language explicitly to `"vi"` in settings to ensure proper Vietnamese transcription.

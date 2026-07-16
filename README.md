# Voxtral — Audio Transcription & Speaker Diarization for macOS

A fast, native macOS app that turns any audio file into a searchable, speaker-labeled transcript — powered by [Mistral AI's Voxtral](https://docs.mistral.ai/studio-api/audio/speech_to_text/offline_transcription) speech-to-text API, with synchronized audio playback.

Built with SwiftUI, SwiftData and AVFoundation. Zero third-party dependencies. Your audio never goes anywhere except directly to the Mistral API.

## Features

- **Transcription + diarization** — who said what, with per-segment timestamps
- **Synced playback** — the current segment is highlighted and auto-scrolled while the audio plays; click any segment to jump the audio there
- **History** — every transcription is saved locally (SwiftData) and searchable by name or content
- **Speaker renaming** — click a speaker label to give it a real name, applied everywhere
- **Inline editing** — double-click any segment to fix the transcript text
- **Find in transcript** (⌘F) with match navigation and audio seek
- **Export** — copy to clipboard, or save as `.txt` / Markdown (with timestamps and speaker names)
- **Resilient** — retry failed jobs, relink moved audio files, playback speeds 1× / 1.5× / 2×

## The model: Voxtral Mini Transcribe 2

The app uses [`voxtral-mini-2602`](https://docs.mistral.ai/models/model-cards/voxtral-mini-transcribe-26-02) (Voxtral Mini Transcribe 2), Mistral's dedicated speech-to-text model:

- **State-of-the-art multilingual transcription** with automatic language detection
- **Native speaker diarization** (`diarize=true`) and segment-level timestamps
- **Long audio**: up to **≈3 hours** per file in a single API call — no chunking needed
- **Price**: **$0.003 per minute** of audio (a 1-hour meeting costs ~$0.18)

## Getting an API key

1. Create an account at [console.mistral.ai](https://console.mistral.ai)
2. Add a billing method (Billing → Payments), or activate the free tier if available
3. Go to **API Keys** → **Create new key** and copy it
4. In Voxtral: **⌘,** (Settings) → paste the key → *Enregistrer*. It is stored in the macOS Keychain, never on disk or in the repo.

## Build & install

Requires macOS 15+ and the Swift toolchain (Xcode or Command Line Tools).

```bash
swift test           # run the unit tests
./scripts/bundle.sh  # release build → build/Voxtral.app
ditto build/Voxtral.app /Applications/Voxtral.app
```

## Usage

1. Drag an audio file (mp3, m4a, wav, flac…) into the window — or click *Ouvrir*
2. Wait a few seconds for transcription + diarization
3. Play, search, rename speakers, edit, export
4. Right-click an item in the sidebar to retranscribe, rename or delete it

Audio files are referenced, not copied: if you move a file, the transcript stays readable and a *Relier…* button lets you point back to the new location.

## Privacy

- Audio is uploaded only to `api.mistral.ai` for transcription — no analytics, no other network calls
- The API key lives in the macOS Keychain
- Transcripts are stored locally in `~/Library/Application Support`

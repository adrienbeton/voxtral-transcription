# Voxtral Transcription

App macOS locale : transcription + diarization de fichiers audio via l'API Mistral
(Voxtral Mini Transcribe 2), historique, lecture synchronisée audio/transcript.

## Build

```bash
swift build          # debug
swift test           # tests
./scripts/bundle.sh  # produit build/Voxtral.app
```

## Usage

1. Ouvrir Voxtral.app, aller dans Réglages (⌘,) et coller sa clé API Mistral.
2. Glisser un fichier audio dans la fenêtre (mp3, m4a, wav, flac…).
3. Cliquer un segment pour positionner l'audio ; ⌘F pour chercher ; renommer
   les speakers en cliquant leur nom ; Copier / Exporter depuis la toolbar.

Les fichiers audio sont référencés, pas copiés : si tu déplaces un fichier,
le transcript reste lisible mais la lecture est désactivée.

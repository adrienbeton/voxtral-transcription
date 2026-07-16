# Voxtral Transcription — Design

**Date** : 2026-07-16
**Statut** : validé par Adrien

## Objectif

App macOS locale et personnelle : transcription + diarization de fichiers audio via l'API Mistral, avec historique et lecture synchronisée audio ↔ transcript.

## Stack

- **Swift 6 / SwiftUI**, app macOS pure (cible macOS 15+, Apple Silicon)
- **SwiftData** pour la persistance
- **AVFoundation** (`AVAudioPlayer` ou `AVPlayer`) pour la lecture audio
- **URLSession** pour l'API (multipart upload, pas de SDK tiers)
- Clé API stockée dans le **Keychain** macOS

## API Mistral

- Endpoint : `POST https://api.mistral.ai/v1/audio/transcriptions` (multipart/form-data)
- Modèle : `voxtral-mini-2602` (Voxtral Mini Transcribe 2, $0.003/min)
- Paramètres : `diarize=true`, `timestamp_granularities=["segment"]`
- Contrainte : `timestamp_granularities` incompatible avec `language` → langue en auto-détection
- Réponse : texte complet + segments avec `start`, `end`, `speaker` (IDs type `speaker_0`)

## Modèle de données (SwiftData)

### `Transcription`
- `id: UUID`
- `fileName: String` (nom du fichier original)
- `fileBookmark: Data` (bookmark sécurisé vers le fichier audio original — pas de copie)
- `createdAt: Date`
- `duration: TimeInterval`
- `detectedLanguage: String?`
- `status: enum` (pending / done / failed) + `errorMessage: String?`
- `fullText: String`
- `speakerNames: [String: String]` (ID speaker brut → nom personnalisé)
- Relation 1-N → `Segment`

### `Segment`
- `text: String`
- `start: TimeInterval`
- `end: TimeInterval`
- `speaker: String` (ID brut renvoyé par l'API)
- `order: Int`

## UI — fenêtre unique master-detail

### Sidebar (historique)
- Liste des transcriptions : nom, date, durée, statut
- Champ de recherche : filtre sur nom de fichier ET contenu des segments
- Suppression par clic droit (supprime l'entrée, pas le fichier audio)

### Vue détail (player + transcript)
- Contrôles : play/pause, scrubber, vitesse (1x / 1.5x / 2x)
- Transcript en liste de segments : pastille couleur par speaker + nom + texte
- **Sync bidirectionnelle** :
  - Lecture → segment courant surligné + auto-scroll
  - Clic sur un segment → l'audio saute à `segment.start`
- **Renommage speakers** : clic sur le label → popover champ texte → appliqué à tous les segments de ce speaker (stocké dans `speakerNames`)
- **Recherche in-transcript** (⌘F) : surlignage des occurrences, navigation suivant/précédent, clic sur occurrence → seek audio
- Toolbar : **Copier** (presse-papier) et **Exporter…** (save panel)

### Settings
- Champ clé API Mistral → Keychain

## Import

- Drag & drop d'un fichier audio dans la fenêtre, ou bouton « Ouvrir » (file picker)
- Formats acceptés : audio courants (mp3, m4a, wav, flac, ogg)
- Flow : drop → création `Transcription` (pending) → upload multipart → parsing réponse → sauvegarde segments → statut done
- Indicateur de progression pendant l'upload/traitement

## Export

- **Copier** : transcript complet au presse-papier, format `[Nom speaker] texte` ligne par ligne
- **Exporter…** : `.txt` (même format) ou `.md` (timestamps `[hh:mm:ss]` + speakers en gras)
- Les noms personnalisés des speakers sont utilisés dans les deux cas

## Gestion d'erreurs

- Clé API absente → message + lien vers Settings
- Échec API (clé invalide, fichier trop gros, réseau) → statut `failed` avec message + bouton retry
- Fichier audio introuvable au replay (déplacé/supprimé) → transcript consultable, player désactivé avec message

## Hors scope (YAGNI)

- Édition du texte du transcript
- Watch folder / transcription automatique
- Enregistrement micro
- Export SRT/VTT, PDF
- Multi-fenêtres, iCloud sync

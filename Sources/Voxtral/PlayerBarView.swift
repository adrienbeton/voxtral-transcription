import SwiftUI
import VoxtralCore

struct PlayerBarView: View {
    @Bindable var player: PlayerController

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { player.togglePlay() }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.space, modifiers: [])

            Text(ExportFormatter.timestamp(player.currentTime))
                .font(.caption.monospacedDigit())

            Slider(value: Binding(
                get: { player.currentTime },
                set: { player.seek(to: $0) }
            ), in: 0...max(player.duration, 1))

            Text(ExportFormatter.timestamp(player.duration))
                .font(.caption.monospacedDigit())

            Picker("", selection: $player.rate) {
                Text("1×").tag(Float(1.0))
                Text("1,5×").tag(Float(1.5))
                Text("2×").tag(Float(2.0))
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

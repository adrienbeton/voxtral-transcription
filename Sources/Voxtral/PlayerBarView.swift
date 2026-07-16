import AppKit
import SwiftUI
import VoxtralCore

struct PlayerBarView: View {
    @Bindable var player: PlayerController
    @State private var spaceKeyMonitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { player.togglePlay() }) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)

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
        .onAppear {
            guard spaceKeyMonitor == nil else { return }
            spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 49 else { return event }
                let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
                guard event.modifierFlags.intersection(relevantFlags).isEmpty else { return event }
                guard !(NSApp.keyWindow?.firstResponder is NSTextView) else { return event }
                player.togglePlay()
                return nil
            }
        }
        .onDisappear {
            if let monitor = spaceKeyMonitor {
                NSEvent.removeMonitor(monitor)
                spaceKeyMonitor = nil
            }
        }
    }
}

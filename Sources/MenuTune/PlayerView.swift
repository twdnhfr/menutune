import AppKit
import MenuTuneCore
import SwiftUI
import WebKit

struct PlayerView: View {
    @ObservedObject var model: AppModel

    private let purple = Color(red: 0.52, green: 0.32, blue: 0.92)

    var body: some View {
        VStack(spacing: 0) {
            video
                .frame(width: playerWidth, height: playerHeight)

            if model.playerSize == .standard {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        if model.errorMessage != nil || model.storageWarning != nil || model.shortcutWarning != nil { inlineNotices }
                        titleRow
                        if model.clipboardSuggestion != nil { clipboardSuggestionRow }
                        addBar
                        queue
                        footer
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }

            bottomBar
        }
        .frame(width: playerWidth)
        .background(.regularMaterial)
        .tint(purple)
    }

    private var playerWidth: CGFloat {
        CGFloat(model.playerSize.width)
    }

    private var playerHeight: CGFloat {
        CGFloat(model.playerSize.videoHeight)
    }

    private var inlineNotices: some View {
        VStack(spacing: 7) {
            if let errorMessage = model.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button("Erneut versuchen") { model.togglePlayback() }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.borderless)
                    } else {
                        Button("Erneut versuchen") { model.addInput(playImmediately: true) }
                            .font(.caption.weight(.medium))
                            .buttonStyle(.borderless)
                    }
                    Button {
                        model.dismissError()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Fehlermeldung schließen")
                }
                .padding(9)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            if let storageWarning = model.storageWarning {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    Text(storageWarning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(9)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            }

            if let shortcutWarning = model.shortcutWarning {
                Label(shortcutWarning, systemImage: "keyboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var video: some View {
        YouTubeWebView(webView: model.player.webView)
            .frame(width: playerWidth, height: playerHeight)
            .background(Color.black)
            .overlay {
                if model.queue.currentItem == nil {
                    if model.playerSize == .mini {
                        Button {
                            model.togglePlayerSize()
                        } label: {
                            Label("Standardansicht öffnen", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.88))
                        }
                        .buttonStyle(.borderless)
                        .help("Standardansicht öffnen")
                        .shadow(radius: 4)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "play.rectangle.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.7))
                            Text("Füge einen YouTube-Link hinzu")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .shadow(radius: 4)
                    }
                }
            }
            .accessibilityLabel("YouTube-Player")
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let currentItem = model.queue.currentItem {
                    Text(currentItem.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)
                } else {
                    Text("Bereit für deine Musik")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    if model.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                            .accessibilityLabel("Lädt")
                    }
                    Text(model.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.onCollapse?()
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Menü schließen (⌘⇧Y)")
            .accessibilityLabel("Menü schließen")
        }
    }

    private var addBar: some View {
        HStack(spacing: 8) {
            TextField("YouTube-Link einfügen …", text: $model.input)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.addInput(playImmediately: true) }
                .accessibilityLabel("YouTube-Link")

            Button {
                model.addInput()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("Zur Warteschlange hinzufügen")
            .accessibilityLabel("Zur Warteschlange hinzufügen")
            .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        }
    }

    private var clipboardSuggestionRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "doc.on.clipboard")
                .font(.caption)
                .foregroundStyle(purple)

            Text("YouTube-Link in der Zwischenablage")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.acceptClipboardSuggestion()
            } label: {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(purple)
            .help("Zur Warteschlange übernehmen")
            .accessibilityLabel("Zur Warteschlange übernehmen")

            Button {
                model.dismissClipboardSuggestion()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Vorschlag verwerfen")
            .accessibilityLabel("Vorschlag verwerfen")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(purple.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
    }

    private var queue: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Warteschlange")
                    .font(.subheadline.weight(.semibold))
                Text("\(model.queue.items.count)")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Menu {
                    Button("Wiederholen: Aus") { setRepeat(.off) }
                    Button("Wiederholen: Alle") { setRepeat(.all) }
                    Button("Wiederholen: Titel") { setRepeat(.one) }
                } label: {
                    Image(systemName: repeatIcon)
                        .foregroundStyle(model.queue.repeatMode == .off ? .secondary : purple)
                        .frame(width: 23, height: 23)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Wiederholung: \(repeatLabel)")
                Spacer()
            }

            if model.queue.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "music.note.list")
                        .font(.title3)
                        .foregroundStyle(purple.opacity(0.8))
                    Text("Deine Musik. Ein Klick entfernt.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Füge oben einen YouTube-Link hinzu.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(Array(model.queue.items.enumerated()), id: \.element.id) { index, item in
                            queueRow(item, index: index)
                            if item.id != model.queue.items.last?.id { Divider().padding(.leading, 36) }
                        }
                    }
                }
                .frame(height: min(CGFloat(150), CGFloat(model.queue.items.count * 42)))
            }
        }
    }

    private func queueRow(_ item: QueueItem, index: Int) -> some View {
        let selected = model.queue.currentItemID == item.id
        return HStack(spacing: 9) {
            Image(systemName: selected && model.isPlaying ? "waveform" : "music.note")
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? purple : .secondary)
                .frame(width: 20)

            Button {
                model.play(item)
            } label: {
                Text(item.title)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? purple : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.title), \(selected ? "ausgewählt" : "abspielen")")

            Menu("") {
                Button("Abspielen") { model.play(item) }
                Divider()
                Button("Nach oben") { model.move(item, by: -1) }
                    .disabled(index == 0)
                Button("Nach unten") { model.move(item, by: 1) }
                    .disabled(index == model.queue.items.count - 1)
                Divider()
                Button("Entfernen", role: .destructive) { model.remove(item) }
            }
            .menuStyle(.borderlessButton)
            .frame(width: 26, height: 26)
            .accessibilityLabel("Aktionen für \(item.title)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? purple.opacity(0.09) : .clear)
        .contentShape(Rectangle())
    }

    private var footer: some View {
        HStack {
            Button {
                model.openCurrentOnYouTube()
            } label: {
                Label("Auf YouTube öffnen", systemImage: "arrow.up.right.square")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Auf YouTube öffnen")
            .accessibilityLabel("Auf YouTube öffnen")
            .disabled(model.queue.currentItem == nil)

            Spacer()

            Button("Beenden") {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
        .foregroundStyle(.secondary)
    }

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Spacer()
            playerSizeControl
            if model.playerSize == .mini { Spacer() }
        }
        .padding(.horizontal, 7)
        .frame(height: 32)
        .background(.regularMaterial)
    }

    private var playerSizeControl: some View {
        HStack(spacing: 0) {
            sizeButton("Standard", isSelected: model.playerSize == .standard) {
                if model.playerSize == .mini { model.togglePlayerSize() }
            }
            sizeButton("Mini", isSelected: model.playerSize == .mini) {
                if model.playerSize == .standard { model.togglePlayerSize() }
            }
        }
        .padding(2)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Playergröße")
    }

    private func sizeButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .frame(minWidth: 39)
                .background(isSelected ? purple.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .disabled(isSelected)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var repeatIcon: String {
        model.queue.repeatMode == .one ? "repeat.1" : "repeat"
    }

    private var repeatLabel: String {
        switch model.queue.repeatMode {
        case .off: return "Aus"
        case .all: return "Alle"
        case .one: return "Titel"
        }
    }

    private func setRepeat(_ mode: RepeatMode) {
        while model.queue.repeatMode != mode { model.cycleRepeat() }
    }

}

private struct YouTubeWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // The player owns this web view. Reusing it preserves playback across redraws.
    }
}

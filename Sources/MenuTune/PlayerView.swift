import AppKit
import MenuTuneCore
import SwiftUI
import WebKit

/// Carries the natural height of the scrolling middle section out to the model,
/// so the popover is sized from the real layout instead of a copy of it.
private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) {
        value = max(value, nextValue())
    }
}

struct PlayerView: View {
    @ObservedObject var model: AppModel

    /// Read by StatusItemController; the popover adds it to video and content.
    static let bottomBarHeight: Double = 32

    private let purple = Color(red: 0.52, green: 0.32, blue: 0.92)

    var body: some View {
        VStack(spacing: 0) {
            video
                .frame(width: playerWidth, height: playerHeight)

            if model.showsContentSection {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        if model.errorMessage != nil || model.storageWarning != nil || model.shortcutWarning != nil { inlineNotices }
                        titleRow
                        if model.clipboardSuggestion != nil { clipboardSuggestionRow }
                        addBar
                        queue
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    // Inside the scroll view this measures the natural height,
                    // not the height the popover currently grants it.
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                        }
                    )
                }
            }

            bottomBar
        }
        .frame(width: playerWidth)
        .background(.regularMaterial)
        .tint(purple)
        .onPreferenceChange(ContentHeightKey.self) { [model] height in
            Task { @MainActor in
                if abs(model.contentHeight - height) > 0.5 { model.contentHeight = height }
            }
        }
    }

    private var playerWidth: CGFloat {
        CGFloat(model.playerSize.width)
    }

    private var playerHeight: CGFloat {
        CGFloat(model.embeddedVideoHeight)
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
        YouTubeWebView(webView: model.player.webView, isActive: !model.isPoppedOut)
            .frame(width: playerWidth, height: playerHeight)
            .background(Color.black)
            .overlay {
                if model.isPoppedOut {
                    Button {
                        model.onTogglePopOut?()
                    } label: {
                        Label("Video zurückholen", systemImage: "pip.exit")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.borderless)
                    .help("Video zurück in die Menüleiste holen")
                } else if model.queue.currentItem == nil {
                    if model.playerSize == .mini {
                        Button {
                            model.playerSize = .standard
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
                Button {
                    model.isQueueExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.isQueueExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text("Warteschlange")
                            .font(.subheadline.weight(.semibold))
                        Text("\(model.queue.items.count)")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Warteschlange, \(model.queue.items.count) Titel")
                .accessibilityValue(model.isQueueExpanded ? "Aufgeklappt" : "Zugeklappt")
                .help(model.isQueueExpanded ? "Warteschlange zuklappen" : "Warteschlange aufklappen")
                Menu {
                    Button("Wiederholen: Aus") { model.setRepeat(.off) }
                    Button("Wiederholen: Alle") { model.setRepeat(.all) }
                    Button("Wiederholen: Titel") { model.setRepeat(.one) }
                } label: {
                    Image(systemName: repeatIcon)
                        .foregroundStyle(model.queue.repeatMode == .off ? .secondary : purple)
                        .frame(width: 23, height: 23)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Wiederholung: \(repeatLabel)")
            }

            if model.isQueueExpanded {
                queueContents
            }
        }
    }

    @ViewBuilder
    private var queueContents: some View {
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

    private var bottomBar: some View {
        HStack(spacing: 6) {
            Button {
                model.onTogglePopOut?()
            } label: {
                Image(systemName: model.isPoppedOut ? "pip.exit" : "pip.enter")
                    .font(.system(size: 12))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .help(model.isPoppedOut ? "Video zurückholen" : "Video auskoppeln – weicht der Maus aus")
            .accessibilityLabel(model.isPoppedOut ? "Video zurückholen" : "Video auskoppeln")
            .disabled(model.currentItem == nil)
            Spacer()
            playerSizeControl
        }
        .padding(.horizontal, 7)
        .frame(height: Self.bottomBarHeight)
        .background(.regularMaterial)
    }

    private var playerSizeControl: some View {
        HStack(spacing: 0) {
            sizeButton("Standard", isSelected: model.playerSize == .standard) {
                model.playerSize = .standard
            }
            sizeButton("Mittel", isSelected: model.playerSize == .medium) {
                model.playerSize = .medium
            }
            sizeButton("Mini", isSelected: model.playerSize == .mini) {
                model.playerSize = .mini
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

}

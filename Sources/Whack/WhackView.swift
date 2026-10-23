import SwiftUI
import WhackCore

struct WhackView: View {
    @ObservedObject var model: AppModel
    @State private var isDropTarget = false
    @Environment(\.colorScheme) private var colorScheme
    private let orange = Color(red: 0.95, green: 0.36, blue: 0.16)
    private var panel: Color { colorScheme == .dark ? Color(white: 0.13) : Color(red: 1, green: 0.985, blue: 0.96) }

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 16) {
                reactionSwitch
                if let issue = model.outputIssue {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(issue, systemImage: "speaker.slash.fill")
                            .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                        Button(model.systemOutputNeedsAttention ? "Sound settings" : "Adjust Whack volume") {
                            if model.systemOutputNeedsAttention { model.openSoundSettings() }
                            else { model.showSettings = true }
                        }.font(.system(size: 11, weight: .semibold))
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                }
                if let issue = model.sensorIssue { sensorNotice(issue) }
                HStack {
                    Text("PICK YOUR REACTION").font(.system(size: 10, weight: .bold, design: .rounded)).tracking(1.3)
                    Spacer()
                    Text("\(model.sounds.count) sounds").font(.system(size: 11))
                }.foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(model.sounds) { sound in soundRow(sound) }
                    }
                    .padding(.trailing, 2)
                }
                .frame(height: soundListHeight)
                .scrollIndicators(.visible)
                Button { model.chooseFiles() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(orange)
                        Text(isDropTarget ? "Drop it like it’s hot" : "Add your own sound").fontWeight(.semibold)
                        Spacer()
                        Text("MP3 / WAV").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .padding(13)
                    .background(orange.opacity(isDropTarget ? 0.15 : 0.055), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(orange.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.canEdit)
                .dropDestination(for: URL.self) { urls, _ in
                    guard model.canEdit, !urls.isEmpty else { return false }
                    model.importFiles(urls); return true
                } isTargeted: { isDropTarget = $0 }
                if model.showSettings { settings }
            }
            .padding(.horizontal, 22).padding(.bottom, 18)
            footer
        }
        .frame(width: 390)
        .background(panel)
        .tint(orange)
        .alert("Something needs a little attention", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
            if !model.canEdit { Button("Open library folder") { model.revealLibrary() } }
        } message: { Text(model.errorMessage ?? "") }
        .sheet(item: $model.renameSound) { _ in
            VStack(alignment: .leading, spacing: 18) {
                Text("Name that sound").font(.system(size: 21, weight: .bold, design: .rounded))
                TextField("Sound name", text: $model.renameText).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Sound name")
                    .onSubmit { model.saveRename() }
                HStack {
                    Spacer()
                    Button("Cancel") { model.renameSound = nil }.keyboardShortcut(.cancelAction)
                    Button("Save") { model.saveRename() }.keyboardShortcut(.defaultAction)
                        .disabled(model.renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.renameText.count > 60)
                }
            }.padding(24).frame(width: 320)
        }
        .alert("Delete \(model.deleteSound?.name ?? "sound")?", isPresented: Binding(get: { model.deleteSound != nil }, set: { if !$0 { model.deleteSound = nil } })) {
            Button("Cancel", role: .cancel) { model.deleteSound = nil }
            Button("Delete", role: .destructive) { model.confirmDelete() }
        } message: { Text("This removes Whack’s copy. Your original file stays where it is.") }
    }

    private var soundListHeight: CGFloat {
        let available = (NSScreen.main?.visibleFrame.height ?? 900) - 50
        let surrounding: CGFloat = 334 + (model.showSettings ? 174 : 0) + (model.sensorIssue == nil ? 0 : 150) + (model.outputIssue == nil ? 0 : 105)
        return min(230, CGFloat(model.sounds.count) * 55, max(80, available - surrounding))
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let url = Bundle.whackAssets.url(forResource: "whack", withExtension: "png"), let logo = NSImage(contentsOf: url) {
                Image(nsImage: logo).resizable().scaledToFit().frame(width: 54, height: 54)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Whack!").font(.system(size: 30, weight: .heavy, design: .rounded)).tracking(-1)
                Text("A little tap. A big personality.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }.padding(.horizontal, 22).padding(.top, 23).padding(.bottom, 21)
    }

    private var reactionSwitch: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                HStack(spacing: 7) {
                    Circle().fill(model.isOn ? orange : Color.secondary.opacity(0.45)).frame(width: 6, height: 6)
                    Text(model.isOn ? "Let’s make some noise" : "Give your Mac a voice")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                Spacer(minLength: 6)
                Toggle("Tap reactions", isOn: Binding(get: { model.isOn }, set: model.setEnabled))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).disabled(!model.canEdit)
                    .accessibilityLabel("Tap reactions")
            }
            Text(model.status).font(.system(size: 11)).foregroundStyle(.secondary)
            if model.isOn {
                GeometryReader { geometry in
                    Capsule().fill(orange.opacity(0.12))
                        .overlay(alignment: .leading) {
                            Capsule().fill(orange).frame(width: max(4, geometry.size.width * model.level))
                        }
                }.frame(height: 4).accessibilityLabel("Motion level").accessibilityValue("\(Int(model.level * 100)) percent")
            }
        }.padding(14).background(orange.opacity(0.075), in: RoundedRectangle(cornerRadius: 14))
    }

    private func sensorNotice(_ issue: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tap detection needs attention", systemImage: "exclamationmark.circle").font(.system(size: 12, weight: .semibold))
            Text(issue).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button("Try sensor again") { model.setEnabled(true) }.font(.system(size: 11, weight: .semibold))
        }.padding(12).background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func soundRow(_ sound: Sound) -> some View {
        let selected = model.selectedID == sound.id
        return HStack(spacing: 8) {
            Button { model.select(sound) } label: {
                HStack(spacing: 10) {
                    Image(systemName: sound.symbol).font(.system(size: 17, weight: .medium))
                        .foregroundStyle(selected ? orange : Color.secondary).frame(width: 25)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sound.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(sound.id == "moan" ? "Synth voice · \(sound.duration, specifier: "%.1f")s" : "\(sound.bundled ? "Original" : "Your sound") · \(sound.duration, specifier: "%.1f")s")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(orange) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Select \(sound.name)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            Button { model.preview(sound) } label: {
                Image(systemName: model.playingID == sound.id ? "stop.fill" : "play.fill")
                    .font(.system(size: 11)).frame(width: 29, height: 29)
                    .background(Color.primary.opacity(0.055), in: Circle())
            }.buttonStyle(.plain).help(model.playingID == sound.id ? "Stop preview" : "Preview \(sound.name)")
                .accessibilityLabel(model.playingID == sound.id ? "Stop \(sound.name)" : "Preview \(sound.name)")
            if !sound.bundled {
                Menu {
                    Button("Rename…") { model.beginRename(sound) }
                    Button("Replace…") { model.chooseFiles(replacing: sound) }
                    Divider()
                    Button("Delete…", role: .destructive) { model.deleteSound = sound }
                } label: { Image(systemName: "ellipsis").frame(width: 15, height: 25) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("Manage \(sound.name)")
            }
        }.padding(.horizontal, 10).padding(.vertical, 8)
            .background(selected ? orange.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
            .disabled(!model.canEdit)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack { Text("Sensitivity"); Spacer(); Text(model.preferences.sensitivity < 0.34 ? "Firm" : model.preferences.sensitivity > 0.66 ? "Light" : "Balanced").foregroundStyle(.secondary) }
                Slider(value: Binding(get: { model.preferences.sensitivity }, set: model.setSensitivity), in: 0...1)
                    .accessibilityLabel("Tap sensitivity")
                Text("Typing is muted. Pause briefly, then tap.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                Text("Cooldown")
                Spacer()
                Slider(value: Binding(get: { model.preferences.cooldown }, set: { model.setCooldown(($0 * 20).rounded() / 20) }), in: 0.2...2)
                    .frame(width: 140).accessibilityLabel("Cooldown between taps")
                Text("\(model.preferences.cooldown, specifier: "%.2f")s").monospacedDigit().frame(width: 38)
            }
            HStack {
                Text("Volume")
                Spacer()
                Slider(value: Binding(get: { model.preferences.volume }, set: model.setVolume), in: 0...1)
                    .frame(width: 140).accessibilityLabel("Sound volume")
                Text("\(Int(model.preferences.volume * 100))%").monospacedDigit().frame(width: 38)
            }
            Text("Reactions pause while audio plays. A gentle tap is plenty.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.font(.system(size: 11)).disabled(!model.canEdit)
    }

    private var footer: some View {
        HStack {
            Button { model.showSettings.toggle() } label: {
                Label("Settings", systemImage: "slider.horizontal.3").foregroundStyle(model.showSettings ? orange : .secondary)
            }.buttonStyle(.plain)
            Spacer()
            Text(model.tapCount == 0 ? "Tap gently. Laugh loudly." : "\(model.tapCount) \(model.tapCount == 1 ? "tap" : "taps"). Excellent taste.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
            Spacer()
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Quit Whack")
                .accessibilityLabel("Quit Whack")
        }.font(.system(size: 11)).padding(.horizontal, 22).padding(.vertical, 14)
            .background(Color.primary.opacity(0.025))
    }
}

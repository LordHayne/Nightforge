import AppKit
import SwiftUI

/// The design's glass: frosted, lit from above – a bright rim, a sheen in the upper half – and
/// lifted off the backdrop by a shadow. Drawn by hand rather than with macOS 26's Liquid Glass, so
/// it looks the same from macOS 14 on and shows in the offscreen renders the screens are checked with.
struct Glass: Equatable {
    /// Coloured glass: sodium for the main action, ink for a switch that's on.
    var tint: Color?
    /// Darker and denser, for messages laid over everything.
    var thick = false
    /// The tint's light falls around the glass – only the one main action.
    var glows = false

    static let regular = Glass()
    static let thick = Glass(thick: true)

    static func tinted(_ color: Color, glows: Bool = false) -> Glass {
        Glass(tint: color, glows: glows)
    }
}

/// The glass behind a control's content.
struct GlassBackground<S: InsettableShape>: View {
    let glass: Glass
    let shape: S
    var hovering = false
    /// A busy main action: the tint at half strength.
    var dimmed = false
    /// Part of the glass filled with the full tint from the left (a download's progress).
    var progress: Double?

    var body: some View {
        ZStack(alignment: .leading) {
            if let tint = glass.tint {
                // Solid coloured glass; a busy one lets the frosted backdrop through.
                if dimmed { shape.fill(.ultraThinMaterial) }
                shape.fill(tint.opacity(dimmed ? 0.55 : 1))
                    .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
                if let progress {
                    GeometryReader { geo in
                        shape.fill(tint).frame(width: max(geo.size.height, geo.size.width * progress))
                    }
                }
                // Deeper towards the bottom, like the light through a lens.
                shape.fill(LinearGradient(colors: [.black.opacity(0), .black.opacity(hovering ? 0.04 : 0.1)],
                                          startPoint: .center, endPoint: .bottom))
            } else {
                shape.fill(.ultraThinMaterial)
                    .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
                // Thick glass is the design's night blue, lighter at the top, not the material's grey.
                if glass.thick {
                    shape.fill(LinearGradient(colors: [Theme.slate.opacity(0.85), Theme.night.opacity(0.9)],
                                              startPoint: .top, endPoint: .bottom))
                }
                shape.fill(LinearGradient(colors: [.white.opacity(glass.thick ? 0.06 : hovering ? 0.16 : 0.09),
                                                   .white.opacity(glass.thick ? 0.02 : hovering ? 0.06 : 0.03)],
                                          startPoint: .top, endPoint: .bottom))
            }
            // The sheen: the upper half catches the light.
            shape.inset(by: 1.5)
                .fill(LinearGradient(colors: [.white.opacity(sheen), .white.opacity(0)], startPoint: .top, endPoint: .center))
            shape.strokeBorder(LinearGradient(stops: rim, startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }

    private var sheen: Double {
        if glass.tint != nil { return hovering ? 0.55 : 0.45 }
        return glass.thick ? 0.04 : hovering ? 0.12 : 0.07
    }

    /// Bright at the top where the light hits, nearly gone in the middle, a faint reflection below.
    private var rim: [Gradient.Stop] {
        let top = glass.tint != nil ? 0.65 : glass.thick ? 0.22 : hovering ? 0.55 : 0.42
        return [.init(color: .white.opacity(top), location: 0),
                .init(color: .white.opacity(top * 0.25), location: 0.35),
                .init(color: .white.opacity(top * 0.1), location: 0.65),
                .init(color: .white.opacity(top * 0.4), location: 1)]
    }

    private var shadow: (color: Color, radius: CGFloat, y: CGFloat) {
        if glass.glows, let tint = glass.tint { return (tint.opacity(hovering ? 0.6 : 0.4), hovering ? 24 : 16, 6) }
        if glass.tint != nil { return (.black.opacity(0.25), 8, 4) }
        if glass.thick { return (.black.opacity(0.45), 18, 8) }
        return (.black.opacity(0.28), 10, 5)
    }
}

/// A button on glass: brighter under the pointer, a little smaller while pressed.
struct GlassButtonStyle<S: InsettableShape>: ButtonStyle {
    var glass = Glass.regular
    let shape: S
    var dimmed = false
    var progress: Double?
    /// Off for a button that stays readable while it can't be pressed (Play while a game starts).
    var fadesWhenDisabled = true

    func makeBody(configuration: Configuration) -> some View {
        GlassControl(label: configuration.label, glass: glass, shape: shape, pressed: configuration.isPressed,
                     dimmed: dimmed, progress: progress, fadesWhenDisabled: fadesWhenDisabled)
    }
}

/// A text button on glass, for the ones beside the big buttons ("Clear filters", "Load Mac Version").
struct GlassTextButtonStyle: ButtonStyle {
    /// Sodium glass for the action a screen is about.
    var prominent = false
    /// Red glass for the answer that deletes something – never a dialog's default.
    var destructive = false
    var small = false

    func makeBody(configuration: Configuration) -> some View {
        let tint = destructive ? Theme.danger : prominent ? Theme.sodium : nil
        GlassControl(label: configuration.label
                        .font(size: small ? 12.5 : 14, weight: .semibold)
                        .foregroundStyle(tint != nil ? Theme.night : Theme.ink)
                        .padding(.horizontal, small ? 14 : 22)
                        .frame(height: small ? 30 : 42),
                     glass: tint.map { .tinted($0) } ?? .regular, shape: Capsule(), pressed: configuration.isPressed)
    }
}

/// A button inside a shared piece of glass (the top bar's downloads, rescan and settings): no glass of
/// its own, a light capsule under the pointer.
struct GlassGroupButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassGroupButton(label: configuration.label, pressed: configuration.isPressed)
    }
}

/// The design's switch: sodium while on, a white knob that slides across. The label sits on the left.
struct GlassSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 16) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            GlassSwitch(isOn: configuration.isOn) { configuration.isOn.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? L10n.t("On") : L10n.t("Off"))
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

private struct GlassSwitch: View {
    let isOn: Bool
    let toggle: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.sodium : .white.opacity(0.15))
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(isOn ? 0.5 : 0.1), .white.opacity(0)],
                                                           startPoint: .top, endPoint: .bottom)))
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
                    .frame(width: 20, height: 20)
                    .padding(3)
            }
            .frame(width: 46, height: 26)
            .contentShape(Capsule())
            .onTapGesture { if isEnabled { toggle() } }
            .opacity(isEnabled ? 1 : 0.5)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isOn)
    }
}

/// The thin line between buttons that share a piece of glass.
struct GlassDivider: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 16)
    }
}

private struct GlassGroupButton<Label: View>: View {
    let label: Label
    let pressed: Bool
    @State private var hovering = false
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        label
            .foregroundStyle(Theme.ink.opacity(hovering ? 1 : 0.9))
            .frame(width: 36, height: 30)
            .background(Capsule().fill(.white.opacity(hovering ? 0.15 : 0)))
            .contentShape(Capsule())
            .scaleEffect(pressed && !reduceMotion ? 0.9 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

private struct GlassControl<Label: View, S: InsettableShape>: View {
    let label: Label
    let glass: Glass
    let shape: S
    let pressed: Bool
    var dimmed = false
    var progress: Double?
    var fadesWhenDisabled = true
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.reduceMotion) private var reduceMotion

    var body: some View {
        label
            .background(GlassBackground(glass: glass, shape: shape, hovering: hovering && isEnabled, dimmed: dimmed, progress: progress))
            .contentShape(shape)
            .opacity(isEnabled || !fadesWhenDisabled ? 1 : 0.5)
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: pressed)
    }
}

// MARK: - Dialogs

/// The design's dialog: its title, the round close button, then the content – on thick glass over
/// the library instead of the system's sheet panel. Esc and B close it through the × button.
struct GlassDialog<Content: View>: View {
    let title: String
    let id: String
    let width: CGFloat
    let spacing: CGFloat
    let close: (() -> Void)?
    let content: Content
    @Environment(\.dismiss) private var dismiss

    /// `id` names the pad's close button ("<id>.close"); `close` replaces just closing the sheet.
    init(_ title: String, id: String, width: CGFloat = 500, spacing: CGFloat = 20, close: (() -> Void)? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.id = id
        self.width = width
        self.spacing = spacing
        self.close = close
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            GlassDialogHeader(title: title, id: id) { (close ?? { dismiss() })() }
            content
        }
        .padding(28)
        .frame(width: width)
        // Never past the window: a part that scrolls (DialogScroll) gives way.
        .frame(maxHeight: DialogRoom.height)
        .fixedSize(horizontal: false, vertical: true)
        .glassDialogBackground()
    }
}

/// How tall a dialog may be: Nightforge's window less a margin. A taller sheet pushes the window
/// up and hangs out below it, so a dialog's long part scrolls within this instead.
enum DialogRoom {
    @MainActor static var height: CGFloat {
        let window = NSApp.windows.first { $0.title == "Nightforge" }?.contentLayoutRect.height
            ?? NSScreen.main?.visibleFrame.height ?? 800
        return window - 40
    }
}

/// The part of a dialog that scrolls once the dialog would reach past the window (DialogRoom),
/// while its title and buttons stay: until then just as tall as what's in it. The pad's highlight
/// brings what it moves to into view.
struct DialogScroll<Content: View>: View {
    let spacing: CGFloat
    let content: Content
    @ObservedObject private var padFocus = PadFocus.shared

    init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: spacing) { content }
                // Room for the pad's highlight, which reaches a little past each control.
                .padding(8)
        }
        .scrollBounceBehavior(.basedOnSize)
        .padding(-8)
        .onChange(of: padFocus.focused) { _, id in padFocus.reveal(id) }
    }
}

/// A dialog's title with the round × beside it.
struct GlassDialogHeader: View {
    let title: String
    let id: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            Text(title)
                .displayFont(22)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            GlassCloseButton(id: "\(id).close", action: close)
                .padding(.top, -4)
                .padding(.trailing, -8)
        }
    }
}

/// The round × at a dialog's top right; Esc (and B, which sends it) presses it.
struct GlassCloseButton: View {
    let id: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(size: 12, weight: .bold, scales: false)
                .foregroundStyle(Theme.ink.opacity(0.8))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(GlassButtonStyle(shape: Circle()))
        .keyboardShortcut(.cancelAction)
        .help(L10n.t("Close"))
        .accessibilityLabel(L10n.t("Close"))
        .padFocus(id, cornerRadius: 16, activate: action)
    }
}

/// A question or a message instead of the system's alert: the text, then the answers on the right.
/// The safe answer is the default (Return, and where the pad starts); a destructive one never is.
struct GlassQuestion<Buttons: View>: View {
    let title: String
    let message: String
    let id: String
    let buttons: Buttons

    init(_ title: String, message: String, id: String, @ViewBuilder buttons: () -> Buttons) {
        self.title = title
        self.message = message
        self.id = id
        self.buttons = buttons()
    }

    var body: some View {
        GlassDialog(title, id: id, width: 460) {
            Text(message)
                .font(size: 14)
                .lineSpacing(3)
                .foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                buttons
            }
            .padding(.top, 4)
        }
    }
}

/// A section's title, small and spaced out like the design's.
struct SectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(size: 11, weight: .semibold)
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.muted)
    }
}

/// A message for a GlassQuestion sheet, known by its text.
struct DialogMessage: Identifiable {
    let text: String
    var id: String { text }

    /// `message` as a sheet's item: shown while it's set, cleared when the sheet closes.
    static func item(_ message: Binding<String?>) -> Binding<DialogMessage?> {
        Binding(get: { message.wrappedValue.map(DialogMessage.init) },
                set: { if $0 == nil { message.wrappedValue = nil } })
    }
}

extension View {
    /// Thick night-blue glass behind a dialog, in place of the system's sheet panel.
    func glassDialogBackground() -> some View {
        foregroundStyle(Theme.ink)
            .background(GlassBackground(glass: .thick, shape: RoundedRectangle(cornerRadius: 28, style: .continuous)))
            .presentationBackground(.clear)
    }

    /// A darker well in the glass for rows and notes, like a download's row.
    func glassWell(cornerRadius: CGFloat = 16) -> some View {
        background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(.white.opacity(0.1)))
    }
}

// MARK: - Inputs and progress

/// The design's tick box, for picking several (games to make room with): sodium while ticked.
struct GlassCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(configuration.isOn ? Theme.sodium : .white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.white.opacity(configuration.isOn ? 0.45 : 0.3)))
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(size: 10, weight: .heavy, scales: false)
                            .foregroundStyle(Theme.night)
                    }
                }
                .frame(width: 18, height: 18)
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? L10n.t("On") : L10n.t("Off"))
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

/// The design's text field: a dark well in the glass, a sodium rim while typing. A on the pad
/// puts the cursor in it.
struct GlassTextField: View {
    let prompt: String
    @Binding var text: String
    let id: String
    var monospaced = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.muted.opacity(0.7)))
            .textFieldStyle(.plain)
            .font(size: 14, design: monospaced ? .monospaced : .default)
            .foregroundStyle(Theme.ink)
            .focused($focused)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? Theme.sodium.opacity(0.7) : .white.opacity(0.1)))
            .padFocus(id, cornerRadius: 12, activate: { focused = true })
    }
}

/// Busy: a faint ring with a sodium arc going round, in place of the system's spinner.
struct GlassSpinner: View {
    var size: CGFloat = 16
    /// Night on sodium glass, where a sodium arc wouldn't show.
    var tint = Theme.sodium

    var body: some View {
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            ZStack {
                Circle().stroke(tint == Theme.sodium ? .white.opacity(0.2) : tint.opacity(0.25), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(turn * 360))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// How far something is: sodium in a dark groove, like a download's bar.
struct GlassProgressBar: View {
    let value: Double
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(Theme.sodium)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int((value * 100).rounded())) %")
    }
}

import SwiftUI
import UniformTypeIdentifiers

// Overview cards for the Claude hub, the file shelf and the clipboard history.

// MARK: - Shared row

/// One line in a list card: leading mark, title, trailing detail. Lights up under the cursor.
private struct HubRow<Leading: View>: View {
    let title: String
    let detail: String
    var help: String = ""
    let action: () -> Void
    @ViewBuilder var leading: () -> Leading
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                leading().frame(width: 10)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(hovered ? 1 : 0.9))
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1)
                Spacer(minLength: 4)
                // The detail gives way first: a long folder name must never squeeze the title out
                Text(detail)
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 6)
            .frame(height: 19)
            .background(Color.white.opacity(hovered ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
    }
}

// MARK: - Claude hub

struct ClaudeHubCard: View {
    let task: AgentTask
    @ObservedObject private var appState = AppState.shared
    @State private var browsing = false      // looking at the session list while a session runs

    private var sessionActive: Bool { task.state != .idle || !task.steps.isEmpty }
    private var showsList: Bool { !sessionActive || browsing }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkillHeader(color: task.color,
                        title: sessionActive && !browsing ? task.name : "Claude Code",
                        subtitle: sessionActive && !browsing ? "Claude Code" : "") {
                HStack(spacing: 4) {
                    if sessionActive {
                        SkillIconButton(icon: browsing ? "waveform" : "list.bullet", size: 16, iconSize: 7) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { browsing.toggle() }
                        }
                        .help(browsing ? "Back to the running session" : "Recent sessions")
                    }
                    SkillIconButton(icon: "bubble.left.and.bubble.right.fill", size: 16, iconSize: 7) {
                        ClaudeHub.shared.openChats()
                    }
                    .help("Open Claude — your chats")
                    SkillIconButton(icon: "square.and.pencil", size: 16, iconSize: 7) {
                        ClaudeHub.shared.newChat()
                    }
                    .help("New chat in Claude")
                }
            }

            if showsList {
                UsageMeter(usage: appState.claudeUsage, refreshing: appState.claudeUsageRefreshing)
                    .padding(.top, 5)
                    .padding(.leading, SkillLayout.leading)
                    .padding(.trailing, SkillLayout.trailing)

                sessionList
                    .padding(.top, 3)
                    .padding(.leading, SkillLayout.leading - 6)
                    .padding(.trailing, SkillLayout.trailing - 6)
                    .transition(.opacity)
            } else {
                TickerView(task: task)
                    .frame(height: 44)
                    .padding(.top, 6)
                    .padding(.leading, SkillLayout.leading)
                    .padding(.trailing, SkillLayout.trailing)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .onAppear {
            ClaudeHub.shared.refreshSessions()
            ClaudeHub.shared.loadUsageFromDesktopApp()
        }
        .onChange(of: task.state) { _, _ in ClaudeHub.shared.refreshSessions() }
        .onChange(of: appState.focusId) { _, _ in browsing = false }
    }

    /// "Desktop · 2h" — the folder is cut short so the title keeps the room.
    private static func detail(for session: ClaudeSession) -> String {
        let project = session.project
        guard !project.isEmpty else { return session.timeAgo }
        let short = project.count > 11 ? String(project.prefix(10)) + "…" : project
        return "\(short) · \(session.timeAgo)"
    }

    @ViewBuilder
    private var sessionList: some View {
        if appState.claudeSessions.isEmpty {
            Text("No sessions yet. Run claude in a terminal and it will show up here.")
                .font(.system(size: 10.5))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(2)
                .padding(.horizontal, 6).padding(.top, 4)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(appState.claudeSessions) { session in
                        HubRow(title: session.title,
                               detail: Self.detail(for: session),
                               help: session.livePid != nil ? "Running — jump to its terminal tab" : "Resume in a new terminal window") {
                            ClaudeHub.shared.open(session)
                        } leading: {
                            if session.livePid != nil {
                                LiveDot(busy: session.busy)
                            } else {
                                Image(systemName: "terminal.fill")
                                    .font(.system(size: 7.5))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                        }
                    }
                }
            }
            .frame(height: 53)
        }
    }
}

/// Green dot for a session whose `claude` process is still alive; it breathes while busy.
private struct LiveDot: View {
    let busy: Bool

    var body: some View {
        PulsingDots(color: Color(hex: "#4ADE80"), size: 6, glow: 1...4, active: busy)
    }
}

/// Two slim gauges: how much of the 5-hour and weekly Claude limits is used. Tap to refresh.
private struct UsageMeter: View {
    let usage: ClaudeUsage?
    let refreshing: Bool
    @State private var hovered = false

    var body: some View {
        Button {
            ClaudeHub.shared.refreshUsageNow()
        } label: {
            HStack(spacing: 8) {
                gauge("5H", fiveHour)
                gauge("7D", sevenDay)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white.opacity(hovered || refreshing ? 0.9 : 0.35))
                    .rotationEffect(.degrees(refreshing ? 360 : 0))
                    .animation(refreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                               value: refreshing)
            }
            .frame(height: 12)
            .opacity(stale ? 0.6 : 1)   // dimmed until refreshed
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(helpText)
    }

    /// A reading is only worth showing while its window can still be the same one.
    private var fiveHour: Double? {
        guard let usage, Date().timeIntervalSince(usage.asOf) < 5 * 3600 else { return nil }
        return usage.fiveHour
    }
    private var sevenDay: Double? {
        guard let usage, Date().timeIntervalSince(usage.asOf) < 7 * 86400 else { return nil }
        return usage.sevenDay
    }
    private var stale: Bool { usage.map { Date().timeIntervalSince($0.asOf) > 30 * 60 } ?? true }

    private func gauge(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 7.5, weight: .bold))
                .tracking(0.5)
                .foregroundColor(.white.opacity(0.55))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Self.color(value ?? 0))
                        .frame(width: max(3, geo.size.width * min(max(value ?? 0, 0), 1)))
                        .shadow(color: Self.color(value ?? 0).opacity(0.6), radius: 3)
                }
            }
            .frame(height: 3)
            Text(value.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white.opacity(0.9))
                .contentTransition(.numericText())
                .frame(minWidth: 22, alignment: .trailing)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: value)
    }

    private static func color(_ v: Double) -> Color {
        v >= 0.9 ? Color(hex: "#FF6B78") : (v >= 0.7 ? Color(hex: "#FFC048") : .white)
    }

    private var helpText: String {
        guard let usage else { return "Claude plan usage — click to measure (sends one tiny request)" }
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(usage.asOf) ? "HH:mm" : "d MMM HH:mm"
        var text = "Claude plan usage as of \(f.string(from: usage.asOf))"
        if let resets = usage.fiveHourResets, resets > Date() {
            let r = DateFormatter(); r.dateFormat = "HH:mm"
            text += " · 5-hour window resets at \(r.string(from: resets))"
        }
        return text + " · click to refresh (sends one tiny request)"
    }
}

// MARK: - Shelf

struct ShelfCardView: View {
    @ObservedObject private var appState = AppState.shared
    private let teal = Color(hex: "#2DD4BF")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkillHeader(color: "#2DD4BF", title: "Shelf",
                        subtitle: appState.shelf.isEmpty ? "Empty"
                            : "\(appState.shelf.count) file\(appState.shelf.count == 1 ? "" : "s")",
                        trailingInset: SkillLayout.trailing) {
                if !appState.shelf.isEmpty {
                    SkillIconButton(icon: "trash.fill", size: 16, iconSize: 7) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { ShelfStore.shared.clear() }
                    }
                    .help("Clear the shelf (files stay where they are)")
                }
            }

            if appState.shelf.isEmpty {
                Text("Drop files on the notch to park them here, then drag them out wherever you need them.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
                    .padding(.leading, SkillLayout.leading)
                    .padding(.trailing, SkillLayout.trailing)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(appState.shelf) { item in
                            ShelfTile(item: item)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .padding(.leading, SkillLayout.leading)
                    .padding(.trailing, SkillLayout.trailing)
                    .padding(.vertical, 2)
                }
                .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.shelf)
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    @State private var hovered = false

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
            Text(item.name)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 5)
        .frame(width: 58, height: 56)
        .liquidGlass(shape, tint: Color.black.opacity(hovered ? 0.04 : 0.14), interactive: true,
                     fallback: Color.white.opacity(0.07))
        .glassRim(shape, strength: hovered ? 1 : 0.6, lineWidth: 0.7)
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button { ShelfStore.shared.remove(item) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 6.5, weight: .heavy))
                        .foregroundColor(.black)
                        .frame(width: 13, height: 13)
                        .background(Color.white, in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: -3)
                .transition(.scale.combined(with: .opacity))
                .help("Take off the shelf")
            }
        }
        .scaleEffect(hovered ? 1.05 : 1)
        .contentShape(shape)
        .onTapGesture { ShelfStore.shared.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { ShelfStore.shared.open(item) }
            Button("Show in Finder") { ShelfStore.shared.reveal(item) }
            Divider()
            Button("Take off the shelf") { ShelfStore.shared.remove(item) }
        }
        .help(item.url.path)
        .onHover { h in withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { hovered = h } }
    }
}

// MARK: - Clipboard

struct ClipboardCardView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var copiedId: UUID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkillHeader(color: "#A78BFA", title: "Clipboard",
                        subtitle: appState.clips.isEmpty ? "Nothing copied yet" : "Click to copy",
                        trailingInset: SkillLayout.trailing) {
                if !appState.clips.isEmpty {
                    SkillIconButton(icon: "trash.fill", size: 16, iconSize: 7) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { ClipboardMonitor.shared.clear() }
                    }
                    .help("Forget the history")
                }
            }

            if appState.clips.isEmpty {
                Text("Text you copy shows up here. It stays in memory only, and passwords from password managers are skipped.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 7)
                    .padding(.leading, SkillLayout.leading)
                    .padding(.trailing, SkillLayout.trailing)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(appState.clips) { clip in
                            HubRow(title: clip.preview, detail: copiedId == clip.id ? "Copied" : Self.ago(clip.date),
                                   help: String(clip.text.prefix(400))) {
                                copiedId = clip.id
                                ClipboardMonitor.shared.copy(clip)
                            } leading: {
                                Image(systemName: clip.isLink ? "link" : "text.alignleft")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
                .frame(height: 64)
                .padding(.top, 4)
                .padding(.leading, SkillLayout.leading - 6)
                .padding(.trailing, SkillLayout.trailing - 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: appState.clips.map(\.id))
    }

    private static func ago(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60    { return "now" }
        if diff < 3600  { return "\(Int(diff / 60))m" }
        return "\(Int(diff / 3600))h"
    }
}

// MARK: - Notes

struct NotesCardView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var draft = ""
    @State private var copiedId: UUID? = nil
    @FocusState private var fieldFocused: Bool

    private let accent = Color(hex: "#FB923C")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: the field to jot into sits right next to the title
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text("Notes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .fixedSize()

                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                    TextField("", text: $draft, prompt: Text("Jot it down…").foregroundStyle(.white.opacity(0.5)))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .focused($fieldFocused)
                        .onSubmit(add)
                }
                .padding(.horizontal, 8).frame(height: 22)
                .liquidGlass(Capsule(), fallback: Color.white.opacity(fieldFocused ? 0.1 : 0.06))
                .overlay(Capsule().strokeBorder(accent.opacity(fieldFocused ? 0.55 : 0), lineWidth: 0.8))
                .contentShape(Capsule())
                .onTapGesture {
                    // The island is a non-activating panel: it must be key before it can take text
                    IslandWindowController.shared?.window?.makeKey()
                    fieldFocused = true
                }

                if appState.notes.contains(where: \.done) {
                    SkillIconButton(icon: "checkmark.circle.badge.xmark", size: 16, iconSize: 8) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { NotesStore.shared.clearDone() }
                    }
                    .help("Remove the ticked notes")
                }
            }
            .frame(height: 22)
            .padding(.top, 3)
            .padding(.leading, SkillLayout.leading)
            .padding(.trailing, SkillLayout.trailing)

            if appState.notes.isEmpty {
                Text("A place for the thought you don't want to lose. Press Return to keep it; click a note to copy it.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .padding(.leading, SkillLayout.leading)
                    .padding(.trailing, SkillLayout.trailing)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(appState.notes) { note in
                            NoteRow(note: note, copied: copiedId == note.id) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(note.text, forType: .string)
                                copiedId = note.id
                                SoundEngine.shared.play("pop")
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                }
                .frame(height: 57)
                .padding(.top, 3)
                .padding(.leading, SkillLayout.leading - 6)
                .padding(.trailing, SkillLayout.trailing - 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.notes)
    }

    private func add() {
        NotesStore.shared.add(draft)
        draft = ""
    }
}

private struct NoteRow: View {
    let note: NoteItem
    let copied: Bool
    let copy: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 6) {
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { NotesStore.shared.toggle(note.id) } } label: {
                Image(systemName: note.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(note.done ? Color(hex: "#34D399") : .white.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 14, height: 19)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(note.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(note.done ? 0.45 : (hovered ? 1 : 0.9)))
                .strikethrough(note.done, color: .white.opacity(0.45))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if hovered {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { NotesStore.shared.remove(note.id) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 14, height: 14)
                        .background(Color.white.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            } else {
                Text(copied ? "Copied" : NoteRow.ago(note.date))
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize()
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 19)
        .background(Color.white.opacity(hovered ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: copy)
        .help(note.text)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
    }

    private static func ago(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60     { return "now" }
        if diff < 3600   { return "\(Int(diff / 60))m" }
        if diff < 86400  { return "\(Int(diff / 3600))h" }
        return "\(Int(diff / 86400))d"
    }
}

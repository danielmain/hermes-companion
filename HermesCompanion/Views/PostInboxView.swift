import SwiftUI

// MARK: - Filter Enum

public enum DispatchFilter: String, CaseIterable, Identifiable {
    case all = "ALL"
    case pending = "PENDING"
    case replied = "REPLIED"
    case failed = "FAILED"
    case archived = "ARCHIVE"

    public var id: String { rawValue }

    public func matches(_ status: DispatchStatus) -> Bool {
        switch self {
        case .all: return status != .archived
        case .pending: return status == .pendingAgent
        case .replied: return status == .replied
        case .failed: return status == .failed
        case .archived: return status == .archived
        }
    }
}

// MARK: - Main Post / Inbox View

public struct PostInboxView: View {
    @StateObject private var store = DispatchStore.shared
    @State private var selectedFilter: DispatchFilter = .all
    @State private var searchText: String = ""
    @State private var showingCompose: Bool = false
    @State private var showingPostalDisclaimer: Bool = false
    @AppStorage("hasSeenPostDisclaimer") private var hasSeenPostDisclaimer: Bool = false

    public init() {}

    private var filteredThreads: [DispatchThread] {
        let sourceList = (selectedFilter == .archived) ? store.archivedThreads : store.threads
        return sourceList.filter { thread in
            let matchesFilter = selectedFilter.matches(thread.status)
            if searchText.isEmpty {
                return matchesFilter
            }
            let matchesSearch = thread.subject.localizedCaseInsensitiveContains(searchText) ||
                (thread.lastSnippet?.localizedCaseInsensitiveContains(searchText) ?? false)
            return matchesFilter && matchesSearch
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorialSpacing.large) {
                    EditorialPageHeader(
                        index: "HERMES / POST 04",
                        title: "Hermes\nPost",
                        subtitle: "Private, asynchronous postal channels and letters synchronized with your Hermes agent via iCloud."
                    )

                    actionBarSection

                    filterSegmentedBar

                    if filteredThreads.isEmpty {
                        emptyStateView
                    } else {
                        LazyVStack(spacing: EditorialSpacing.medium) {
                            ForEach(filteredThreads) { thread in
                                NavigationLink(destination: DispatchThreadDetailView(threadId: thread.id)) {
                                    DispatchThreadCard(thread: thread)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, EditorialSpacing.page)
                .padding(.top, EditorialSpacing.large)
                .padding(.bottom, EditorialSpacing.hero)
            }
            .background(EditorialColor.paper)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingCompose) {
                NewDispatchSheetView(isPresented: $showingCompose)
            }
            .sheet(isPresented: $showingPostalDisclaimer) {
                PostalDisclaimerSheetView(isPresented: $showingPostalDisclaimer)
            }
            .refreshable {
                store.loadThreads(force: true)
                store.loadArchivedThreads(force: true)
            }
            .onAppear {
                store.loadThreads()
                store.loadArchivedThreads()
                if !hasSeenPostDisclaimer {
                    showingPostalDisclaimer = true
                }
            }
            .onChange(of: selectedFilter) { _, newFilter in
                if newFilter == .archived {
                    store.loadArchivedThreads()
                }
            }
            .onReceive(Timer.publish(every: 5.0, on: .main, in: .default).autoconnect()) { _ in
                store.loadThreads()
            }
        }
    }

    private var actionBarSection: some View {
        HStack(spacing: EditorialSpacing.small) {
            Button {
                store.loadThreads(force: true)
                if selectedFilter == .archived {
                    store.loadArchivedThreads(force: true)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(EditorialIconButtonStyle())
            .accessibilityLabel("Refresh inbox")

            Button {
                showingPostalDisclaimer = true
            } label: {
                Image(systemName: "info.circle")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(EditorialIconButtonStyle())
            .accessibilityLabel("Postal system explanation")

            Spacer()

            Button {
                showingCompose = true
            } label: {
                HStack(spacing: EditorialSpacing.small) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                    Text("New")
                }
            }
            .buttonStyle(EditorialButtonStyle(isPrimary: true, isFullWidth: false))
            .accessibilityLabel("New letter")
        }
    }

    private var filterSegmentedBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: EditorialSpacing.small) {
                ForEach(DispatchFilter.allCases) { filter in
                    Button {
                        withAnimation(EditorialMotion.quick) {
                            selectedFilter = filter
                        }
                    } label: {
                        EditorialStatusToken(
                            text: filter.rawValue,
                            isInverted: selectedFilter == filter
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, EditorialSpacing.xSmall)
        }
    }

    private var emptyStateView: some View {
        EditorialEmptyState(
            index: "POSTBOX EMPTY",
            title: "No Letters",
            message: "Drop an asynchronous letter or memo to your Hermes agent. Your agent will review and reply into your inbox via iCloud.",
            systemImage: "envelope"
        )
    }
}

// MARK: - Thread Card View

private struct DispatchThreadCard: View {
    let thread: DispatchThread

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            HStack(alignment: .center, spacing: 6) {
                EditorialStatusToken(
                    text: thread.targetProfile.uppercased(),
                    isInverted: false,
                    systemImage: "cpu"
                )

                EditorialStatusToken(
                    text: thread.status.label.uppercased(),
                    isInverted: thread.status == .pendingAgent || thread.status == .failed,
                    systemImage: thread.status == .pendingAgent ? "clock" : (thread.status == .failed ? "exclamationmark.triangle.fill" : (thread.status == .replied ? "checkmark" : "archivebox"))
                )

                Spacer(minLength: 4)

                Text(thread.updatedAt.compactRelativeFormatted)
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(thread.subject)
                .font(.headline)
                .fontWeight(.medium)
                .foregroundStyle(EditorialColor.ink)
                .lineLimit(2)
                .padding(.top, EditorialSpacing.xSmall)

            if let snippet = thread.lastSnippet, !snippet.isEmpty {
                Text(snippet)
                    .font(.editorialBody)
                    .foregroundStyle(EditorialColor.secondaryInk)
                    .lineLimit(2)
            }

            if thread.status == .failed, let error = thread.lastError, !error.isEmpty {
                Text(error)
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)
                    .lineLimit(1)
            }

            EditorialRule()

            HStack {
                Text(thread.id)
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)

                Spacer()

                Text("\(thread.messageCount) \(thread.messageCount == 1 ? "memo" : "memos")")
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.ink)
            }
        }
        .editorialPanel(cutCorner: true)
    }
}

// MARK: - Thread Detail View

public struct DispatchThreadDetailView: View {
    let threadId: String
    @StateObject private var store = DispatchStore.shared
    @State private var messages: [DispatchMessage] = []
    @State private var isSending: Bool = false

    private var currentThread: DispatchThread? {
        store.threads.first(where: { $0.id == threadId }) ?? store.archivedThreads.first(where: { $0.id == threadId })
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: EditorialSpacing.large) {
                    if let thread = currentThread {
                        headerSection(thread)
                    }

                    if messages.isEmpty {
                        EditorialEmptyState(
                            index: "NO MESSAGES",
                            title: "Loading Memos",
                            message: "Fetching thread chronology...",
                            systemImage: "envelope"
                        )
                    } else {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            EditorialMemoCard(
                                message: message,
                                sequenceIndex: index + 1,
                                targetProfile: currentThread?.targetProfile ?? "default"
                            )
                            .id(message.id)
                        }
                    }

                    if let thread = currentThread {
                        if thread.status == .pendingAgent {
                            EditorialInTransitBubble(targetProfile: thread.targetProfile)
                                .id("in_transit_indicator")
                        } else if thread.status == .failed {
                            EditorialFailureBanner(
                                error: thread.lastError,
                                onRetry: {
                                    _ = store.retryThread(id: thread.id)
                                }
                            )
                            .id("failed_banner")
                        } else if thread.status != .archived {
                            ThreadReplySectionView(
                                thread: thread,
                                isSending: isSending,
                                onSend: { text in
                                    sendReply(textToSend: text)
                                }
                            )
                            .id("reply_section")
                        }
                    }
                }
                .padding(.horizontal, EditorialSpacing.page)
                .padding(.top, EditorialSpacing.medium)
                .padding(.bottom, EditorialSpacing.hero)
            }
            .onChange(of: messages.count) { oldCount, newCount in
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: currentThread?.status) { oldStatus, newStatus in
                if newStatus == .pendingAgent {
                    withAnimation {
                        proxy.scrollTo("in_transit_indicator", anchor: .bottom)
                    }
                } else if newStatus == .failed {
                    withAnimation {
                        proxy.scrollTo("failed_banner", anchor: .bottom)
                    }
                }
            }
        }
        .background(EditorialColor.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let thread = currentThread {
                    if thread.status != .archived {
                        Button {
                            store.archiveThread(id: thread.id)
                        } label: {
                            Text("Archive")
                                .font(.editorialUtility)
                                .foregroundStyle(EditorialColor.secondaryInk)
                        }
                    } else {
                        Button {
                            store.unarchiveThread(id: thread.id)
                        } label: {
                            Text("Unarchive")
                                .font(.editorialUtility)
                                .foregroundStyle(EditorialColor.secondaryInk)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadMessages()
        }
        .onReceive(Timer.publish(every: (currentThread?.status == .pendingAgent ? 2.5 : 5.0), on: .main, in: .default).autoconnect()) { _ in
            loadMessages()
        }
    }

    private func headerSection(_ thread: DispatchThread) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            HStack(spacing: EditorialSpacing.small) {
                EditorialStatusToken(
                    text: thread.targetProfile.uppercased(),
                    isInverted: false,
                    systemImage: "cpu"
                )
                EditorialStatusToken(
                    text: thread.status.label.uppercased(),
                    isInverted: thread.status == .pendingAgent || thread.status == .failed,
                    systemImage: thread.status == .pendingAgent ? "paperplane.fill" : (thread.status == .failed ? "exclamationmark.triangle.fill" : (thread.status == .replied ? "checkmark" : "archivebox"))
                )
                Spacer()
                Text(thread.createdAt.compactDateFormatted)
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }

            Text(thread.subject)
                .font(.editorialTitle)
                .lineSpacing(-4)
                .foregroundStyle(EditorialColor.ink)

            EditorialRule(strong: true)
        }
        .padding(.bottom, EditorialSpacing.xSmall)
    }

    private func loadMessages() {
        store.loadMessagesAsync(for: threadId) { result in
            if case .success(let loaded) = result {
                if self.messages != loaded {
                    self.messages = loaded
                }
            }
        }
    }

    private func sendReply(textToSend: String) {
        guard currentThread?.status != .pendingAgent else { return }
        guard !textToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isSending = true
        let result = store.replyToThread(threadId: threadId, body: textToSend, sender: .user)

        DispatchQueue.main.async {
            self.isSending = false
            switch result {
            case .success(let msg):
                self.messages.append(msg)
            case .failure:
                break
            }
        }
    }
}

// MARK: - Dedicated Thread Reply Section

private struct ThreadReplySectionView: View {
    let thread: DispatchThread
    let isSending: Bool
    let onSend: (String) -> Void

    @State private var replyText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reply")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(EditorialColor.ink)

                Spacer()

                HStack(spacing: EditorialSpacing.xSmall) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("iCloud · 5–30m")
                        .font(.editorialUtilitySmall)
                }
                .foregroundStyle(EditorialColor.secondaryInk)
            }

            ZStack(alignment: .topLeading) {
                if replyText.isEmpty {
                    Text("Write a reply...")
                        .font(.system(.body, design: .serif))
                        .italic()
                        .foregroundStyle(EditorialColor.secondaryInk)
                        .padding(.top, EditorialSpacing.small)
                        .padding(.leading, EditorialSpacing.small)
                }

                TextEditor(text: $replyText)
                    .font(.system(.body, design: .serif))
                    .frame(minHeight: 100)
                    .padding(EditorialSpacing.xSmall)
                    .scrollContentBackground(.hidden)
                    .background(EditorialColor.surface)
                    .focused($isInputFocused)
            }
            .overlay {
                Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
            }

            HStack {
                Spacer()

                Button {
                    let text = replyText
                    replyText = ""
                    isInputFocused = false
                    onSend(text)
                } label: {
                    HStack(spacing: EditorialSpacing.small) {
                        if isSending {
                            ProgressView()
                                .tint(EditorialColor.paper)
                            Text("Sending...")
                                .font(.editorialUtility)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.caption.weight(.semibold))
                            Text("Dispatch")
                                .font(.editorialUtility)
                        }
                    }
                }
                .buttonStyle(EditorialButtonStyle(isPrimary: true, isFullWidth: false))
                .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
        }
        .padding(EditorialSpacing.medium)
        .background(EditorialColor.surface)
        .overlay {
            Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
        }
    }
}

// MARK: - Editorial Memo Card (Full-Width Letter Dossier)

private struct EditorialMemoCard: View {
    let message: DispatchMessage
    let sequenceIndex: Int
    let targetProfile: String

    private var isUser: Bool {
        message.sender == .user
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Postal dossier header
            HStack(spacing: EditorialSpacing.small) {
                EditorialStatusToken(
                    text: isUser ? "#\(sequenceIndex) · YOU" : "#\(sequenceIndex) · HERMES",
                    isInverted: !isUser,
                    systemImage: isUser ? "person.fill" : "sparkles"
                )

                Spacer()

                Text(message.timestamp.compactDateFormatted)
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, EditorialSpacing.medium)
            .padding(.top, EditorialSpacing.medium)
            .padding(.bottom, EditorialSpacing.small)

            EditorialRule()

            // Postal memo body
            Text(verbatim: message.body)
                .font(.system(.body, design: .serif))
                .foregroundStyle(EditorialColor.ink)
                .lineSpacing(5)
                .padding(EditorialSpacing.medium)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(isUser ? EditorialColor.userBubble : EditorialColor.agentBubble)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(isUser ? EditorialColor.secondaryInk : EditorialColor.ink)
                .frame(width: isUser ? 2 : 3)
        }
        .clipShape(Rectangle())
        .overlay {
            Rectangle()
                .stroke(isUser ? EditorialColor.hairline : EditorialColor.ink.opacity(0.35), lineWidth: EditorialBorder.hairline)
        }
        .contextMenu {
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = message.body
                #endif
            } label: {
                Label("Copy Letter", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK: - In Transit and Failure State Components

private struct EditorialInTransitBubble: View {
    let targetProfile: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: EditorialSpacing.small) {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(EditorialColor.ink)

                    Text("IN TRANSIT")
                        .font(.editorialUtilitySmall)
                        .lineLimit(1)
                }
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .foregroundStyle(EditorialColor.ink)
                .background(EditorialColor.paper)
                .overlay {
                    Rectangle().stroke(EditorialColor.ink, lineWidth: EditorialBorder.hairline)
                }

                Spacer()

                EditorialStatusToken(
                    text: targetProfile.uppercased(),
                    isInverted: true,
                    systemImage: "sparkles"
                )
            }
            .padding(.horizontal, EditorialSpacing.medium)
            .padding(.top, EditorialSpacing.medium)
            .padding(.bottom, EditorialSpacing.small)

            EditorialRule()

            VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                Text("In transit via iCloud. Your Hermes agent will pick it up and reply shortly (typically 5–30 min).")
                    .font(.system(.body, design: .serif))
                    .italic()
                    .foregroundStyle(EditorialColor.secondaryInk)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(EditorialSpacing.medium)
        }
        .background(EditorialColor.surface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(EditorialColor.hairline)
                .frame(width: 3)
        }
        .clipShape(Rectangle())
        .overlay {
            Rectangle()
                .stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
        }
    }
}

// MARK: - Postal Notice Component

private struct EditorialPostalHint: View {
    var body: some View {
        HStack(spacing: EditorialSpacing.xSmall) {
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(EditorialColor.secondaryInk)

            Text("iCloud postal relay · 5–30 min")
                .font(.editorialUtilitySmall)
                .foregroundStyle(EditorialColor.secondaryInk)

            Spacer()
        }
    }
}

private struct EditorialFailureBanner: View {
    let error: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            HStack(spacing: EditorialSpacing.small) {
                EditorialStatusToken(
                    text: "TRANSMISSION FAILED",
                    isInverted: true,
                    systemImage: "exclamationmark.triangle.fill"
                )
                Spacer()
            }

            Text(error ?? "Agent execution failed or timed out while drafting correspondence.")
                .font(.editorialBody)
                .foregroundStyle(EditorialColor.ink)

            HStack {
                Button(action: onRetry) {
                    HStack(spacing: EditorialSpacing.small) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                        Text("Retry")
                    }
                }
                .buttonStyle(EditorialButtonStyle(isPrimary: true, isFullWidth: false))

                Spacer()
            }
            .padding(.top, EditorialSpacing.xSmall)
        }
        .editorialPanel(emphasized: true)
    }
}

// MARK: - Postal Disclaimer Sheet

public struct PostalDisclaimerSheetView: View {
    @Binding var isPresented: Bool
    @AppStorage("hasSeenPostDisclaimer") private var hasSeenPostDisclaimer: Bool = false

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorialSpacing.large) {
                    EditorialPageHeader(
                        index: "HERMES / DISPATCH 01",
                        title: "Hermes\nPostbox",
                        subtitle: "Asynchronous epistolar relay protocol via iCloud Drive."
                    )

                    VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
                        infoCard(
                            badge: "ASYNC PROTOCOL",
                            title: "Postal Letters, Not Live Chat",
                            description: "Hermes Post operates on a physical postal letter model: you drop a letter, it travels through iCloud synchronization envelopes, and your agent composes a reply once delivered. It is not real-time instant messaging.",
                            icon: "envelope.badge.shield.half.filled"
                        )

                        infoCard(
                            badge: "SYSTEM PURPOSE",
                            title: "Designed for Offline & Non-P2P Links",
                            description: "This relay is an autonomous bridge for when you are away from home or cannot establish a direct P2P (Tailscale or local Wi-Fi) connection to your Mac. It consumes zero idle tokens and requires no intermediary servers.",
                            icon: "antenna.radiowaves.left.and.right"
                        )

                        infoCard(
                            badge: "DELIVERY CADENCE",
                            title: "5–30 Minute Transit Rhythm",
                            description: "Due to Apple CloudKit sync schedules and iOS background battery optimization, letters and agent responses typically take 5 to 30 minutes. Dispatch your thoughts and check back later.",
                            icon: "clock.arrow.circlepath"
                        )
                    }

                    Button {
                        hasSeenPostDisclaimer = true
                        isPresented = false
                    } label: {
                        HStack {
                            Spacer()
                            Text("Continue")
                                .font(.editorialUtility)
                            Spacer()
                        }
                    }
                    .buttonStyle(EditorialButtonStyle(isPrimary: true))
                    .padding(.top, EditorialSpacing.small)
                }
                .padding(.horizontal, EditorialSpacing.page)
                .padding(.vertical, EditorialSpacing.large)
            }
            .background(EditorialColor.paper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        hasSeenPostDisclaimer = true
                        isPresented = false
                    }
                    .font(.editorialUtility)
                    .foregroundStyle(EditorialColor.ink)
                }
            }
        }
    }

    private func infoCard(badge: String, title: String, description: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: EditorialSpacing.small) {
            HStack(spacing: EditorialSpacing.small) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(EditorialColor.ink)
                EditorialStatusToken(text: badge, isInverted: false)
            }

            Text(title)
                .font(.headline)
                .foregroundStyle(EditorialColor.ink)

            Text(description)
                .font(.editorialBody)
                .foregroundStyle(EditorialColor.secondaryInk)
                .lineSpacing(3)
        }
        .padding(EditorialSpacing.medium)
        .background(EditorialColor.surface)
        .overlay {
            Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
        }
    }
}

// MARK: - New Dispatch Sheet

public struct NewDispatchSheetView: View {
    @Binding var isPresented: Bool
    @StateObject private var store = DispatchStore.shared
    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var selectedProfile: String = "default"
    @State private var errorMessage: String?
    @State private var showingCustomProfileAlert: Bool = false
    @State private var customProfileInput: String = ""

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: EditorialSpacing.large) {
                    EditorialPageHeader(
                        index: "HERMES POST",
                        title: "Compose\nLetter",
                        subtitle: "Drop an asynchronous letter or inquiry into your agent's inbox."
                    )

                    VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
                        VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                            Text("TARGET AGENT PROFILE")
                                .font(.editorialUtility)
                                .tracking(1.0)
                                .foregroundStyle(EditorialColor.secondaryInk)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: EditorialSpacing.small) {
                                    ForEach(store.availableProfiles) { profile in
                                        Button {
                                            selectedProfile = profile.id
                                        } label: {
                                            EditorialStatusToken(
                                                text: profile.name.uppercased(),
                                                isInverted: selectedProfile == profile.id,
                                                systemImage: "cpu"
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }

                                    Button {
                                        customProfileInput = ""
                                        showingCustomProfileAlert = true
                                    } label: {
                                        EditorialStatusToken(
                                            text: "+ PROFILE",
                                            isInverted: false,
                                            systemImage: "plus"
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.vertical, EditorialSpacing.xSmall)
                            }
                        }

                        EditorialField(
                            label: "SUBJECT / TOPIC",
                            prompt: "e.g. Weekly Movement Summary",
                            text: $subject
                        )

                        VStack(alignment: .leading, spacing: EditorialSpacing.xSmall) {
                            Text("LETTER BODY")
                                .font(.editorialUtility)
                                .tracking(1.0)
                                .foregroundStyle(EditorialColor.secondaryInk)

                            TextEditor(text: $bodyText)
                                .frame(minHeight: 180)
                                .padding(EditorialSpacing.small)
                                .background(EditorialColor.surface)
                                .overlay {
                                    Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
                                }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Color.red)
                        }

                        EditorialPostalHint()
                            .padding(.vertical, EditorialSpacing.xSmall)

                        Button("Send") {
                            transmit()
                        }
                        .buttonStyle(EditorialButtonStyle(isPrimary: true))
                        .disabled(subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .editorialPanel()
                }
                .padding(.horizontal, EditorialSpacing.page)
                .padding(.top, EditorialSpacing.large)
                .padding(.bottom, EditorialSpacing.hero)
            }
            .background(EditorialColor.paper)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .font(.editorialUtility)
                    .foregroundStyle(EditorialColor.ink)
                }
            }
            .onAppear {
                if let first = store.availableProfiles.first {
                    selectedProfile = first.id
                }
            }
            .alert("Address to Agent Profile", isPresented: $showingCustomProfileAlert) {
                TextField("e.g. love, work, health", text: $customProfileInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add & Select") {
                    let trimmed = customProfileInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !trimmed.isEmpty {
                        store.registerCustomProfile(id: trimmed)
                        selectedProfile = trimmed
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter the name of your Hermes profile. It will be added to your profile list.")
            }
        }
    }

    private func transmit() {
        let result = store.createThread(subject: subject, initialBody: bodyText, targetProfile: selectedProfile)
        switch result {
        case .success:
            isPresented = false
        case .failure(let error):
            self.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Backwards Compatibility
public typealias DispatchesView = PostInboxView

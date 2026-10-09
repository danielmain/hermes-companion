import SwiftUI

// MARK: - Filter Enum

public enum DispatchFilter: String, CaseIterable, Identifiable {
    case all = "ALL"
    case pending = "AWAITING"
    case replied = "REPLIED"
    case archived = "ARCHIVED"

    public var id: String { rawValue }

    public func matches(_ status: DispatchStatus) -> Bool {
        switch self {
        case .all: return true
        case .pending: return status == .pendingAgent
        case .replied: return status == .replied
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

    public init() {}

    private var filteredThreads: [DispatchThread] {
        store.threads.filter { thread in
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
            .refreshable {
                store.loadThreads()
            }
            .onAppear {
                store.loadThreads()
            }
            .onReceive(Timer.publish(every: 5.0, on: .main, in: .common).autoconnect()) { _ in
                store.loadThreads()
            }
        }
    }

    private var actionBarSection: some View {
        HStack(spacing: EditorialSpacing.small) {
            Button {
                store.loadThreads()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(EditorialIconButtonStyle())
            .accessibilityLabel("Refresh inbox")

            Spacer()

            Button {
                showingCompose = true
            } label: {
                HStack(spacing: EditorialSpacing.small) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                    Text("NEW LETTER")
                }
            }
            .buttonStyle(EditorialButtonStyle(isPrimary: true))
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
            HStack(alignment: .firstTextBaseline, spacing: EditorialSpacing.small) {
                EditorialStatusToken(
                    text: thread.targetProfile.uppercased(),
                    isInverted: false,
                    systemImage: "cpu"
                )

                EditorialStatusToken(
                    text: thread.status.label.uppercased(),
                    isInverted: thread.status == .pendingAgent,
                    systemImage: thread.status == .pendingAgent ? "clock" : (thread.status == .replied ? "checkmark" : "archivebox")
                )

                Spacer()

                Text(thread.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)
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
    @State private var replyText: String = ""
    @State private var isSending: Bool = false
    @FocusState private var isInputFocused: Bool

    private var currentThread: DispatchThread? {
        store.threads.first(where: { $0.id == threadId })
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: EditorialSpacing.medium) {
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
                            LazyVStack(spacing: EditorialSpacing.medium) {
                                ForEach(messages) { message in
                                    DispatchMessageBubble(message: message)
                                        .id(message.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, EditorialSpacing.page)
                    .padding(.top, EditorialSpacing.medium)
                    .padding(.bottom, EditorialSpacing.large)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            EditorialRule()

            replyComposerBar
        }
        .background(EditorialColor.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let thread = currentThread, thread.status != .archived {
                    Button {
                        store.archiveThread(id: thread.id)
                    } label: {
                        Text("Archive")
                            .font(.editorialUtility)
                            .foregroundStyle(EditorialColor.secondaryInk)
                    }
                }
            }
        }
        .onAppear {
            loadMessages()
        }
        .onReceive(Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()) { _ in
            loadMessages()
            store.loadThreads()
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
                    isInverted: thread.status == .pendingAgent
                )
                Spacer()
                Text(thread.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.editorialUtilitySmall)
                    .foregroundStyle(EditorialColor.secondaryInk)
            }

            Text(thread.subject)
                .font(.editorialTitle)
                .lineSpacing(-4)
                .foregroundStyle(EditorialColor.ink)

            EditorialRule(strong: true)
        }
        .padding(.bottom, EditorialSpacing.small)
    }

    private var replyComposerBar: some View {
        VStack(spacing: EditorialSpacing.small) {
            HStack(alignment: .bottom, spacing: EditorialSpacing.small) {
                TextField("Compose reply letter...", text: $replyText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(EditorialSpacing.small)
                    .background(EditorialColor.surface)
                    .overlay {
                        Rectangle().stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
                    }
                    .focused($isInputFocused)

                Button {
                    sendReply()
                } label: {
                    if isSending {
                        ProgressView()
                            .tint(EditorialColor.paper)
                            .frame(width: 44, height: 44)
                            .background(EditorialColor.ink)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.bold))
                            .foregroundStyle(EditorialColor.paper)
                            .frame(width: 44, height: 44)
                            .background(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? EditorialColor.secondaryInk : EditorialColor.ink)
                    }
                }
                .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
        }
        .padding(EditorialSpacing.medium)
        .background(EditorialColor.paper)
    }

    private func loadMessages() {
        let result = store.loadMessages(for: threadId)
        if case .success(let loaded) = result {
            if loaded.count != self.messages.count || loaded.last?.id != self.messages.last?.id {
                self.messages = loaded
            }
        }
    }

    private func sendReply() {
        let textToSend = replyText
        guard !textToSend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isSending = true
        let result = store.replyToThread(threadId: threadId, body: textToSend, sender: .user)

        DispatchQueue.main.async {
            self.isSending = false
            switch result {
            case .success(let msg):
                self.messages.append(msg)
                self.replyText = ""
                self.isInputFocused = false
            case .failure:
                break
            }
        }
    }
}

// MARK: - Message Bubble / Memo Card

private struct DispatchMessageBubble: View {
    let message: DispatchMessage

    private var isUser: Bool {
        message.sender == .user
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: EditorialSpacing.large)
            }

            VStack(alignment: .leading, spacing: EditorialSpacing.small) {
                HStack {
                    EditorialStatusToken(
                        text: isUser ? "YOU" : "HERMES AGENT",
                        isInverted: !isUser,
                        systemImage: isUser ? "person.fill" : "sparkles"
                    )

                    Spacer()

                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.editorialUtilitySmall)
                        .foregroundStyle(EditorialColor.secondaryInk)
                }

                Text(LocalizedStringKey(message.body))
                    .font(isUser ? .editorialBody : .system(.body, design: .serif))
                    .foregroundStyle(EditorialColor.ink)
                    .lineSpacing(isUser ? 3 : 5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(EditorialSpacing.medium)
            .background(isUser ? EditorialColor.surface : EditorialColor.paper)
            .overlay(alignment: .leading) {
                if !isUser {
                    Rectangle()
                        .fill(EditorialColor.ink)
                        .frame(width: 3)
                }
            }
            .clipShape(isUser ? AnyShape(CutCornerShape()) : AnyShape(Rectangle()))
            .overlay {
                if isUser {
                    CutCornerShape()
                        .stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
                } else {
                    Rectangle()
                        .stroke(EditorialColor.hairline, lineWidth: EditorialBorder.hairline)
                }
            }

            if !isUser {
                Spacer(minLength: EditorialSpacing.compact)
            }
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

                        Button("Drop to Postbox") {
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

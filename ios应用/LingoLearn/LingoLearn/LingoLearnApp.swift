import SwiftUI
import SwiftData
import AVFoundation
import Charts
import UIKit

// MARK: - Theme

private enum AppTheme {
    static let primary = Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255) // #0EA5E9
    static let accent = Color(red: 20 / 255, green: 184 / 255, blue: 166 / 255) // #14B8A6
    static let warning = Color.orange
    static let success = Color.green
    static let error = Color.red

    static let cardGradient = LinearGradient(
        colors: [primary.opacity(0.9), accent.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Models

enum WordLevel: String, Codable, CaseIterable, Identifiable {
    case cet4 = "CET4"
    case cet6 = "CET6"

    var id: String { rawValue }
}

enum MasteryState: String, Codable, CaseIterable, Identifiable {
    case newWord = "new"
    case learning = "learning"
    case mastered = "mastered"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newWord: return "新学"
        case .learning: return "学习中"
        case .mastered: return "已掌握"
        }
    }
}

enum StudyMode: String, Codable {
    case learn
    case review
    case test
}

enum PracticeType: String, CaseIterable, Identifiable {
    case multipleChoice
    case fillBlank
    case listening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .multipleChoice: return "选择题"
        case .fillBlank: return "填空题"
        case .listening: return "听力题"
        }
    }

    var subtitle: String {
        switch self {
        case .multipleChoice: return "英文词汇 -> 选择中文释义"
        case .fillBlank: return "中文提示 -> 输入英文单词"
        case .listening: return "听发音 -> 选择正确单词"
        }
    }
}

enum ProgressRange: Int, CaseIterable, Identifiable {
    case days7 = 7
    case days30 = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .days7: return "近7天"
        case .days30: return "近30天"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@Model
final class WordItem {
    @Attribute(.unique) var english: String
    var id: UUID
    var phonetic: String
    var meaning: String
    var example: String
    var levelRaw: String
    var masteryRaw: String
    var isFavorite: Bool
    var efactor: Double
    var intervalDays: Int
    var repetitions: Int
    var dueDate: Date
    var lastReviewedAt: Date?
    var createdAt: Date

    init(english: String, phonetic: String, meaning: String, example: String, levelRaw: String) {
        self.id = UUID()
        self.english = english
        self.phonetic = phonetic
        self.meaning = meaning
        self.example = example
        self.levelRaw = levelRaw
        self.masteryRaw = MasteryState.newWord.rawValue
        self.isFavorite = false
        self.efactor = 2.5
        self.intervalDays = 1
        self.repetitions = 0
        self.dueDate = .now
        self.lastReviewedAt = nil
        self.createdAt = .now
    }

    var level: WordLevel {
        get { WordLevel(rawValue: levelRaw) ?? .cet4 }
        set { levelRaw = newValue.rawValue }
    }

    var mastery: MasteryState {
        get { MasteryState(rawValue: masteryRaw) ?? .newWord }
        set { masteryRaw = newValue.rawValue }
    }
}

@Model
final class StudyRecord {
    var id: UUID
    var date: Date
    var modeRaw: String
    var correct: Bool
    var duration: Double
    var word: String

    init(date: Date, modeRaw: String, correct: Bool, duration: Double, word: String) {
        self.id = UUID()
        self.date = date
        self.modeRaw = modeRaw
        self.correct = correct
        self.duration = duration
        self.word = word
    }

    var mode: StudyMode {
        get { StudyMode(rawValue: modeRaw) ?? .learn }
        set { modeRaw = newValue.rawValue }
    }
}

@Model
final class AchievementUnlock {
    @Attribute(.unique) var key: String
    var unlockedAt: Date

    init(key: String, unlockedAt: Date = .now) {
        self.key = key
        self.unlockedAt = unlockedAt
    }
}

@Model
final class UserSettings {
    @Attribute(.unique) var singletonKey: String
    var dailyGoal: Int
    var reminderEnabled: Bool
    var reminderTime: Date
    var soundEnabled: Bool
    var hapticsEnabled: Bool
    var autoPlayPronunciation: Bool
    var appearanceRaw: String
    var perQuestionSeconds: Int
    var practiceQuestionCountRaw: Int?

    init() {
        self.singletonKey = "default"
        self.dailyGoal = 30
        self.reminderEnabled = false
        self.reminderTime = Calendar.current.date(from: DateComponents(hour: 20, minute: 0)) ?? .now
        self.soundEnabled = true
        self.hapticsEnabled = true
        self.autoPlayPronunciation = true
        self.appearanceRaw = AppearanceMode.system.rawValue
        self.perQuestionSeconds = 15
        self.practiceQuestionCountRaw = 10
    }

    var appearance: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var practiceQuestionCount: Int {
        get { max(5, min(practiceQuestionCountRaw ?? 10, 60)) }
        set { practiceQuestionCountRaw = max(5, min(newValue, 60)) }
    }
}

struct SeedWord: Codable {
    let english: String
    let phonetic: String
    let meaning: String
    let example: String
    let level: String
}

// MARK: - App Models

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: Int = 0
    @Published var bootstrapState: BootstrapState = .idle
}

enum BootstrapState {
    case idle
    case loading
    case ready
    case failed(String)
}

struct DayStudyStat: Identifiable {
    let id = UUID()
    let date: Date
    let count: Int
}

struct MasterySlice: Identifiable {
    let id = UUID()
    let state: MasteryState
    let count: Int
}

struct AchievementDefinition: Identifiable {
    let key: String
    let title: String
    let subtitle: String
    let icon: String

    var id: String { key }
}

struct PracticeQuestion: Identifiable {
    let id = UUID()
    let type: PracticeType
    let word: String
    let prompt: String
    let answer: String
    let options: [String]
    let helperMeaning: String
}

struct WrongAnswerItem: Identifiable {
    let id = UUID()
    let word: String
    let meaning: String
    let correctAnswer: String
}

// MARK: - Services

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium, enabled: Bool) {
        guard enabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }

    static func success(enabled: Bool) {
        guard enabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    static func error(enabled: Bool) {
        guard enabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
}

final class TTSService {
    static let shared = TTSService()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {}

    func speak(_ text: String, enabled: Bool = true) {
        guard enabled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.47
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}

struct SM2Scheduler {
    static func review(word: WordItem, quality inputQuality: Int, now: Date = .now) {
        let quality = max(0, min(5, inputQuality))
        var repetitions = word.repetitions
        var interval = word.intervalDays
        var efactor = word.efactor

        if quality < 3 {
            repetitions = 0
            interval = 1
        } else {
            repetitions += 1
            switch repetitions {
            case 1: interval = 1
            case 2: interval = 6
            default:
                interval = max(1, Int((Double(interval) * efactor).rounded()))
            }
        }

        let delta = 0.1 - Double(5 - quality) * (0.08 + Double(5 - quality) * 0.02)
        efactor = max(1.3, efactor + delta)

        word.repetitions = repetitions
        word.intervalDays = interval
        word.efactor = efactor
        word.lastReviewedAt = now
        word.dueDate = Calendar.current.date(byAdding: .day, value: interval, to: now) ?? now

        if repetitions >= 6 {
            word.mastery = .mastered
        } else if repetitions >= 2 {
            word.mastery = .learning
        } else {
            word.mastery = .newWord
        }
    }
}

@MainActor
struct AchievementEngine {
    static let all: [AchievementDefinition] = [
        .init(key: "first_study", title: "首次学习", subtitle: "完成第一条学习记录", icon: "sparkles"),
        .init(key: "streak_7", title: "连续7天", subtitle: "连续学习7天", icon: "flame.fill"),
        .init(key: "mastered_100", title: "掌握100词", subtitle: "掌握词汇达到100", icon: "brain.head.profile"),
        .init(key: "review_200", title: "学习达人", subtitle: "累计完成200次练习", icon: "bolt.badge.clock"),
        .init(key: "perfect_10", title: "测验满分", subtitle: "一次测验10题全对", icon: "checkmark.seal.fill")
    ]

    static func evaluate(
        words: [WordItem],
        records: [StudyRecord],
        achievements: [AchievementUnlock],
        modelContext: ModelContext,
        latestSessionCorrect: Int? = nil,
        latestSessionTotal: Int? = nil
    ) -> AchievementDefinition? {
        let unlocked = Set(achievements.map(\.key))
        let streak = StudyAnalytics.streakDays(from: records)
        let masteredCount = words.filter { $0.mastery == .mastered }.count

        for definition in all where !unlocked.contains(definition.key) {
            let shouldUnlock: Bool
            switch definition.key {
            case "first_study":
                shouldUnlock = !records.isEmpty
            case "streak_7":
                shouldUnlock = streak >= 7
            case "mastered_100":
                shouldUnlock = masteredCount >= 100
            case "review_200":
                shouldUnlock = records.count >= 200
            case "perfect_10":
                shouldUnlock = (latestSessionCorrect == 10 && latestSessionTotal == 10)
            default:
                shouldUnlock = false
            }

            if shouldUnlock {
                let unlock = AchievementUnlock(key: definition.key)
                modelContext.insert(unlock)
                try? modelContext.save()
                return definition
            }
        }

        return nil
    }
}

struct StudyAnalytics {
    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }

    static func todayCount(records: [StudyRecord]) -> Int {
        records.filter { isSameDay($0.date, .now) }.count
    }

    static func streakDays(from records: [StudyRecord]) -> Int {
        let calendar = Calendar.current
        let uniqueDays = Set(records.map { calendar.startOfDay(for: $0.date) })
        guard !uniqueDays.isEmpty else { return 0 }

        var streak = 0
        var cursor = calendar.startOfDay(for: .now)

        while uniqueDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
    }

    static func lineStats(records: [StudyRecord], range: ProgressRange) -> [DayStudyStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        let counts: [Date: Int] = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.count }

        return (0..<range.rawValue).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -(range.rawValue - 1 - offset), to: today) else {
                return nil
            }
            return DayStudyStat(date: day, count: counts[day, default: 0])
        }
    }

    static func heatmapStats(records: [StudyRecord], days: Int = 84) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        let counts: [Date: Int] = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.count }

        return (0..<days).compactMap { index in
            guard let day = calendar.date(byAdding: .day, value: -(days - 1 - index), to: today) else {
                return nil
            }
            return (date: day, count: counts[day, default: 0])
        }
    }
}

// MARK: - Bootstrap

@MainActor
struct DataBootstrapper {
    static func bootstrapIfNeeded(modelContext: ModelContext) throws {
        let settingsDescriptor = FetchDescriptor<UserSettings>()
        let existingSettings = try modelContext.fetch(settingsDescriptor)
        if existingSettings.isEmpty {
            modelContext.insert(UserSettings())
        } else {
            for settings in existingSettings where settings.practiceQuestionCountRaw == nil {
                settings.practiceQuestionCountRaw = 10
            }
        }

        let wordsDescriptor = FetchDescriptor<WordItem>()
        let existingWords = try modelContext.fetch(wordsDescriptor)

        let url = Bundle.main.url(forResource: "SeedWords", withExtension: "json")
            ?? Bundle.main.url(forResource: "SeedWords", withExtension: "json", subdirectory: "Resources")

        guard let url else {
            throw NSError(domain: "LingoLearn", code: 404, userInfo: [NSLocalizedDescriptionKey: "找不到 SeedWords.json"])
        }

        let data = try Data(contentsOf: url)
        let seedWords = try JSONDecoder().decode([SeedWord].self, from: data)
        var existingMap = Dictionary(uniqueKeysWithValues: existingWords.map { ($0.english.lowercased(), $0) })

        for item in seedWords {
            let key = item.english.lowercased()
            if let existing = existingMap[key] {
                // Keep学习进度字段，仅同步词条内容。
                existing.phonetic = item.phonetic
                existing.meaning = item.meaning
                existing.example = item.example
                existing.levelRaw = item.level
            } else {
                let word = WordItem(
                    english: key,
                    phonetic: item.phonetic,
                    meaning: item.meaning,
                    example: item.example,
                    levelRaw: item.level
                )
                modelContext.insert(word)
                existingMap[key] = word
            }
        }

        try modelContext.save()
    }
}

// MARK: - App Entry

@main
struct LingoLearnApp: App {
    @StateObject private var appState = AppState()

    private var modelContainer: ModelContainer = {
        let schema = Schema([
            WordItem.self,
            StudyRecord.self,
            AchievementUnlock.self,
            UserSettings.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer 初始化失败: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(appState)
        }
        .modelContainer(modelContainer)
    }
}

struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @Query private var settings: [UserSettings]

    var body: some View {
        Group {
            switch appState.bootstrapState {
            case .idle, .loading:
                LoadingStateView(title: "正在准备词库", subtitle: "首次启动会加载 500+ 预置单词")
            case .ready:
                RootTabView()
            case .failed(let message):
                ErrorStateView(
                    title: "初始化失败",
                    subtitle: message,
                    buttonTitle: "重试"
                ) {
                    bootstrap()
                }
            }
        }
        .preferredColorScheme(settings.first?.appearance.colorScheme)
        .task {
            bootstrap()
        }
    }

    private func bootstrap() {
        appState.bootstrapState = .loading
        do {
            try DataBootstrapper.bootstrapIfNeeded(modelContext: modelContext)
            appState.bootstrapState = .ready
        } catch {
            appState.bootstrapState = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Root Tabs

struct RootTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }
                .tag(0)

            LearnView()
                .tabItem {
                    Label("学习", systemImage: "rectangle.on.rectangle.angled")
                }
                .tag(1)

            PracticeHubView()
                .tabItem {
                    Label("练习", systemImage: "pencil.and.list.clipboard")
                }
                .tag(2)

            ProgressDashboardView()
                .tabItem {
                    Label("进度", systemImage: "chart.xyaxis.line")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(AppTheme.primary)
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    @Query(sort: \WordItem.createdAt) private var words: [WordItem]
    @Query(sort: \StudyRecord.date, order: .reverse) private var records: [StudyRecord]
    @Query private var settings: [UserSettings]

    private var todayProgress: Int { StudyAnalytics.todayCount(records: records) }
    private var dailyGoal: Int { settings.first?.dailyGoal ?? 30 }
    private var dueCount: Int { words.filter { $0.dueDate <= .now }.count }
    private var streakDays: Int { StudyAnalytics.streakDays(from: records) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 14) {
                        ProgressRingView(progress: min(Double(todayProgress) / Double(max(dailyGoal, 1)), 1.0), lineWidth: 14)
                            .frame(width: 170, height: 170)
                            .overlay {
                                VStack(spacing: 4) {
                                    Text("\(todayProgress)/\(dailyGoal)")
                                        .font(.system(size: 26, weight: .bold))
                                    Text("今日进度")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                        HStack(spacing: 8) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(.orange)
                            Text("连续打卡 \(streakDays) 天")
                                .font(.headline)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    HStack(spacing: 14) {
                        QuickActionCard(
                            title: "开始学习",
                            subtitle: "新词 + 复习",
                            icon: "play.circle.fill",
                            color: AppTheme.primary
                        ) {
                            Haptics.impact(.medium, enabled: settings.first?.hapticsEnabled ?? true)
                            appState.selectedTab = 1
                        }

                        QuickActionCard(
                            title: "快速复习",
                            subtitle: "到期词汇",
                            icon: "arrow.clockwise.circle.fill",
                            color: AppTheme.accent,
                            badge: dueCount
                        ) {
                            Haptics.impact(.medium, enabled: settings.first?.hapticsEnabled ?? true)
                            appState.selectedTab = 1
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                NotificationCenter.default.post(name: .startReviewOnly, object: nil)
                            }
                        }

                        QuickActionCard(
                            title: "随机测试",
                            subtitle: "10题冲刺",
                            icon: "shuffle.circle.fill",
                            color: .indigo
                        ) {
                            Haptics.impact(.medium, enabled: settings.first?.hapticsEnabled ?? true)
                            appState.selectedTab = 2
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                NotificationCenter.default.post(name: .startRandomQuiz, object: nil)
                            }
                        }
                    }

                    if dueCount > 0 {
                        HStack {
                            Label("待复习单词", systemImage: "bell.badge.fill")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(dueCount)")
                                .font(.headline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppTheme.warning.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        .padding()
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if words.isEmpty {
                        EmptyStateView(
                            title: "词库为空",
                            subtitle: "请在设置中重置数据，或检查预置词库文件"
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("LingoLearn")
        }
    }
}

// MARK: - Learn

struct LearnView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WordItem.createdAt) private var words: [WordItem]
    @Query(sort: \StudyRecord.date, order: .reverse) private var records: [StudyRecord]
    @Query private var settings: [UserSettings]
    @Query private var achievements: [AchievementUnlock]

    @State private var sessionWords: [WordItem] = []
    @State private var currentIndex: Int = 0
    @State private var isFlipped: Bool = false
    @State private var dragOffset: CGSize = .zero
    @State private var reviewOnly: Bool = false

    @State private var knownCount: Int = 0
    @State private var unknownCount: Int = 0
    @State private var favoriteCount: Int = 0
    @State private var processedCount: Int = 0
    @State private var showRoundSummary: Bool = false

    @State private var unlockedAchievement: AchievementDefinition?

    private var hapticsEnabled: Bool { settings.first?.hapticsEnabled ?? true }
    private var soundEnabled: Bool { settings.first?.soundEnabled ?? true }
    private var autoPlay: Bool { settings.first?.autoPlayPronunciation ?? true }

    private var currentWord: WordItem? {
        guard currentIndex >= 0, currentIndex < sessionWords.count else { return nil }
        return sessionWords[currentIndex]
    }

    private var displayIndex: Int {
        guard !sessionWords.isEmpty else { return 0 }
        return min(currentIndex + 1, sessionWords.count)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                header

                if let word = currentWord {
                    FlashcardView(word: word, isFlipped: isFlipped, dragOffset: dragOffset)
                        .frame(maxWidth: .infinity, maxHeight: 380)
                        .gesture(dragGesture)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                isFlipped.toggle()
                            }
                            Haptics.impact(.light, enabled: hapticsEnabled)
                        }
                        .overlay(alignment: .topTrailing) {
                            Button {
                                TTSService.shared.speak(word.english, enabled: soundEnabled)
                                Haptics.impact(.light, enabled: hapticsEnabled)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(.black.opacity(0.3), in: Circle())
                            }
                            .padding(16)
                        }

                    SwipeHintView()
                } else {
                    EmptyStateView(
                        title: reviewOnly ? "当前没有到期复习" : "本轮学习完成",
                        subtitle: reviewOnly ? "返回首页继续学习新词，或稍后再来" : "已完成本组学习，可刷新新一组"
                    )
                    .frame(maxHeight: .infinity)
                }

                Button {
                    refreshSession(resetRound: true)
                } label: {
                    Label("刷新学习卡组", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
            }
            .padding()
            .navigationTitle("单词学习")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(reviewOnly ? "全部" : "仅复习") {
                        reviewOnly.toggle()
                        refreshSession(resetRound: true)
                    }
                }
            }
            .alert("本轮统计", isPresented: $showRoundSummary) {
                Button("继续") {}
            } message: {
                Text("认识：\(knownCount)\n不认识：\(unknownCount)\n收藏：\(favoriteCount)")
            }
            .overlay(alignment: .top) {
                if let unlockedAchievement {
                    AchievementToast(definition: unlockedAchievement)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                                withAnimation(.spring()) {
                                    self.unlockedAchievement = nil
                                }
                            }
                        }
                }
            }
            .onAppear {
                refreshSession(resetRound: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .startReviewOnly)) { _ in
                reviewOnly = true
                refreshSession(resetRound: true)
            }
            .onChange(of: currentIndex) { _, _ in
                if autoPlay, let word = currentWord {
                    TTSService.shared.speak(word.english, enabled: soundEnabled)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(reviewOnly ? "复习模式" : "学习模式")
                    .font(.headline)
                Text("\(displayIndex)/\(sessionWords.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                statBadge(title: "认识", value: knownCount, color: AppTheme.success)
                statBadge(title: "不认识", value: unknownCount, color: AppTheme.error)
            }
        }
    }

    private func statBadge(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let translation = value.translation

                if translation.width > 130 {
                    handleReview(quality: 4, correct: true)
                } else if translation.width < -130 {
                    handleReview(quality: 1, correct: false)
                } else if translation.height < -130 {
                    handleFavorite()
                }

                withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
                    dragOffset = .zero
                }
            }
    }

    private func refreshSession(resetRound: Bool) {
        let dueWords = words.filter { $0.dueDate <= .now }
        let newWords = words.filter { $0.mastery == .newWord }

        let pool: [WordItem]
        if reviewOnly {
            pool = dueWords
        } else {
            let combined = (dueWords + newWords)
            var seen = Set<String>()
            pool = combined.filter { seen.insert($0.english).inserted }
        }

        let sessionSize = min(max(settings.first?.dailyGoal ?? 30, 30), 80)
        sessionWords = Array(pool.shuffled().prefix(sessionSize))
        currentIndex = 0
        isFlipped = false

        if resetRound {
            knownCount = 0
            unknownCount = 0
            favoriteCount = 0
            processedCount = 0
        }
    }

    private func handleReview(quality: Int, correct: Bool) {
        guard let word = currentWord else { return }

        SM2Scheduler.review(word: word, quality: quality)
        let record = StudyRecord(
            date: .now,
            modeRaw: (reviewOnly ? StudyMode.review : StudyMode.learn).rawValue,
            correct: correct,
            duration: 1,
            word: word.english
        )
        modelContext.insert(record)

        if correct {
            knownCount += 1
            Haptics.success(enabled: hapticsEnabled)
        } else {
            unknownCount += 1
            Haptics.error(enabled: hapticsEnabled)
        }

        processedCount += 1

        if let achievement = AchievementEngine.evaluate(
            words: words,
            records: records + [record],
            achievements: achievements,
            modelContext: modelContext
        ) {
            withAnimation(.spring()) {
                unlockedAchievement = achievement
            }
        }

        try? modelContext.save()
        moveNext()
    }

    private func handleFavorite() {
        guard let word = currentWord else { return }
        word.isFavorite.toggle()
        if word.isFavorite { favoriteCount += 1 }
        Haptics.impact(.rigid, enabled: hapticsEnabled)
        try? modelContext.save()
        moveNext()
    }

    private func moveNext() {
        isFlipped = false

        if currentIndex < sessionWords.count - 1 {
            currentIndex += 1
        } else {
            currentIndex = sessionWords.count
        }

        if processedCount > 0, processedCount % 10 == 0 {
            showRoundSummary = true
        }
    }
}

// MARK: - Practice

struct PracticeHubView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WordItem.createdAt) private var words: [WordItem]
    @Query private var settings: [UserSettings]

    @State private var selectedType: PracticeType = .multipleChoice
    @State private var activeSession: PracticeSessionConfig?

    private var hapticsEnabled: Bool { settings.first?.hapticsEnabled ?? true }
    private var configuredQuestionCount: Int { settings.first?.practiceQuestionCount ?? 10 }
    private var questionCountBinding: Binding<Int> {
        Binding(
            get: { settings.first?.practiceQuestionCount ?? 10 },
            set: { newValue in
                guard let userSettings = settings.first else { return }
                userSettings.practiceQuestionCount = newValue
                try? modelContext.save()
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("题型", selection: $selectedType) {
                    ForEach(PracticeType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                PracticeTypeCard(type: selectedType)

                Stepper("每轮题数：\(configuredQuestionCount)", value: questionCountBinding, in: 5...60)
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if words.count < 4 {
                    EmptyStateView(title: "词库数量不足", subtitle: "至少需要 4 个单词才能开始测试")
                }

                Button {
                    startSession(random: false)
                } label: {
                    Label("开始练习", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
                .disabled(words.count < 4)

                Button {
                    startSession(random: true)
                } label: {
                    Label("随机测试（\(configuredQuestionCount)题）", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(words.count < 4)

                Spacer()
            }
            .padding()
            .navigationTitle("练习测试")
            .onReceive(NotificationCenter.default.publisher(for: .startRandomQuiz)) { _ in
                startSession(random: true)
            }
            .fullScreenCover(item: $activeSession) { config in
                PracticeSessionView(config: config)
            }
        }
    }

    private func startSession(random: Bool) {
        Haptics.impact(.medium, enabled: hapticsEnabled)
        let type = random ? PracticeType.allCases.randomElement() ?? .multipleChoice : selectedType
        let preferredCount = settings.first?.practiceQuestionCount ?? 10
        let count = min(max(5, preferredCount), max(4, words.count))
        activeSession = PracticeSessionConfig(type: type, questionCount: count)
    }
}

struct PracticeSessionConfig: Identifiable {
    let id = UUID()
    let type: PracticeType
    let questionCount: Int
}

struct PracticeSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WordItem.createdAt) private var words: [WordItem]
    @Query(sort: \StudyRecord.date, order: .reverse) private var records: [StudyRecord]
    @Query private var settings: [UserSettings]
    @Query private var achievements: [AchievementUnlock]

    let config: PracticeSessionConfig

    @State private var questions: [PracticeQuestion] = []
    @State private var currentIndex: Int = 0
    @State private var selectedOption: String?
    @State private var typedAnswer: String = ""
    @State private var answerSubmitted: Bool = false

    @State private var correctCount: Int = 0
    @State private var spentSeconds: Int = 0
    @State private var remainingSeconds: Int = 15
    @State private var showWrongAnimation: Bool = false
    @State private var showCorrectAnimation: Bool = false

    @State private var wrongAnswers: [WrongAnswerItem] = []
    @State private var finished: Bool = false
    @State private var unlockedAchievement: AchievementDefinition?

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var perQuestionSeconds: Int { settings.first?.perQuestionSeconds ?? 15 }
    private var hapticsEnabled: Bool { settings.first?.hapticsEnabled ?? true }
    private var soundEnabled: Bool { settings.first?.soundEnabled ?? true }

    private var currentQuestion: PracticeQuestion? {
        guard currentIndex >= 0, currentIndex < questions.count else { return nil }
        return questions[currentIndex]
    }

    private var timerProgress: Double {
        guard perQuestionSeconds > 0 else { return 0 }
        return Double(remainingSeconds) / Double(perQuestionSeconds)
    }

    var body: some View {
        NavigationStack {
            Group {
                if finished {
                    PracticeResultView(
                        correctCount: correctCount,
                        totalCount: questions.count,
                        spentSeconds: spentSeconds,
                        wrongAnswers: wrongAnswers
                    ) {
                        dismiss()
                    }
                } else if let question = currentQuestion {
                    VStack(spacing: 18) {
                        topProgress

                        VStack(alignment: .leading, spacing: 10) {
                            Text("第 \(currentIndex + 1) / \(questions.count) 题")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Text(questionPromptText(question))
                                .font(.title3.bold())
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if question.type == .listening {
                                Button {
                                    TTSService.shared.speak(question.answer, enabled: soundEnabled)
                                } label: {
                                    Label("播放发音", systemImage: "speaker.wave.2.fill")
                                }
                                .buttonStyle(.bordered)
                                .tint(AppTheme.accent)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                        answerArea(question: question)

                        Spacer()
                    }
                    .padding()
                    .overlay {
                        if showCorrectAnimation {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 82))
                                .foregroundStyle(AppTheme.success)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                } else {
                    LoadingStateView(title: "正在生成题目", subtitle: "请稍候")
                }
            }
            .navigationTitle("\(config.type.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("退出") {
                        dismiss()
                    }
                }
            }
            .overlay(alignment: .top) {
                if let unlockedAchievement {
                    AchievementToast(definition: unlockedAchievement)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear {
                setupSession()
            }
            .onReceive(timer) { _ in
                guard !finished, !questions.isEmpty else { return }
                spentSeconds += 1
                remainingSeconds -= 1

                if remainingSeconds <= 0 {
                    submitAnswer(userAnswer: nil)
                }
            }
        }
    }

    private var topProgress: some View {
        VStack(spacing: 8) {
            ProgressView(value: timerProgress)
                .tint(timerProgress > 0.25 ? AppTheme.primary : AppTheme.error)

            HStack {
                Text("剩余 \(remainingSeconds)s")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("正确 \(correctCount)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.success)
            }
        }
    }

    @ViewBuilder
    private func answerArea(question: PracticeQuestion) -> some View {
        switch question.type {
        case .multipleChoice, .listening:
            VStack(spacing: 10) {
                ForEach(question.options, id: \.self) { option in
                    Button {
                        selectedOption = option
                        submitAnswer(userAnswer: option)
                    } label: {
                        HStack {
                            Text(option)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemBackground))
                        )
                    }
                    .buttonStyle(.plain)
                    .modifier(ShakeEffect(trigger: showWrongAnimation ? 1 : 0))
                }
            }

        case .fillBlank:
            VStack(spacing: 12) {
                TextField("输入英文单词", text: $typedAnswer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding()
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .modifier(ShakeEffect(trigger: showWrongAnimation ? 1 : 0))

                Button {
                    let answer = typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                    submitAnswer(userAnswer: answer.isEmpty ? nil : answer)
                } label: {
                    Label("提交答案", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
            }
        }
    }

    private func questionPromptText(_ question: PracticeQuestion) -> String {
        switch question.type {
        case .multipleChoice:
            return question.prompt
        case .fillBlank:
            return "中文提示：\(question.prompt)"
        case .listening:
            return "听发音后选择对应单词"
        }
    }

    private func setupSession() {
        let sourceWords = Array(words.shuffled().prefix(max(config.questionCount, 4)))
        questions = Self.generateQuestions(type: config.type, words: sourceWords, count: config.questionCount)
        remainingSeconds = perQuestionSeconds

        if config.type == .listening, let first = questions.first {
            TTSService.shared.speak(first.answer, enabled: soundEnabled)
        }
    }

    private func submitAnswer(userAnswer: String?) {
        guard !answerSubmitted, let question = currentQuestion else { return }

        answerSubmitted = true
        let normalizedAnswer = (userAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isCorrect = normalizedAnswer == question.answer.lowercased()

        if isCorrect {
            correctCount += 1
            Haptics.success(enabled: hapticsEnabled)
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                showCorrectAnimation = true
            }
        } else {
            Haptics.error(enabled: hapticsEnabled)
            withAnimation(.default) {
                showWrongAnimation = true
            }

            wrongAnswers.append(
                WrongAnswerItem(word: question.word, meaning: question.helperMeaning, correctAnswer: question.answer)
            )
        }

        if let testedWord = words.first(where: { $0.english == question.word.lowercased() }) {
            SM2Scheduler.review(word: testedWord, quality: isCorrect ? 4 : 2)
        }

        let record = StudyRecord(
            date: .now,
            modeRaw: StudyMode.test.rawValue,
            correct: isCorrect,
            duration: Double(max(1, perQuestionSeconds - remainingSeconds)),
            word: question.word
        )
        modelContext.insert(record)
        try? modelContext.save()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            nextQuestion(sessionRecord: record)
        }
    }

    private func nextQuestion(sessionRecord: StudyRecord) {
        withAnimation {
            showCorrectAnimation = false
            showWrongAnimation = false
        }

        answerSubmitted = false
        selectedOption = nil
        typedAnswer = ""
        remainingSeconds = perQuestionSeconds

        if currentIndex < questions.count - 1 {
            currentIndex += 1
            if config.type == .listening, let next = currentQuestion {
                TTSService.shared.speak(next.answer, enabled: soundEnabled)
            }
        } else {
            if let unlock = AchievementEngine.evaluate(
                words: words,
                records: records + [sessionRecord],
                achievements: achievements,
                modelContext: modelContext,
                latestSessionCorrect: correctCount,
                latestSessionTotal: questions.count
            ) {
                withAnimation(.spring()) {
                    unlockedAchievement = unlock
                }
            }
            finished = true
        }
    }

    static func generateQuestions(type: PracticeType, words: [WordItem], count: Int) -> [PracticeQuestion] {
        let safePool = words.isEmpty ? [] : words
        let selectedWords = Array(safePool.shuffled().prefix(count))

        return selectedWords.map { word in
            switch type {
            case .multipleChoice:
                let distractors = safePool
                    .filter { $0.english != word.english }
                    .filter { $0.meaning != word.meaning }
                    .shuffled()
                    .prefix(3)
                    .map(\.meaning)
                var options = Array(Set(distractors + [word.meaning])).shuffled()
                while options.count < 4 {
                    options.append("（干扰项）\(Int.random(in: 100...999))")
                }
                return PracticeQuestion(
                    type: type,
                    word: word.english,
                    prompt: "\(word.english) \(word.phonetic)",
                    answer: word.meaning,
                    options: Array(options.prefix(4)).shuffled(),
                    helperMeaning: word.meaning
                )

            case .fillBlank:
                return PracticeQuestion(
                    type: type,
                    word: word.english,
                    prompt: word.meaning,
                    answer: word.english,
                    options: [],
                    helperMeaning: word.meaning
                )

            case .listening:
                let distractors = safePool
                    .filter { $0.english != word.english }
                    .shuffled()
                    .prefix(3)
                    .map(\.english)
                var options = Array(Set(distractors + [word.english])).shuffled()
                while options.count < 4 {
                    options.append("word\(Int.random(in: 100...999))")
                }
                return PracticeQuestion(
                    type: type,
                    word: word.english,
                    prompt: "听发音",
                    answer: word.english,
                    options: Array(options.prefix(4)).shuffled(),
                    helperMeaning: word.meaning
                )
            }
        }
    }
}

struct PracticeResultView: View {
    let correctCount: Int
    let totalCount: Int
    let spentSeconds: Int
    let wrongAnswers: [WrongAnswerItem]
    let onDone: () -> Void

    private var accuracy: Double {
        guard totalCount > 0 else { return 0 }
        return Double(correctCount) / Double(totalCount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Text("练习完成")
                        .font(.largeTitle.bold())

                    Text("正确率 \(Int(accuracy * 100))%")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(accuracy >= 0.8 ? AppTheme.success : AppTheme.warning)

                    Text("用时 \(spentSeconds) 秒")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                if wrongAnswers.isEmpty {
                    Label("本轮没有错题", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(AppTheme.success)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("错题回顾")
                            .font(.headline)

                        ForEach(wrongAnswers) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.word)
                                    .font(.headline)
                                Text(item.meaning)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    onDone()
                } label: {
                    Label("返回", systemImage: "arrow.backward.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
            }
            .padding()
        }
    }
}

// MARK: - Progress

struct ProgressDashboardView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WordItem.createdAt) private var words: [WordItem]
    @Query(sort: \StudyRecord.date, order: .reverse) private var records: [StudyRecord]
    @Query private var achievements: [AchievementUnlock]

    @State private var selectedRange: ProgressRange = .days7
    @State private var unlockedAchievement: AchievementDefinition?

    private var masteryDistribution: [MasterySlice] {
        let newCount = words.filter { $0.mastery == .newWord }.count
        let learningCount = words.filter { $0.mastery == .learning }.count
        let masteredCount = words.filter { $0.mastery == .mastered }.count
        return [
            MasterySlice(state: .newWord, count: newCount),
            MasterySlice(state: .learning, count: learningCount),
            MasterySlice(state: .mastered, count: masteredCount)
        ]
    }

    private var unlockedKeys: Set<String> {
        Set(achievements.map(\.key))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if records.isEmpty {
                        EmptyStateView(title: "暂无学习记录", subtitle: "完成一次学习或测试后可查看趋势图")
                    }

                    chartSection
                    heatmapSection
                    masterySection
                    badgeSection
                }
                .padding()
            }
            .navigationTitle("学习进度")
            .overlay(alignment: .top) {
                if let unlockedAchievement {
                    AchievementToast(definition: unlockedAchievement)
                        .padding(.top, 6)
                }
            }
            .onAppear {
                if let unlock = AchievementEngine.evaluate(
                    words: words,
                    records: records,
                    achievements: achievements,
                    modelContext: modelContext
                ) {
                    withAnimation(.spring()) {
                        unlockedAchievement = unlock
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                        withAnimation {
                            unlockedAchievement = nil
                        }
                    }
                }
            }
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("学习趋势")
                    .font(.headline)
                Spacer()
                Picker("范围", selection: $selectedRange) {
                    ForEach(ProgressRange.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            let lineData = StudyAnalytics.lineStats(records: records, range: selectedRange)

            Chart(lineData) { item in
                LineMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value("学习数", item.count)
                )
                .foregroundStyle(AppTheme.primary)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("日期", item.date, unit: .day),
                    y: .value("学习数", item.count)
                )
                .foregroundStyle(AppTheme.primary.opacity(0.18))
            }
            .frame(height: 220)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("学习频率热力图")
                .font(.headline)

            HeatmapCalendarView(data: StudyAnalytics.heatmapStats(records: records, days: 84))
                .frame(height: 130)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var masterySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("掌握度分布")
                .font(.headline)

            if #available(iOS 17.0, *) {
                Chart(masteryDistribution) { slice in
                    SectorMark(
                        angle: .value("数量", slice.count),
                        innerRadius: .ratio(0.62),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("状态", slice.state.title))
                }
                .frame(height: 230)
                .chartForegroundStyleScale([
                    "新学": AppTheme.primary.opacity(0.55),
                    "学习中": AppTheme.accent.opacity(0.8),
                    "已掌握": AppTheme.success.opacity(0.9)
                ])
            } else {
                Text("当前系统版本不支持饼图显示")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var badgeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("成就徽章墙")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                ForEach(AchievementEngine.all) { badge in
                    let unlocked = unlockedKeys.contains(badge.key)
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: badge.icon)
                            .font(.title2)
                            .foregroundStyle(unlocked ? AppTheme.warning : .secondary)

                        Text(badge.title)
                            .font(.headline)
                            .foregroundStyle(unlocked ? .primary : .secondary)

                        Text(badge.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(unlocked ? AppTheme.warning.opacity(0.14) : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \WordItem.createdAt) private var words: [WordItem]
    @Query(sort: \StudyRecord.date, order: .reverse) private var records: [StudyRecord]
    @Query private var achievements: [AchievementUnlock]
    @Query private var settingsList: [UserSettings]

    @State private var showResetAlert = false

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Form {
                if let settings {
                    Section("学习目标") {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("每日目标")
                                Spacer()
                                Text("\(settings.dailyGoal)")
                                    .foregroundStyle(AppTheme.primary)
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(settings.dailyGoal) },
                                    set: { settings.dailyGoal = Int($0.rounded()) }
                                ),
                                in: 10...100,
                                step: 1
                            )
                        }

                        Stepper("每题倒计时：\(settings.perQuestionSeconds)s", value: Binding(
                            get: { settings.perQuestionSeconds },
                            set: { settings.perQuestionSeconds = $0 }
                        ), in: 5...60)

                        Stepper("每轮练习题数：\(settings.practiceQuestionCount)", value: Binding(
                            get: { settings.practiceQuestionCount },
                            set: { settings.practiceQuestionCount = $0 }
                        ), in: 5...60)
                    }

                    Section("提醒") {
                        Toggle("学习提醒", isOn: Binding(
                            get: { settings.reminderEnabled },
                            set: {
                                settings.reminderEnabled = $0
                                Haptics.impact(.light, enabled: settings.hapticsEnabled)
                            }
                        ))

                        if settings.reminderEnabled {
                            DatePicker(
                                "提醒时间",
                                selection: Binding(
                                    get: { settings.reminderTime },
                                    set: { settings.reminderTime = $0 }
                                ),
                                displayedComponents: [.hourAndMinute]
                            )
                        }
                    }

                    Section("交互") {
                        Toggle("音效", isOn: Binding(
                            get: { settings.soundEnabled },
                            set: { settings.soundEnabled = $0 }
                        ))

                        Toggle("震动反馈", isOn: Binding(
                            get: { settings.hapticsEnabled },
                            set: { settings.hapticsEnabled = $0 }
                        ))

                        Toggle("自动播放发音", isOn: Binding(
                            get: { settings.autoPlayPronunciation },
                            set: { settings.autoPlayPronunciation = $0 }
                        ))
                    }

                    Section("外观") {
                        Picker("主题", selection: Binding(
                            get: { settings.appearance },
                            set: { settings.appearance = $0 }
                        )) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                    }

                    Section("数据") {
                        Button(role: .destructive) {
                            showResetAlert = true
                        } label: {
                            Label("重置学习进度", systemImage: "trash")
                        }
                    }
                } else {
                    EmptyStateView(title: "设置未初始化", subtitle: "请稍后重试")
                }
            }
            .navigationTitle("设置")
            .onChange(of: settingsList.first?.dailyGoal) { _, _ in saveSettings() }
            .onChange(of: settingsList.first?.reminderEnabled) { _, _ in saveSettings() }
            .onChange(of: settingsList.first?.reminderTime) { _, _ in saveSettings() }
            .onChange(of: settingsList.first?.soundEnabled) { _, _ in saveSettings() }
            .onChange(of: settingsList.first?.hapticsEnabled) { _, _ in saveSettings() }
            .onChange(of: settingsList.first?.autoPlayPronunciation) { _, _ in saveSettings() }
            .onChange(of: settingsList.first?.appearanceRaw) { _, _ in saveSettings() }
            .onChange(of: settingsList.first?.perQuestionSeconds) { _, _ in saveSettings() }
            .onChange(of: settingsList.first?.practiceQuestionCountRaw) { _, _ in saveSettings() }
            .alert("确认重置", isPresented: $showResetAlert) {
                Button("取消", role: .cancel) {}
                Button("确认重置", role: .destructive) {
                    resetProgress()
                }
            } message: {
                Text("将清空学习记录、成就，并重置所有单词状态。")
            }
        }
    }

    private func saveSettings() {
        try? modelContext.save()
    }

    private func resetProgress() {
        for record in records {
            modelContext.delete(record)
        }

        for achievement in achievements {
            modelContext.delete(achievement)
        }

        for word in words {
            word.mastery = .newWord
            word.repetitions = 0
            word.intervalDays = 1
            word.efactor = 2.5
            word.dueDate = .now
            word.lastReviewedAt = nil
            word.isFavorite = false
        }

        try? modelContext.save()
    }
}

// MARK: - Components

struct ProgressRingView: View {
    let progress: Double
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [AppTheme.primary, AppTheme.accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: progress)
        }
    }
}

struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    var badge: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color)

                    if let badge, badge > 0 {
                        Text("\(badge)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(AppTheme.error, in: Capsule())
                            .foregroundStyle(.white)
                            .offset(x: 10, y: -8)
                    }
                }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct FlashcardView: View {
    let word: WordItem
    let isFlipped: Bool
    let dragOffset: CGSize

    private var cardRotation: Double {
        Double(dragOffset.width / 18)
    }

    private var colorOverlay: Color {
        if dragOffset.width > 40 {
            return AppTheme.success.opacity(0.22)
        }
        if dragOffset.width < -40 {
            return AppTheme.error.opacity(0.22)
        }
        if dragOffset.height < -50 {
            return AppTheme.warning.opacity(0.25)
        }
        return .clear
    }

    var body: some View {
        ZStack {
            frontFace
                .opacity(isFlipped ? 0 : 1)

            backFace
                .opacity(isFlipped ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .rotationEffect(.degrees(cardRotation))
        .offset(x: dragOffset.width * 0.48, y: dragOffset.height * 0.42)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isFlipped)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(colorOverlay)
        }
    }

    private var frontFace: some View {
        VStack(spacing: 12) {
            Spacer()
            Text(word.english)
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text(word.phonetic)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
            Spacer()

            Text("点击翻转，左右滑动判断掌握情况")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.88))
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(AppTheme.cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: AppTheme.primary.opacity(0.32), radius: 14, x: 0, y: 8)
        .foregroundStyle(.white)
    }

    private var backFace: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(word.meaning)
                .font(.title3.bold())

            Text(word.example)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer()

            HStack {
                Text(word.level.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.primary.opacity(0.12), in: Capsule())

                if word.isFavorite {
                    Label("已收藏", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.warning)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.primary.opacity(0.25), lineWidth: 1)
        )
    }
}

struct SwipeHintView: View {
    var body: some View {
        HStack(spacing: 14) {
            Label("左滑不认识", systemImage: "xmark.circle")
            Label("右滑认识", systemImage: "checkmark.circle")
            Label("上滑收藏", systemImage: "star")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct PracticeTypeCard: View {
    let type: PracticeType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(type.title)
                .font(.headline)
            Text(type.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct HeatmapCalendarView: View {
    let data: [(date: Date, count: Int)]

    private let rows = 7
    private let columns = 12

    var body: some View {
        let padded = data.suffix(rows * columns)

        HStack(alignment: .top, spacing: 4) {
            ForEach(0..<columns, id: \.self) { column in
                VStack(spacing: 4) {
                    ForEach(0..<rows, id: \.self) { row in
                        let index = column * rows + row
                        if index < padded.count {
                            let item = Array(padded)[index]
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(heatColor(for: item.count))
                                .frame(width: 14, height: 14)
                                .accessibilityLabel(Text(dateLabel(item.date) + " 学习 \(item.count)"))
                        } else {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func heatColor(for count: Int) -> Color {
        switch count {
        case 0: return Color.secondary.opacity(0.12)
        case 1...2: return AppTheme.primary.opacity(0.32)
        case 3...5: return AppTheme.primary.opacity(0.55)
        case 6...9: return AppTheme.accent.opacity(0.72)
        default: return AppTheme.accent.opacity(0.95)
        }
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

struct AchievementToast: View {
    let definition: AchievementDefinition

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: definition.icon)
                .foregroundStyle(AppTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("解锁成就：\(definition.title)")
                    .font(.subheadline.weight(.semibold))
                Text(definition.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
    }
}

struct EmptyStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LoadingStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(AppTheme.primary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

struct ErrorStateView: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(AppTheme.error)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primary)
        }
        .padding()
    }
}

struct ShakeEffect: GeometryEffect {
    var trigger: CGFloat

    var animatableData: CGFloat {
        get { trigger }
        set { trigger = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = 8 * sin(trigger * .pi * 6)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let startReviewOnly = Notification.Name("startReviewOnly")
    static let startRandomQuiz = Notification.Name("startRandomQuiz")
}

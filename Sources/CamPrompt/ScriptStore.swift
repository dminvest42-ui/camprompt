import Foundation

struct Script: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var text: String
    var updatedAt: Date = Date()
}

/// Script library persisted as JSON in ~/Library/Application Support/CamPrompt/scripts.json
@MainActor
final class ScriptStore: ObservableObject {
    @Published var scripts: [Script] = []
    @Published var selectedID: UUID?

    var selectedScript: Script? {
        guard let selectedID else { return scripts.first }
        return scripts.first(where: { $0.id == selectedID }) ?? scripts.first
    }

    private var storageURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CamPrompt")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scripts.json")
    }

    init() {
        load()
        if scripts.isEmpty {
            scripts = [Script(
                title: "Пример",
                text: "Добро пожаловать в CamPrompt!\n\nЭто ваш телесуфлёр. Текст плавно прокручивается прямо под камерой MacBook, поэтому глаза остаются направленными в объектив.\n\nНажмите «Запись» — после обратного отсчёта начнётся запись видео, и текст поедет сам.\n\nПробел — пауза и пуск. R — с начала. Стрелки вверх и вниз — скорость. Esc — скрыть суфлёр.\n\nХороших съёмок!"
            )]
            selectedID = scripts.first?.id
            save()
        } else {
            selectedID = scripts.first?.id
        }
    }

    func addScript() {
        let s = Script(title: "Новый скрипт", text: "")
        scripts.insert(s, at: 0)
        selectedID = s.id
        save()
    }

    func delete(_ script: Script) {
        scripts.removeAll { $0.id == script.id }
        if selectedID == script.id { selectedID = scripts.first?.id }
        save()
    }

    func update(id: UUID, title: String? = nil, text: String? = nil) {
        guard let idx = scripts.firstIndex(where: { $0.id == id }) else { return }
        if let title { scripts[idx].title = title }
        if let text { scripts[idx].text = text }
        scripts[idx].updatedAt = Date()
        save()
    }

    func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([Script].self, from: data) else { return }
        scripts = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(scripts) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}

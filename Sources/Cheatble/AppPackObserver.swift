import Foundation
import CheatbleCore

final class AppPackObserver {
    private let storage: AppPackStorage
    private let bundled = AppPackStorage.bundled()
    private let queue = DispatchQueue(label: "app.cheatble.packs", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var lastSignature: [String]?
    let initialValue: AppPackStorage.Loaded
    var onChange: ((AppPackStorage.Loaded) -> Void)?
    init(storage: AppPackStorage) {
        self.storage = storage
        initialValue = AppPackStorage.merge(bundled: bundled, installed: storage.load())
    }
    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2)
        timer.setEventHandler { [weak self] in self?.check() }
        self.timer = timer
        timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }
    func refresh() { queue.async { [weak self] in self?.lastSignature = nil; self?.check() } }
    private func check() {
        let files = (try? FileManager.default.contentsOfDirectory(at: storage.directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles])) ?? []
        let signature = files.filter { $0.pathExtension.lowercased() == "json" }.map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            return "\(url.lastPathComponent)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values?.fileSize ?? 0)"
        }.sorted()
        guard lastSignature != signature else { return }
        lastSignature = signature
        let loaded = AppPackStorage.merge(bundled: bundled, installed: storage.load())
        DispatchQueue.main.async { [weak self] in self?.onChange?(loaded) }
    }
    deinit { stop() }
}

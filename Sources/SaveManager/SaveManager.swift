import Foundation

public struct SaveFile {
    public fileprivate(set) var path: String
    public let source: String
    public let seed: String
    public let ante: String
    public let round: String
    public fileprivate(set) var date: Date?

    public static var mock: SaveFile {
        SaveFile(path: "path", source: "", seed: "seed", ante: "ante", round: "round", date: nil)
    }
}

extension SaveFile: Identifiable, Equatable, Hashable {
    public var id: String { path }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(path)
    }
}

func getCompressed(_ file: String) -> Data? {
    let fileURL = URL(fileURLWithPath: file)

    if let fileData = try? Data(contentsOf: fileURL) {
        if String(data: fileData, encoding: .utf8)?.prefix(6) != "return" {
            if let decompressedData = try? (fileData as NSData).decompressed(using: .zlib) {
                return decompressedData as Data
            }
        }
        return fileData
    }
    return nil
}

extension SaveFile {
    init?(path: String) {
        guard
            let data = getCompressed(path),
            let source = String(data: data, encoding: .utf8),
            let seed = source.firstMatch(of: /\[\"seed\"\]=\"([0-9a-zA-Z]+)\"/)?.output.1,
            let ante = source.firstMatch(of: /\[\"ante\"\]=(\d+)/)?.output.1,
            let round = source.firstMatch(of: /\[\"round\"\]=(\d+)/)?.output.1
//            let dollars = str.firstMatch(of: /\["dollars"\]\s*="([0-9])"/)?.output.1,
        else {
            return nil
        }
        var date: Date?
        if let dateStr = path.split(separator: "-").last, let timeInterval = TimeInterval(dateStr) {
            date = Date(timeIntervalSince1970: timeInterval)
        }
        self.init(
            path: path,
            source: source,
            seed: String(seed),
            ante: String(ante),
            round: String(round),
            date: date
        )
    }
}

#if canImport(SwiftUI)
import SwiftUI
public class SaveManager: ObservableObject {
    var monitor: FileMonitor?
    var restoring = false
    public init() { }
}
#else
public class SaveManager {
    var monitor: FileMonitor?
    var restoring = false
    public init() { }
}
#endif

extension SaveManager {
    public func autoBackup(newSave: @escaping (_ save: SaveFile) -> Void) {
        func backupSave(saveFilePath: String) throws {
            guard var save = SaveFile(path: saveFilePath) else {
                return
            }
            try FileManager.default.createDirectory(atPath: Paths.backupFolder, withIntermediateDirectories: true)
            let date = Date()
            let backupPath = "\(Paths.backupFolder)/\(save.seed)-\(save.ante)-\(save.round)-\(date.timeIntervalSince1970)"

            try FileManager.default.copyItem(atPath: saveFilePath, toPath: backupPath)
            save.path = backupPath
            save.date = date
            newSave(save)
        }

        monitor = FileMonitor(filePath: Paths.saveFolder) { file, flags in
            guard !self.restoring, file.hasSuffix(Paths.saveFileSuffix) else {
                return
            }
            try? backupSave(saveFilePath: file)
        }
        monitor?.start()
    }

    public var backupFiles: [SaveFile] {
        let result = try? FileManager.default.contentsOfDirectory(atPath: Paths.backupFolder).compactMap {
            SaveFile(path: "\(Paths.backupFolder)/\($0)")
        }
        return result ?? []
    }

    public func restore(save: SaveFile) {
        restoring = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.restoring = false
        }
        try? FileManager.default.removeItem(atPath: Paths.saveFile)
        try? FileManager.default.copyItem(atPath: save.path, toPath: Paths.saveFile)
    }

    public var current: SaveFile? {
        guard let current = SaveFile(path: Paths.saveFile) else {
            return nil
        }
        return backupFiles.first {
            $0.source == current.source
        }
    }
}

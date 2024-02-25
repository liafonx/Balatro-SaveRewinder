//
//  Paths.swift
//  
//
//  Created by mi on 2024/2/24.
//

import Foundation

public enum Paths {
    public static var saveFolder: String {
        get {
            UserDefaults.standard.string(forKey: "SaveFolder") ?? ""
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "SaveFolder")
        }
    }
    public static var saveFolderSuffix: String = "/AppData/Roaming/Balatro/"
    public static var saveFileSuffix: String = "1/save.jkr"
    public static var saveFile: String = "\(saveFolder)/\(saveFileSuffix)"
    public static var backupFolder: String = "\(saveFolder)/backups"
}

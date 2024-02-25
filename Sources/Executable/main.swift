//
//  main.swift
//  
//
//  Created by mi on 2024/2/24.
//

import Foundation
import SaveManager

if let path = CommandLine.arguments.first {
    assert(path.hasSuffix("/AppData/Roaming/Balatro/"), "saveFolder should end with /AppData/Roaming/Balatro/")
    Paths.saveFolder = path
}

let manager =  SaveManager()
manager.autoBackup { path in
    print("new backed up \(path)")
}

RunLoop.main.run()

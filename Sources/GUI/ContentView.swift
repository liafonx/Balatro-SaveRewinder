//
//  ContentView.swift
//
//
//  Created by mi on 2024/2/24.
//

import SwiftUI
import SaveManager

struct ContentView: View {
    @StateObject var saveManager = SaveManager()
    @State var saveList: [SaveFile] = []
    @State var selecting: SaveFile?
    @State var current: SaveFile?

    var body: some View {
        ScrollViewReader { scrollProxy in
            VStack {
                ScrollView {
                    Color.clear
                        .frame(height: 8)
                    ForEach(saveList) { save in
                        SaveFileView(
                            save: save,
                            isCurrent: save == current
                        )
                            .background {
                                Color.gray.opacity(selecting == save ? 1 : 0.3)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .onTapGesture {
                                withAnimation(.easeIn(duration: 0.2)) {
                                    selecting = save
                                }
                            }
                    }
                    Color.clear
                        .frame(height: 8)
                }
                Spacer()
                HStack {
                    Button {
                        if let selecting {
                            saveManager.restore(save: selecting)
                            current = selecting
                        }
                    } label: {
                        Text("Restore this save")
                    }
                    .disabled(selecting == nil)

                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: Paths.saveFolder))
                    } label: {
                        Text("Open save folder")
                    }

                    Button {
                        loadSaveFiles()
                    } label: {
                        Text("Reload file list")
                    }
                }
                .padding(20)
            }
            .padding(.horizontal, 8)
            .onAppear {
                loadSaveFiles()
                saveManager.autoBackup { save in
                    saveList.insert(save, at: 0)
                    current = save
                    scrollProxy.scrollTo(selecting)
                }
            }
        }
    }

    func loadSaveFiles() {
        saveList = saveManager.backupFiles.sorted(by: { save1, save2 in
            guard let date1 = save1.date, let date2 = save2.date else {
                return false
            }
            return date1 > date2
        })

        current = saveManager.current
    }
}

#Preview {
    ContentView()
}

//
//  SaveFileView.swift
//  
//
//  Created by mi on 2024/2/24.
//

import SwiftUI
import SaveManager

struct SaveFileView: View {
    let save: SaveFile
    let isCurrent: Bool
    var nameKey: String {
        "SaveName.\(save.date?.timeIntervalSince1970 ?? 0)"
    }
    @State var name: String? {
        didSet {
            UserDefaults.standard.set(name, forKey: nameKey)
        }
    }
    @State var isHover = false

    var body: some View {
        HStack {
            TextField("", text: .init(get: {
                name ?? ""
            }, set: { newValue in
                name = newValue
            }))
            .frame(width: 90)
            Text(save.seed)
            VStack(alignment: .leading) {
                Text("ante: \(save.ante)")
                Text("round: \(save.round)")
            }
            .padding(10)

            VStack(alignment: .leading) {
                Text(save.date?.formatted(date: .abbreviated, time: .standard) ?? "")
            }
            .padding(10)
            Spacer()
            if isCurrent {
                Text("is current save")
            }
        }
        .padding(.horizontal, 10)
        .onAppear {
            name = UserDefaults.standard.string(forKey: nameKey)
        }
    }
}

#Preview {
    SaveFileView(save: .mock, isCurrent: false)
}

//
//  ContentView.swift
//  mercantis hub
//
//  Created by Kevin Busuttil on 12/04/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "building.2.crop.circle")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Mercantis Hub")
                .font(.title)
                .fontWeight(.semibold)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

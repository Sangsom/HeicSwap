//
//  HomeScreen.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import SwiftUI

struct HomeScreen: View {
    // Until the Convert shell (task 4.1) lands, Home surfaces the import harness so the
    // import service (task 3.5) can be exercised on device.
    var body: some View {
        ImportView()
    }
}

#Preview {
    HomeScreen()
}

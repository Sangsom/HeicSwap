//
//  PaywallPresenter.swift
//  HeicSwap
//
//  Created by Rinalds Domanovs on 23/02/2026.
//

import RevenueCat
import RevenueCatUI
import SwiftUI

/// Thin wrapper around RevenueCat `PaywallView` with purchase and restore callbacks.
struct PaywallPresenter: View {

    var purchaseCompletedHandler: (CustomerInfo) -> Void = { _ in }
    var restoreCompletedHandler: (CustomerInfo) -> Void = { _ in }

    var body: some View {
        PaywallView(displayCloseButton: true)
            .onPurchaseCompleted { customerInfo in
                purchaseCompletedHandler(customerInfo)
            }
            .onRestoreCompleted { customerInfo in
                restoreCompletedHandler(customerInfo)
            }
    }
}

#Preview {
    PaywallPresenter()
}

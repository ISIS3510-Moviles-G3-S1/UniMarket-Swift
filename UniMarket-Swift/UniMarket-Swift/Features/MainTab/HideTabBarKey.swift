//
//  HideTabBarKey.swift
//  UniMarket-Swift
//
//  Created by FELIPE MESA on 6/04/26.
//

import SwiftUI

struct HideTabBarKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

extension EnvironmentValues {
    var hideTabBar: Binding<Bool> {
        get { self[HideTabBarKey.self] }
        set { self[HideTabBarKey.self] = newValue }
    }
}

//
//  SettingsNavigationState.swift
//  SettingsUI
//
//  Created for GoodTerm
//

import Foundation
import SwiftUI

// MARK: - Navigation State
@Observable
public class SettingsNavigationState {
    public var selectedCategory: SettingsCategory?
    public var selectedItem: SettingsItem?
    public var columnVisibility: NavigationSplitViewVisibility = .all

    public init() {
        // Select first category by default
        selectedCategory = .about
    }
}

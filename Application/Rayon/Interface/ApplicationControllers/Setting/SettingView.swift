//
//  SettingView.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/10.
//

import RayonModule
import SettingsUI
import SwiftUI

struct SettingView: View {
    @EnvironmentObject var store: RayonStore

    var body: some View {
        SettingsViewContainer()
            .environmentObject(store)
    }
}

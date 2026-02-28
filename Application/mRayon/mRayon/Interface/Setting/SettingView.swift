//
//  SettingView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import RayonModule
import SettingsUI
import SwiftUI

struct SettingView: View {
    @StateObject var store = RayonStore.shared

    var body: some View {
        SettingsViewContainer()
            .environmentObject(store)
    }
}

//
//  SettingsView.swift
//  SettingsUI
//
//  Created for GoodTerm
//

import DataSync
import Premium
import RayonModule
import SwiftUI

// MARK: - Main Settings View
public struct SettingsViewContainer: View {
    @EnvironmentObject var store: RayonStore
    @State private var selectedCategory: SettingsCategory?

    public init() {}

    public var body: some View {
        #if os(iOS)
        iOSSettingsNavigationView()
        #else
        macOSInlineSettingsView(selectedCategory: $selectedCategory)
            .onAppear {
                if selectedCategory == nil {
                    selectedCategory = .about
                }
            }
        #endif
    }
}

#if os(macOS)
// Inline layout: left category list + right detail, no nested NavigationSplitView
private struct macOSInlineSettingsView: View {
    @Binding var selectedCategory: SettingsCategory?
    @State private var searchText: String = ""

    var body: some View {
        HStack(spacing: 0) {
            // Left: category list (macOS System Settings style)
            List(selection: $selectedCategory) {
                ForEach(SettingsCategory.allCases) { category in
                    CategoryRow(category: category)
                        .tag(category)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 220)

            Divider()

            // Right: detail content
            if let category = selectedCategory {
                CategoryContentView(category: category)
            } else {
                Text("Select a category")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif

#if os(iOS)
private struct iOSSettingsNavigationView: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(SettingsCategory.allCases) { category in
                    NavigationLink {
                        iOSMergedCategoryDetailView(category: category)
                    } label: {
                        CategoryRow(category: category)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.tr("Settings"))
        }
    }
}

private struct iOSMergedCategoryDetailView: View {
    let category: SettingsCategory

    var body: some View {
        Form {
            ForEach(category.items) { item in
                SettingsDetailContent(item: item)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(category.title)
    }
}
#endif

// MARK: - Category Content View (Right Side — System Settings Style)
public struct CategoryContentView: View {
    let category: SettingsCategory

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section header with icon (like macOS System Settings)
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(category.tintColor.gradient)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: category.icon)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(.white)
                        )
                    Text(category.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .padding(.bottom, 4)

                ForEach(category.items) { item in
                    SettingsDetailContent(item: item)
                }
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .padding(DesignTokens.paddingScrollable)
        }
        #if os(macOS)
        .scrollContentBackground(.hidden)
        #endif
    }
}

// MARK: - Design Tokens (local to SettingsUI package)
private enum DesignTokens {
    static let paddingScrollable: CGFloat = 24
    static let cornerRadiusMedium: CGFloat = 14
    static let shadowOpacity: Double = 0.08
    static let shadowRadius: CGFloat = 8
    static let shadowY: CGFloat = 2
    static let itemSpacingStandard: CGFloat = 12
}

// MARK: - Category Row Component (macOS System Settings Style)
public struct CategoryRow: View {
    let category: SettingsCategory

    public var body: some View {
        HStack(spacing: 10) {
            // Colored rounded-square icon badge (like macOS System Settings sidebar)
            RoundedRectangle(cornerRadius: 6)
                .fill(category.tintColor.gradient)
                .frame(width: 26, height: 26)
                .overlay(
                    Image(systemName: category.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                )

            Text(category.title)
                .font(.body)
        }
    }
}

public struct SettingsView_Previews: PreviewProvider {
    public static var previews: some View {
        SettingsViewContainer()
            .environmentObject(RayonStore.shared)
    }
}

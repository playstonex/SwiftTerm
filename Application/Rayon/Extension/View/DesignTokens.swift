//
//  DesignTokens.swift
//  Rayon
//
//  Centralized design tokens for modern Apple HIG styling.
//

import SwiftUI

enum DesignTokens {
    // MARK: - Corner Radius

    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 14
    static let cornerRadiusLarge: CGFloat = 20

    // MARK: - Padding

    static let paddingCompact: CGFloat = 8
    static let paddingStandard: CGFloat = 16
    static let paddingComfortable: CGFloat = 20
    static let paddingScrollable: CGFloat = 24

    // MARK: - Spacing

    static let itemSpacingTight: CGFloat = 6
    static let itemSpacingStandard: CGFloat = 12
    static let itemSpacingRelaxed: CGFloat = 16

    // MARK: - Shadows

    static let shadowRadius: CGFloat = 8
    static let shadowOpacity: Double = 0.08
    static let shadowY: CGFloat = 2

    // MARK: - Grid

    static let gridMinWidth: CGFloat = 300
    static let gridMaxWidth: CGFloat = 500
    static let gridSpacing: CGFloat = 12

    // MARK: - Typography

    static let sectionHeaderSize: CGFloat = 20

    // MARK: - Animation

    static let springResponse: Double = 0.35
    static let springDamping: Double = 0.8
}

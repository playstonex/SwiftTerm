//
//  PlaceholderView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import SwiftUI

struct PlaceholderView: View {
    let hint: String
    let image: ImageDescriptor

    init(_ str: String, img: ImageDescriptor? = nil) {
        hint = str
        if let img = img {
            image = img
        } else {
            image = .ghost
        }
    }

    enum ImageDescriptor: String {
        case emptyWindow = "empty_window"
        case fileLock = "file_lock"
        case ghost
        case connectionBroken = "connection_broken"
        case personWarning = "person_warning"
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(image.rawValue)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 140, height: 140)
                .opacity(0.7)
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadiusMedium)
                    .fill(.regularMaterial)
            }
            .frame(height: 44)
            .frame(maxWidth: .infinity)
            .frame(maxWidth: 400)
            .overlay(
                Text(hint)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
            )
            Spacer()
                .frame(width: 40, height: 40)
        }
        .expended()
        .padding()
    }
}

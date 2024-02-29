//
//  Thanks.swift
//  mRayon
//
//  Created by lei on 2024/2/29.
//

import SwiftUI

struct Thanks: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image("icon")
                    .antialiased(true)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                Divider()
                Text("GoodTerm is made based on the open-source project Rayon")
                Text("Thanks to the creators of Rayon [@Lakr233](https://twitter.com/Lakr233) and his friends: [@__oquery](https://twitter.com/__oquery) [@zlind0](https://github.com/zlind0) [@unixzii](https://twitter.com/unixzii) [@82flex](https://twitter.com/82flex) [@xnth97](https://twitter.com/xnth97)")
                Text("Rayon source code available at: [GitHub](https://github.com/Lakr233/Rayon)")
                
            }
            .font(.system(.body, design: .rounded))
            .padding()
        }
    }
}

#Preview {
    Thanks()
}

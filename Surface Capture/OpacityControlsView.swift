//
//  OpacityControlsView.swift
//  Surface Capture
//
//  Created by Ashley Davison on 04/02/2025.
//

import SwiftUI

struct OpacityControlsView: View {
    @EnvironmentObject var appModel: AppDataModel
    
    var body: some View {
        VStack {
            Button(action: {
                //appModel.adjustOpacity(by: 0.15)
            }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .padding(20)
            }
            .background(Color.gray)
            .clipShape(Circle())
            
            Button(action: {
                //appModel.adjustOpacity(by: -0.15)
            }) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .padding(20)
            }
            .background(Color.gray)
            .clipShape(Circle())
        }
        .padding(.bottom, 20)
        .padding(.trailing, 10)
    }
}

//
//  Views.swift
//  MediaToolSwiftExample
//
//  Created by Dmitry Starkov on 12/05/2023.
//

import SwiftUI

struct CustomSlider: View {
    @State var isEditing: Bool = false

    @Binding var value: Double
    let range: ClosedRange<Double>
    let title: String
    let leading: String
    let trailing: String
    let text: String

    var body: some View {
        Slider(value: $value, in: range) {
            Text(title)
        } minimumValueLabel: {
            Text(leading)
        } maximumValueLabel: {
            Text(trailing)
        } onEditingChanged: { editing in
            isEditing = editing
        }

        Text(text)
            .foregroundColor(isEditing ? .orange : .blue).fixedSize()
    }
}

struct VideoPickerButton: View {
    let title: String
    let onCompletion: (Result<[Foundation.URL], any Error>) -> Void
    @State private var isPresented = false

    var body: some View {
        Button(title) {
            isPresented.toggle()
        }
        .fileImporter(isPresented: $isPresented, allowedContentTypes: [.video, .movie], allowsMultipleSelection: false, onCompletion: onCompletion)
        .buttonStyle(BorderedProminentButtonStyle())
    }
}

/*struct Views: View {
    var body: some View {
        Group {
            CustomSlider(...)
        }
    }
}

struct Views_Previews: PreviewProvider {
    static var previews: some View {
        Views()
    }
}*/

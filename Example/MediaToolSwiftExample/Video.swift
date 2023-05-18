//
//  Video.swift
//  MediaToolSwiftExample
//
//  Created by Dmitry Starkov on 12/05/2023.
//

import Foundation
import CoreTransferable

struct Video: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            return SentTransferredFile(video.url)
        } importing: { data in
            let name = data.file.lastPathComponent
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent(name)

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.copyItem(at: data.file, to: destination)

            return .init(url: destination)
        }
    }
}

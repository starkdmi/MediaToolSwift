//
//  ContentView.swift
//  MediaToolSwiftExample
//
//  Created by Dmitry Starkov on 12/05/2023.
//

import SwiftUI
import MediaToolSwift
import PhotosUI
import AVKit

struct ContentView: View {
    @State private var sourceURL: URL?
    @State private var outputURL: URL?
    @State private var selectedVideos: [PhotosPickerItem] = []

    // Settings
    @State private var tab: Int = 0
    @State private var task: CompressionTask?
    @State private var progress: Double?
    @State private var error: CompressionError?
    @State private var isErrorAlertPresented = false
    // File
    @State private var fileType: CompressionFileType = .mov
    @State private var overwrite = false
    @State private var sourceFilesize: Double? // MB
    @State private var outputFilesize: Double? // MB
    // Video
    @State private var videoCodec: AVVideoCodecType = .hevc
    @State private var resolution: CGSize = .zero
    @State private var frameRate = 0.0
    private let frameRateRange: ClosedRange<Double> = 15...60 // -1...240
    @State private var preserveAlphaChannel = true
    @State private var useHardwareAcceleration = true
    @State private var bitrate: CompressionVideoBitrate = .auto
    @State private var customBitrate = 0.0 // kbit/s
    // Audio
    @State private var skipAudio = false
    @State private var audioCodec: CompressionAudioCodec = .default
    @State private var audioBitrate = 0.0 // kbit/s
    // Playback
    let sourcePlayer = AVQueuePlayer()
    let outputPlayer = AVQueuePlayer()
    @State private var isPaused = true

    var body: some View {
        if sourceURL == nil {
            // Video picker
            PhotosPicker(selection: $selectedVideos, maxSelectionCount: 1, matching: .videos) {
                Text("Select video from Photos")
            }
            .onChange(of: selectedVideos) { items in
                if items.count == 1 {
                    items.first!.loadTransferable(type: Video.self) { result in
                        switch result {
                        case .success(let data):
                            sourceURL = data?.url
                            sourceFilesize = sourceURL?.fileSizeInMB
                        case .failure(let error):
                            print(error)
                            self.error = CompressionError(description: error.localizedDescription)
                            isErrorAlertPresented = true
                        }
                    }
                }
            }

            // File Picker
            VideoPickerButton(title: "Select video from Files", onCompletion: pickerCompletion)
        } else {
            VStack {
                HStack(spacing: 12) {
                    if let url = sourceURL {
                        Text("File: ").foregroundColor(.gray) +
                        Text(url.lastPathComponent).foregroundColor(.blue)
                    }

                    Button("Choose another video") {
                        selectedVideos = []
                        sourceURL = nil
                        reset()
                    }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .disabled(progress != nil && error == nil)
                }.padding(.bottom, 8)

                if let url = sourceURL {
                    // Tab switch
                    Picker("", selection: $tab) {
                        Text("Video").tag(0)
                        Text("Audio").tag(1)
                        Text("File").tag(2)
                        if outputURL != nil {
                            Text("Preview").tag(3)
                        }
                    }.pickerStyle(.segmented).frame(maxWidth: width - 32)

                    // Video Settings
                    if tab == 0 {
                        VStack(alignment: .center) {
                            // Video Codec
                            HStack(spacing: 0) {
                                #if os(iOS)
                                Text("Video Codec:")
                                #endif

                                Picker("Video Codec", selection: $videoCodec) {
                                    Text("HEVC").tag(AVVideoCodecType.hevc)
                                    Text("H.264").tag(AVVideoCodecType.h264)
                                    Text("Prores").tag(AVVideoCodecType.proRes4444)
                                    Text("JPEG").tag(AVVideoCodecType.jpeg)
                                }.pickerStyle(.menu).frame(maxWidth: 160)
                            }

                            // Resolution
                            HStack(spacing: 0) {
                                #if os(iOS)
                                Text("Resolution:")
                                #endif

                                Picker("Resolution", selection: $resolution) {
                                    Text("Original").tag(CGSize.zero)
                                    Text("4K (UHD)").tag(CGSize.uhd)
                                    Text("1080p (Full HD)").tag(CGSize.fhd)
                                    Text("720p (HD)").tag(CGSize.hd)
                                    Text("480p (SD)").tag(CGSize.sd)
                                }.pickerStyle(.menu).frame(maxWidth: 200)
                            }

                            // Bitrate of ouput video, used only by H.264 and H.265/HEVC codecs
                            HStack(spacing: 0) {
                                #if os(iOS)
                                Text("Bitrate:")
                                #endif
                                Picker("Bitrate", selection: $bitrate) {
                                    Text("Auto").tag(CompressionVideoBitrate.auto)
                                    Text("Encoder").tag(CompressionVideoBitrate.encoder)
                                    Text("Custom").tag(CompressionVideoBitrate.value(0))
                                }
                                #if os(OSX)
                                .pickerStyle(.inline)
                                #endif
                            }

                            if case .value = bitrate {
                                CustomSlider(value: $customBitrate, range: 100...10000,
                                             title: "Bitrate",
                                             leading: "100",
                                             trailing: "10000",
                                             text: "\(Int(customBitrate.rounded())) kbit/s"
                                )
                                .frame(maxWidth: width - 32)
                                .padding(.bottom)
                            }

                            // Frame rate
                            let frameRateText = frameRate < frameRateRange.lowerBound + 1 ? "Auto" : "\(Int(frameRate))"
                            #if os(iOS)
                            Text("Frame Rate: \(frameRateText)")
                            #endif
                            CustomSlider(value: $frameRate, range: frameRateRange,
                                         title: "Frame Rate",
                                         leading: "Auto",
                                         trailing: "\(frameRateRange.upperBound)",
                                         text: textIfOSX(frameRateText)
                            ).frame(maxWidth: width - 32)

                            // Preserve Alpha Channel or not
                            Toggle(isOn: $preserveAlphaChannel) {
                                Text("Alpha channel")
                            }.frame(maxWidth: 180)
                            #if os(OSX)
                            .toggleStyle(.checkbox)
                            #endif

                            #if os(OSX)
                            // Hardware Acceleration
                            Toggle(isOn: $useHardwareAcceleration) {
                                Text("Hardware Acceleration")
                            }.frame(maxWidth: 240)
                            .toggleStyle(.checkbox)
                            #endif
                        }
                    }

                    // Audio Settings
                    if tab == 1 {
                        // Skip Audio
                        Toggle(isOn: $skipAudio) {
                            Text("Disable Audio")
                        }.frame(maxWidth: 180)
                        #if os(OSX)
                        .toggleStyle(.checkbox)
                        #endif

                        if !skipAudio {
                            // Audio Codec
                            HStack(spacing: 0) {
                                #if os(iOS)
                                Text("Audio Format:")
                                #endif

                                Picker("Audio Format", selection: $audioCodec) {
                                    Text("Auto").tag(CompressionAudioCodec.default)
                                    Text("AAC").tag(CompressionAudioCodec.aac)
                                    Text("Opus").tag(CompressionAudioCodec.opus)
                                    Text("FLAC").tag(CompressionAudioCodec.flac)
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: 200)
                            }

                            // Audio bitrate in bits
                            if audioCodec == .aac || audioCodec == .opus {
                                #if os(iOS)
                                Text("Bitrate")
                                #endif
                                let range: ClosedRange<Double> = audioCodec == .aac ? 63...320 : 5...512
                                CustomSlider(value: $audioBitrate, range: range,
                                             title: "Bitrate",
                                             leading: "Auto",
                                             trailing: "\(range.upperBound)",
                                             text: audioBitrate < range.lowerBound + 1.0 ? "Auto" : "\(Int(audioBitrate.rounded())) kbit/s"
                                )
                                .frame(maxWidth: width - 32)
                                .onChange(of: audioCodec) { codec in
                                    audioBitrate = codec == .aac ? 63.0 : 5.0
                                }
                            }
                        }
                    }

                    if tab == 2 {
                        // File Type
                        HStack(spacing: 0) {
                            #if os(iOS)
                            Text("File Type:")
                            #endif

                            Picker("File Type", selection: $fileType) {
                                Text("QuickTime - mov").tag(CompressionFileType.mov)
                                Text("MPEG-4 - mp4").tag(CompressionFileType.mp4)
                                Text("iTunes - m4v").tag(CompressionFileType.m4v)
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 200)
                        }

                        // Overwrite destination
                        Toggle(isOn: $overwrite) {
                            Text("Overwrite")
                        }.frame(maxWidth: 180)
                        #if os(OSX)
                        .toggleStyle(.checkbox)
                        #endif
                    }

                    // Video Preview Player
                    if tab == 3 {
                        HStack {
                            Spacer()

                            // Source
                            VStack {
                                GeometryReader { geometry in
                                    PlayerView(avPlayer: sourcePlayer, url: url, size: geometry.size, isPaused: $isPaused)
                                }
                                #if os(iOS)
                                .frame(maxWidth: width / 2 - 32)
                                #else
                                .frame(width: 240)
                                #endif
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray, lineWidth: 2)
                                )

                                Text(sourceFilesize == nil ? " " : "Size: \(sourceFilesize!, specifier: "%.1f") MB").foregroundColor(.gray)
                            }

                            // Compressed
                            if let outputURL = outputURL {
                                VStack {
                                    GeometryReader { geometry in
                                        PlayerView(avPlayer: outputPlayer, url: outputURL, size: geometry.size, isPaused: $isPaused)
                                    }
                                    #if os(iOS)
                                    .frame(maxWidth: width / 2 - 32)
                                    #else
                                    .frame(width: 240)
                                    #endif
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.gray, lineWidth: 2)
                                    )

                                    Text(outputFilesize == nil ? " " : "Size: \(outputFilesize!, specifier: "%.1f") MB").foregroundColor(.gray)
                                }
                            }

                            Spacer()
                        }

                        // Video controls
                        HStack {
                            Button("Play") {
                                isPaused = false
                                sourcePlayer.play()
                                if outputURL != nil {
                                    outputPlayer.play()
                                }
                            }

                            Button("Pause") {
                                isPaused = true
                                sourcePlayer.pause()
                                if outputURL != nil {
                                    outputPlayer.pause()
                                }
                            }
                        }
                    }

                    Spacer()

                    HStack {
                        Button("Compress", action: compress)
                            .buttonStyle(BorderedProminentButtonStyle())
                            .disabled(progress != nil && error == nil)

                        if progress != nil && error == nil {
                            Button("Cancel") {
                                task?.cancel()
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                            .tint(.red)
                        }
                    }

                    if let progress = progress, error == nil {
                        Text("Progress: ").foregroundColor(.gray) + Text("\(progress * 100.0, specifier: "%.0f")%").foregroundColor(.blue)
                    }
                }
            }
            .padding()
            .alert(isPresented: $isErrorAlertPresented, error: error) {
                Button("OK", role: .cancel, action: reset)
            }
        }
    }

    private func reset() {
        task = nil
        progress = nil
        error = nil
        tab = 0
        outputURL = nil
    }

    private var width: CGFloat {
        #if os(OSX)
        NSScreen.main!.frame.size.width
        #else
        UIScreen.main.bounds.width
        #endif
    }

    private func textIfOSX(_ text: String) -> String {
        #if os(iOS)
        ""
        #else
        text
        #endif
    }

    private func pickerCompletion(_ result: Result<[Foundation.URL], any Error>) {
        if let urls = try? result.get(), let url = urls.first {
            sourceURL = url
            sourceFilesize = url.fileSizeInMB
        } else {
            error = CompressionError(description: "Failed to select video file")
            isErrorAlertPresented = true
        }
    }

    private func compress() {
        guard let url = sourceURL else { return }
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            error = CompressionError(description: "Cannot access cache directory")
            isErrorAlertPresented = true
            return
        }

        let destination = URL(fileURLWithPath: "\(directory.path)/\(url.lastPathComponent).\(fileType.rawValue)")
        print("Destination: \(destination.path)")

        var videoBitrate = bitrate
        if case .value = bitrate {
            videoBitrate = .value(Int(customBitrate) * 1000)
        }

        let videoSettings = CompressionVideoSettings(
            codec: videoCodec,
            bitrate: videoBitrate,
            size: resolution == .zero ? nil : resolution,
            frameRate: frameRate < frameRateRange.lowerBound + 1 ? nil : Int(frameRate),
            preserveAlphaChannel: preserveAlphaChannel,
            hardwareAcceleration: useHardwareAcceleration ? .auto : .disabled
        )

        let audioSettings = CompressionAudioSettings(
            codec: audioCodec,
            bitrate: audioBitrate < (audioCodec == .aac ? 64.0 : 6.0) ? nil : Int(audioBitrate) * 1000
        )

        Task {
            reset()
            task = await VideoTool.convert(
                source: url,
                destination: destination,
                fileType: fileType,
                videoSettings: videoSettings,
                skipAudio: skipAudio,
                audioSettings: audioSettings,
                // By default XCode remove the metadata from output file, to prevent:
                // Go to Build Settings tab, Under the "Other C Flags" section, add the following flag: -fno-strip-metadata
                skipSourceMetadata: false,
                copyExtendedFileMetadata: true,
                overwrite: overwrite,
                callback: { state in
                    switch state {
                    case .started:
                        print("Started")
                        self.progress = 0.0
                        break
                    case .progress(let progress):
                        // print("Progress: \(progress.fractionCompleted)")
                        self.progress = progress.fractionCompleted
                        break
                    case .completed(let url):
                        print("Done: \(url.absoluteString)")
                        self.progress = nil
                        self.outputURL = url
                        outputFilesize = url.fileSizeInMB
                        // Preview
                        tab = 3
                        self.isPaused = false
                        sourcePlayer.play()
                        outputPlayer.play()
                        break
                    case .failed(let error):
                        self.progress = nil
                        if let error = error as? CompressionError {
                            print("Error: \(error.description)")
                            self.error = error
                            isErrorAlertPresented = true
                        } else {
                            // Objective-C NSException
                            print("Error: \(error.localizedDescription)")
                            self.error = CompressionError(description: error.localizedDescription)
                            isErrorAlertPresented = true
                        }
                        break
                    case .cancelled:
                        print("Cancelled")
                        self.progress = nil
                        self.error = CompressionError(description: "Cancelled")
                        isErrorAlertPresented = true
                        break
                    }
                }
            )
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        #if os(OSX)
        ContentView()
        #else
        Group {
            ContentView()

            ContentView()
                .previewDevice("iPad mini (6th generation)")
        }
        #endif
    }
}

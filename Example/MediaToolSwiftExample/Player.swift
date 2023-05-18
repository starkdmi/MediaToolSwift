//
//  Player.swift
//  MediaToolSwiftExample
//
//  Created by Dmitry Starkov on 12/05/2023.
//

import SwiftUI
import AVKit

class Player {
    private let size: CGSize
    private var player: AVQueuePlayer!
    private var playerLayer: AVPlayerLayer!
    private var looper: AVPlayerLooper!

    init(player: AVQueuePlayer, url: URL, size: CGSize? = nil) {
        self.player = player
        self.size = size ?? CGSize(width: 100, height: 100)
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        playerLayer = AVPlayerLayer(player: player)
    }

    func makeView() -> Any {
        #if os(iOS)
        let backgroundColor = UIColor.clear.cgColor
        #else
        let backgroundColor = NSColor.clear.cgColor
        #endif

        // Setup video player layer
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = backgroundColor
        playerLayer.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        // playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

        // Parent view
        #if os(iOS)
        let view = UIView()
        let layer = view.layer
        #else
        let view = NSView()
        view.layer = CALayer()
        let layer = view.layer!
        #endif
        layer.backgroundColor = backgroundColor
        layer.addSublayer(playerLayer)

        return view
    }

    func updateView() {
        player.play()
    }
}

#if os(iOS)
struct PlayerView: UIViewRepresentable {
    private let player: Player!
    private let url: URL
    private let size: CGSize?
    private let isPaused: Binding<Bool>

    init(avPlayer: AVQueuePlayer, url: URL, size: CGSize? = nil, isPaused: Binding<Bool>) {
        self.url = url
        self.size = size
        self.isPaused = isPaused
        player = Player(player: avPlayer, url: url, size: size)
    }

    func makeUIView(context: Context) -> UIView {
        player.makeView() as! UIView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if !isPaused.wrappedValue {
            player.updateView()
        }
    }
}
#else
struct PlayerView: NSViewRepresentable {
    typealias NSViewType = NSView

    private let player: Player!
    private let url: URL
    private let size: CGSize?
    private let isPaused: Binding<Bool>

    init(avPlayer: AVQueuePlayer, url: URL, size: CGSize? = nil, isPaused: Binding<Bool>) {
        self.url = url
        self.size = size
        self.isPaused = isPaused
        player = Player(player: avPlayer, url: url, size: size)
    }

    func makeNSView(context: Context) -> NSView {
        player.makeView() as! NSView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if !isPaused.wrappedValue {
            player.updateView()
        }
    }
}
#endif

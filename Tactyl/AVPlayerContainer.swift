//
//  AVPlayerContainer.swift
//  Tactyl
//
//  Created by Ashish Patil on 31/08/25.
//

import Foundation

import SwiftUI
import AVKit

struct AVPlayerContainer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> UIView {
        let view = PlayerUIView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? PlayerUIView)?.playerLayer.player = player
    }

    class PlayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }

        var playerLayer: AVPlayerLayer {
            return layer as! AVPlayerLayer
        }
    }
}

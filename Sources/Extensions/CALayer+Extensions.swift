import Foundation
import AVFoundation
import QuartzCore

/// Public extension on `CALayer`
public extension CALayer {
    /// Set animation for property
    /// - keyPath: animatable property key path
    /// - id: unique id
    /// - fromValue: value to animate from, previous is used for `nil`
    /// - toValue: value to animate to
    /// - atTime: start time in seconds
    /// - duration: animation duration
    func animate(_ keyPath: String, id: String?, fromValue: Any? = nil, toValue: Any?, atTime: CFTimeInterval = AVCoreAnimationBeginTimeAtZero, duration: CFTimeInterval = 0.0) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.duration = duration // fade-in and fade-out duration
        animation.fromValue = fromValue
        animation.toValue = toValue
        // https://developer.apple.com/documentation/avfoundation/avvideocompositioncoreanimationtool
        animation.beginTime = atTime == 0.0 ? AVCoreAnimationBeginTimeAtZero : atTime
        animation.isRemovedOnCompletion = false // to keep animated value after animation finished
        animation.fillMode = .forwards
        self.add(animation, forKey: id)
    }

    /// Apply present/dismiss animations on layer
    func setTimeRangeAnimation(from: Double, to: Double?, opacity: Float) {
        guard from != .zero || to != nil else { return }

        if from != .zero {
            // appears hidden
            self.opacity = 0.0
            self.animate("opacity", id: "animateFadeIn", fromValue: 0.0, toValue: opacity, atTime: from) // show
            if let to = to {
                self.animate("opacity", id: "animateFadeOut", fromValue: opacity, toValue: 0.0, atTime: to) // hide
            }
        } else {
            // appears visible
            self.opacity = opacity
            self.animate("opacity", id: "animateFadeOut", fromValue: opacity, toValue: 0.0, atTime: to!) // hide
        }
    }
}

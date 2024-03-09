//
//  Progress+Extensions.swift
//
//
//  Created by Dmitry Starkov on 10/03/2024.
//

import Foundation

/// Internal extensions on `Progress`
internal extension Progress {

    /// Calculate estimated remaining time
    /// - Parameters:
    ///   - startedAt: initial time of progress
    ///   - offset: offset for more accurate time calculation, in percentage
    func estimateRemainingTime(startedAt: Date, offset: Double) -> TimeInterval? {
        let fractionCompleted = self.fractionCompleted
        if fractionCompleted > 0.0, fractionCompleted > offset {
            let timeElapsed = Date().timeIntervalSince(startedAt)
            let fractionRemaining = 1.0 - fractionCompleted
            let timeRemaining = timeElapsed / fractionCompleted * fractionRemaining
            return timeRemaining
        }
        return nil
    }
}

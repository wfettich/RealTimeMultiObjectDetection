//
//  FPSCounter.swift
//  RT_MultiObjectDetection
//
//  Created by Claude on 07.11.2025.
//

import Foundation
import QuartzCore

class FPSCounter {

    // MARK: - Properties

    private var frameCount = 0
    private var lastUpdateTime: TimeInterval = 0
    private var currentFPS: Double = 0

    var fps: Double {
        return currentFPS
    }

    // MARK: - Methods

    /// Returns true if FPS value was updated this tick
    func tick() -> Bool {
        let currentTime = CACurrentMediaTime()

        // Initialize on first frame
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return false
        }

        frameCount += 1

        // Update FPS every second
        let elapsedTime = currentTime - lastUpdateTime
        if elapsedTime >= 1.0 {
            currentFPS = Double(frameCount) / elapsedTime
            frameCount = 0
            lastUpdateTime = currentTime
            return true
        }

        return false
    }

    func reset() {
        frameCount = 0
        lastUpdateTime = 0
        currentFPS = 0
    }
}

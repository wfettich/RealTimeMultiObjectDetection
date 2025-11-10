//
//  ObjectDetector.swift
//  RT_MultiObjectDetection
//
//  Created by Walter Fettich on 07.11.2025.
//

import Foundation
import Vision
import CoreML
import UIKit

class VisionObjectDetector: DetectorProtocol {

    // MARK: - Properties

    private var visionModel: VNCoreMLModel?
    private let confidenceThreshold: Float = 0.3

    var lastInferenceTime: TimeInterval = 0

    // MARK: - Initialization

    init() {
        setupModel()
    }

    private func setupModel() {
        do {
            let config = MLModelConfiguration()
            // Use CPU for baseline - we'll optimize this later
            config.computeUnits = .all

            let model = try YOLOv3Tiny(configuration: config)
            visionModel = try VNCoreMLModel(for: model.model)
        } catch {
            print("Failed to load model: \(error.localizedDescription)")
        }
    }

    // MARK: - Detection

    func detect(in pixelBuffer: CVPixelBuffer, completion: @escaping ([Detection], TimeInterval) -> Void) {
        guard let model = visionModel else {
            completion([], 0)
            return
        }

        let startTime = CACurrentMediaTime()

        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self = self else { return }

            let inferenceTime = CACurrentMediaTime() - startTime

            if let error = error {
                print("Detection error: \(error.localizedDescription)")
                completion([], inferenceTime)
                return
            }

            let detections = self.processResults(request.results)
            completion(detections, inferenceTime)
        }

        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("Failed to perform detection: \(error.localizedDescription)")
            completion([], 0)
        }
    }

    private func processResults(_ results: [Any]?) -> [Detection] {
        guard let results = results as? [VNRecognizedObjectObservation] else {
            return []
        }

        var detections: [Detection] = []

        for observation in results {
            guard let topLabel = observation.labels.first,
                  topLabel.confidence >= confidenceThreshold else {
                continue
            }

            // Convert from normalized coordinates to CGRect
            let boundingBox = observation.boundingBox

            let detection = Detection(
                boundingBox: boundingBox,
                label: topLabel.identifier,
                confidence: topLabel.confidence
            )

            detections.append(detection)
        }

        return detections
    }
}

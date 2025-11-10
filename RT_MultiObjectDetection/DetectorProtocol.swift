//
//  DetectorProtocol.swift
//  RT_MultiObjectDetection
//
//  Created by Walter Fettich on 07.11.2025.
//

import Foundation
import CoreVideo
import CoreGraphics

struct Detection {
    let boundingBox: CGRect
    let label: String
    let confidence: Float
}

protocol DetectorProtocol {
    var lastInferenceTime: TimeInterval { get }
    func detect(in pixelBuffer: CVPixelBuffer, completion: @escaping ([Detection], TimeInterval) -> Void)
}

enum ModelType: String, CaseIterable {
    case yoloV3Tiny = "YOLOv3-Tiny (Vision)"
    case mobileNetV2 = "MobileNetV2 (Direct CoreML)"

    var modelName: String {
        switch self {
        case .yoloV3Tiny:
            return "YOLOv3Tiny"
        case .mobileNetV2:
            return "MobileNetV2_SSDLite"
        }
    }

    var modelSize: String {
        switch self {
        case .yoloV3Tiny:
            return "35.5 MB"
        case .mobileNetV2:
            return "8.8 MB"
        }
    }

    var framework: String {
        switch self {
        case .yoloV3Tiny:
            return "Vision + CoreML"
        case .mobileNetV2:
            return "CoreML Direct"
        }
    }

    var inputSize: String {
        switch self {
        case .yoloV3Tiny:
            return "416x416"
        case .mobileNetV2:
            return "300x300"
        }
    }
}

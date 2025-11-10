//
//  DirectCoreMLDetector.swift
//  RT_MultiObjectDetection
//
//  Created by Walter Fettich on 07.11.2025.
//

import Foundation
import CoreML
import CoreVideo
import CoreImage
import QuartzCore

/// Direct CoreML detector that bypasses Vision framework for full control
///
/// Why bypass Vision framework:
/// - Full control over preprocessing (manual resize, normalization)
/// - No Vision framework overhead (Vision adds ~5-10ms per inference)
/// - Direct access to raw model outputs (no post-processing by Vision)
/// - Can optimize for specific model architectures
/// - Better understanding of the full ML pipeline
///
/// Trade-offs:
/// - More code to maintain (manual NMS, coordinate parsing, etc.)
/// - Need to understand model's specific input/output format
/// - Vision provides convenience (automatic preprocessing, easier API)
class DirectCoreMLDetector: DetectorProtocol {

    // MARK: - Properties

    /// The loaded CoreML model instance (MLModel, not VNCoreMLModel)
    /// Direct MLModel access allows manual feature input/output handling
    private var model: MLModel?

    /// Image preprocessor for manual resizing before inference
    /// Handles camera frame (e.g., 1920x1080) → model input (e.g., 300x300)
    private let preprocessor: ImagePreprocessor

    /// Minimum confidence to keep a detection (0-1 range)
    /// Detections below this threshold are filtered out
    /// 0.3 = 30% confidence minimum
    private let confidenceThreshold: Float = 0.3

    /// Model's expected input dimension (e.g., 300 for MobileNetV2, 416 for YOLO)
    /// Used to initialize preprocessor with correct target size
    private let modelInputSize: Int

    /// Time taken for last inference (in seconds)
    /// Updated after each detect() call for performance monitoring
    var lastInferenceTime: TimeInterval = 0

    /// Model type for determining which output processing to use
    /// Different models have different output formats:
    /// - YOLO: Outputs all anchor boxes [1, 1917, 91], requires manual NMS
    /// - MobileNet: Outputs pre-filtered detections [N, 4], NMS already applied
    enum DetectorModelType {
        case yolo
        case mobilenet
    }
    private let modelType: DetectorModelType

    // MARK: - Initialization

    /// Initialize detector with a specific CoreML model
    ///
    /// - Parameters:
    ///   - modelName: Name of .mlmodel or .mlpackage file in bundle (without extension)
    ///   - inputSize: Square input dimension expected by model (default: 300 for MobileNetV2)
    ///   - modelType: Type of model architecture for appropriate output processing (default: .mobilenet)
    init(modelName: String, inputSize: Int = 300, modelType: DetectorModelType = .mobilenet) {
        self.modelInputSize = inputSize
        self.modelType = modelType
        // Create preprocessor to resize images to model's expected input size
        self.preprocessor = ImagePreprocessor(targetWidth: inputSize, targetHeight: inputSize)
        setupModel(modelName: modelName)
    }

    /// Load CoreML model from app bundle
    ///
    /// Loads the model file and configures compute units (CPU/GPU/Neural Engine)
    ///
    /// - Parameter modelName: Model file name without extension
    ///
    /// Model formats:
    /// - .mlmodelc: Compiled model (Xcode compiles .mlmodel → .mlmodelc automatically)
    /// - .mlpackage: New format for iOS 14+ with better Neural Engine support
    private func setupModel(modelName: String) {
        do {
            // Configure which hardware to use for inference
            let config = MLModelConfiguration()
            // .all = Let iOS choose best compute unit (CPU, GPU, or Neural Engine)
            // Alternatives: .cpuOnly, .cpuAndGPU, .cpuAndNeuralEngine
            config.computeUnits = .all

            // Find model in app bundle
            // Try .mlmodelc first (compiled), fallback to .mlpackage (iOS 14+)
            // Bundle.main.url: Searches in app's Resources folder
            guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") ??
                                  Bundle.main.url(forResource: modelName, withExtension: "mlpackage") else {
                print("Failed to find model: \(modelName)")
                return
            }

            // Load the model from file URL
            // MLModel is the base CoreML class (no Vision wrapper)
            // This loads model into memory and prepares for inference
            model = try MLModel(contentsOf: modelURL, configuration: config)
            print("✅ Loaded model: \(modelName)")
        } catch {
            print("Failed to load model: \(error.localizedDescription)")
        }
    }

    // MARK: - Detection

    /// Detect objects in a camera frame
    ///
    /// Pipeline: Preprocess → CoreML Inference → Parse Results → NMS → Return
    ///
    /// - Parameters:
    ///   - pixelBuffer: Camera frame (any size, typically 1920x1080)
    ///   - completion: Callback with detected objects and inference time
    ///
    /// This is the main entry point that orchestrates:
    /// 1. Manual preprocessing (resize to model input size)
    /// 2. Direct CoreML inference (no Vision wrapper)
    /// 3. Raw output parsing (confidence + coordinates arrays)
    /// 4. Non-Maximum Suppression to remove duplicates
    func detect(in pixelBuffer: CVPixelBuffer, completion: @escaping ([Detection], TimeInterval) -> Void) {
        // Ensure model is loaded
        guard let model = model else {
            completion([], 0)
            return
        }

        // Start timing for performance measurement
        // CACurrentMediaTime(): High-resolution timer in seconds since boot
        let startTime = CACurrentMediaTime()

        // Step 1: Preprocess image (resize from camera size to model input size)
        // Example: 1920x1080 → 300x300 for MobileNetV2
        guard let preprocessedBuffer = preprocessor.preprocess(pixelBuffer) else {
            completion([], 0)
            return
        }

        do {
            // Step 2: Create CoreML input feature
            // MLFeatureValue wraps the pixel buffer as a CoreML-compatible input
            let input = try MLFeatureValue(pixelBuffer: preprocessedBuffer)

            // MLDictionaryFeatureProvider maps feature names to values
            // "image" is the input name defined in the CoreML model
            // (different models may use different input names)
            let inputFeatures = try MLDictionaryFeatureProvider(dictionary: ["image": input])

            // Step 3: Run inference - THE ACTUAL ML COMPUTATION HAPPENS HERE
            // model.prediction() executes the neural network on CPU/GPU/Neural Engine
            // Returns MLFeatureProvider with model outputs (confidence, coordinates)
            let prediction = try model.prediction(from: inputFeatures)

            // Calculate total inference time (preprocessing + model execution)
            let inferenceTime = CACurrentMediaTime() - startTime

            // Step 4: Process raw model outputs into Detection objects
            // This includes parsing arrays, filtering by confidence, and applying NMS
            // Switch processing based on model type
            let detections: [Detection]
            switch modelType {
            case .yolo:
                detections = processResultsYOLO(prediction)
            case .mobilenet:
                detections = processResultsMobileNet(prediction)
            }

            // Return results via completion handler
            completion(detections, inferenceTime)

        } catch {
            print("Prediction error: \(error.localizedDescription)")
            completion([], CACurrentMediaTime() - startTime)
        }
    }

    /// Parse raw CoreML model outputs into Detection objects (for YOLO-style models)
    ///
    /// YOLO/SSD models with anchor-based architecture output format:
    ///
    /// Model Architecture (SSD - Single Shot Detector):
    /// - Uses 1917 "anchor boxes" (pre-defined potential object locations)
    /// - For each anchor, predicts: confidence for 91 classes + bounding box adjustment
    ///
    /// Output format:
    /// - confidence: [1, 1917, 91] - probability for each class at each anchor
    ///   - Dimension 0: batch (always 1 for single image)
    ///   - Dimension 1: anchor index (0-1916)
    ///   - Dimension 2: class index (0=background, 1-90=COCO classes)
    /// - coordinates: [1, 1917, 4] - bounding box for each anchor
    ///   - Dimension 0: batch (always 1)
    ///   - Dimension 1: anchor index (0-1916)
    ///   - Dimension 2: [ymin, xmin, ymax, xmax] in normalized 0-1 coordinates
    ///
    /// - Parameter prediction: Raw CoreML output (MLFeatureProvider)
    /// - Returns: Array of Detection objects after filtering and NMS
    private func processResultsYOLO(_ prediction: MLFeatureProvider) -> [Detection] {
        var detections: [Detection] = []

        // Extract the two output arrays from CoreML prediction
        // featureValue(for:): Gets output by name (defined in CoreML model)
        // multiArrayValue: Converts to MLMultiArray (multi-dimensional array)
        guard let confidenceArray = prediction.featureValue(for: "confidence")?.multiArrayValue,
              let coordinatesArray = prediction.featureValue(for: "coordinates")?.multiArrayValue else {
            print("Failed to get model outputs")
            return []
        }

        // Get array dimensions from the shape property
        // shape: Array of NSNumbers describing each dimension
        // shape[0] = batch size (1), shape[1] = anchors (1917), shape[2] = classes (91)
        let numAnchors = confidenceArray.shape[1].intValue    // 1917 anchor boxes
        let numClasses = confidenceArray.shape[2].intValue    // 91 classes (0=background + 90 COCO)

        // Loop through all 1917 anchor boxes
        for anchor in 0..<numAnchors {
            // Find the class with highest confidence for this anchor
            var maxConfidence: Float = 0
            var maxClass: Int = 0

            // Search through all classes (skip index 0 = background)
            for classIndex in 1..<numClasses {
                // Access 3D array: [batch=0, anchor=current, class=current]
                // Must use [NSNumber] for MLMultiArray subscript
                let confidenceIndex = [0, anchor, classIndex] as [NSNumber]
                let confidence = confidenceArray[confidenceIndex].floatValue

                // Track highest confidence and its class
                if confidence > maxConfidence {
                    maxConfidence = confidence
                    maxClass = classIndex
                }
            }

            // Filter out low-confidence detections
            // If max confidence < threshold (0.3), this anchor likely has no object
            if maxConfidence < confidenceThreshold {
                continue
            }

            // Extract bounding box coordinates from coordinates array
            // Order: [ymin, xmin, ymax, xmax] - specific to this model!
            // Coordinates are normalized (0-1 range, relative to image dimensions)
            let ymin = coordinatesArray[[0, anchor, 0] as [NSNumber]].floatValue
            let xmin = coordinatesArray[[0, anchor, 1] as [NSNumber]].floatValue
            let ymax = coordinatesArray[[0, anchor, 2] as [NSNumber]].floatValue
            let xmax = coordinatesArray[[0, anchor, 3] as [NSNumber]].floatValue

            // Convert to CGRect for easier manipulation
            // Note: Coordinates are already normalized (0-1), no conversion needed
            // width = xmax - xmin, height = ymax - ymin
            let boundingBox = CGRect(
                x: CGFloat(xmin),
                y: CGFloat(ymin),
                width: CGFloat(xmax - xmin),
                height: CGFloat(ymax - ymin)
            )

            // Map class index to human-readable label
            // min() prevents out-of-bounds if model returns invalid class
            let label = cocoClassNames[min(maxClass, cocoClassNames.count - 1)]

            // Create Detection object with parsed data
            let detection = Detection(
                boundingBox: boundingBox,
                label: label,
                confidence: maxConfidence
            )

            detections.append(detection)
        }

        // Apply Non-Maximum Suppression to remove overlapping duplicate detections
        // IOU threshold 0.5 = remove boxes with >50% overlap
        return applyNMS(detections, iouThreshold: 0.5)
    }

    /// Parse raw CoreML model outputs for MobileNetV2_SSDLite (Apple's format)
    ///
    /// Apple's MobileNetV2_SSDLite typically outputs pre-filtered detections:
    /// - Model does NMS internally, only returns top N detections (not all anchors)
    /// - Common output names: "confidence"/"scores" and "coordinates"/"boxes"
    /// - Output shapes vary: could be [N], [1, N], [N, 4], [1, N, 4]
    ///
    /// This function includes debug logging to discover the actual format
    ///
    /// - Parameter prediction: Raw CoreML output (MLFeatureProvider)
    /// - Returns: Array of Detection objects (already filtered by model's NMS)
    private func processResultsMobileNet(_ prediction: MLFeatureProvider) -> [Detection] {
        var detections: [Detection] = []

        // DEBUG: Log all available output names to discover actual format
        print("🔍 DEBUG: MobileNetV2 output feature names:")
        for featureName in prediction.featureNames {
            print("  - \(featureName)")
            if let featureValue = prediction.featureValue(for: featureName) {
                // Log the type of each output
                if let multiArray = featureValue.multiArrayValue {
                    print("    Type: MLMultiArray")
                    print("    Shape: \(multiArray.shape)")
                    print("    DataType: \(multiArray.dataType.rawValue)")
                } else {
                    print("    Type: \(type(of: featureValue))")
                }
            }
        }

        // Try common output names for MobileNetV2 models
        // Apple's models typically use "confidence" and "coordinates"
        guard let confidenceArray = prediction.featureValue(for: "confidence")?.multiArrayValue ??
                                      prediction.featureValue(for: "scores")?.multiArrayValue else {
            print("❌ Failed to get confidence/scores output")
            print("   Available outputs: \(prediction.featureNames)")
            return []
        }

        guard let coordinatesArray = prediction.featureValue(for: "coordinates")?.multiArrayValue ??
                                      prediction.featureValue(for: "boxes")?.multiArrayValue else {
            print("❌ Failed to get coordinates/boxes output")
            print("   Available outputs: \(prediction.featureNames)")
            return []
        }

        // DEBUG: Log shapes to understand format
        print("🔍 Confidence shape: \(confidenceArray.shape)")
        print("🔍 Coordinates shape: \(coordinatesArray.shape)")

        // Determine array dimensions based on shape
        let confidenceShape = confidenceArray.shape
        let coordinatesShape = coordinatesArray.shape

        // MobileNetV2_SSDLite format is:
        // - confidence: [num_detections, num_classes] e.g., [2, 90]
        // - coordinates: [num_detections, 4] e.g., [2, 4]
        // NOT [1, N] or [N] - it's [N, num_classes]!

        guard confidenceShape.count == 2 else {
            print("❌ Unexpected confidence shape: \(confidenceShape), expected [N, num_classes]")
            return []
        }

        guard coordinatesShape.count == 2 else {
            print("❌ Unexpected coordinates shape: \(coordinatesShape), expected [N, 4]")
            return []
        }

        // Extract dimensions
        let numDetections = confidenceShape[0].intValue   // First dimension = number of detections
        let numClasses = confidenceShape[1].intValue      // Second dimension = number of classes

        print("🔍 Processing \(numDetections) detections with \(numClasses) classes each")

        // Process each detection
        for detectionIdx in 0..<numDetections {
            // Find the class with highest confidence for this detection
            var maxConfidence: Float = 0
            var maxClassIdx: Int = 0

            for classIdx in 0..<numClasses {
                let confidence = confidenceArray[[detectionIdx as NSNumber, classIdx as NSNumber]].floatValue
                if confidence > maxConfidence {
                    maxConfidence = confidence
                    maxClassIdx = classIdx
                }
            }

            // Filter by confidence threshold
            if maxConfidence < confidenceThreshold {
                continue
            }

            // Extract coordinates [ymin, xmin, ymax, xmax] in normalized 0-1 range
            let ymin = coordinatesArray[[detectionIdx as NSNumber, 0]].floatValue
            let xmin = coordinatesArray[[detectionIdx as NSNumber, 1]].floatValue
            let ymax = coordinatesArray[[detectionIdx as NSNumber, 2]].floatValue
            let xmax = coordinatesArray[[detectionIdx as NSNumber, 3]].floatValue

            // Convert to CGRect (coordinates already normalized 0-1)
            let boundingBox = CGRect(
                x: CGFloat(xmin),
                y: CGFloat(ymin),
                width: CGFloat(xmax - xmin),
                height: CGFloat(ymax - ymin)
            )

            // Map class index to COCO label
            // MobileNetV2 outputs 90 classes WITHOUT background (indices 0-89)
            // cocoClassNames has background at index 0, so we need to offset by +1
            // MobileNetV2 class 0 = cocoClassNames[1] = "person"
            let labelIndex = maxClassIdx + 1
            let label = labelIndex < cocoClassNames.count ? cocoClassNames[labelIndex] : "object"

            let detection = Detection(
                boundingBox: boundingBox,
                label: label,
                confidence: maxConfidence
            )

            detections.append(detection)
        }

        print("🔍 Found \(detections.count) detections above threshold")

        // MobileNetV2 typically does NMS internally, but apply it anyway to be safe
        return applyNMS(detections, iouThreshold: 0.5)
    }

    // MARK: - Non-Maximum Suppression

    /// Apply Non-Maximum Suppression to remove duplicate/overlapping detections
    ///
    /// Problem: Object detection models often detect the same object multiple times
    /// with slightly different bounding boxes. We need to remove duplicates.
    ///
    /// NMS Algorithm:
    /// 1. Sort all detections by confidence (highest first)
    /// 2. Keep the highest-confidence detection
    /// 3. Remove all detections that significantly overlap with it (IoU > threshold)
    /// 4. Repeat for remaining detections
    ///
    /// Example:
    /// - Detection A: "person" 0.9 confidence, box at (0.2, 0.3, 0.1, 0.2)
    /// - Detection B: "person" 0.7 confidence, box at (0.21, 0.31, 0.09, 0.19) <- 80% overlap
    /// Result: Keep A, discard B (they're detecting the same person)
    ///
    /// - Parameters:
    ///   - detections: All detections from model (may include duplicates)
    ///   - iouThreshold: Overlap threshold (0.5 = remove boxes with >50% overlap)
    /// - Returns: Filtered list with duplicates removed
    private func applyNMS(_ detections: [Detection], iouThreshold: Float) -> [Detection] {
        guard !detections.isEmpty else { return [] }

        // Sort by confidence descending - highest confidence detections first
        // This ensures we keep the "best" detection when removing duplicates
        let sorted = detections.sorted { $0.confidence > $1.confidence }

        // Array to store detections we're keeping
        var keep: [Detection] = []

        // Process each detection in confidence order
        for detection in sorted {
            var shouldKeep = true

            // Check if this detection overlaps significantly with any kept detection
            for kept in keep {
                // Calculate Intersection over Union (IoU) - measure of overlap
                let iou = calculateIOU(detection.boundingBox, kept.boundingBox)

                // If IoU > threshold, boxes overlap too much = likely same object
                if iou > iouThreshold {
                    shouldKeep = false
                    break  // No need to check other boxes
                }
            }

            // If detection doesn't overlap with any kept detection, keep it
            if shouldKeep {
                keep.append(detection)
            }
        }

        return keep
    }

    /// Calculate Intersection over Union (IoU) between two bounding boxes
    ///
    /// IoU measures how much two boxes overlap:
    /// - IoU = (Intersection Area) / (Union Area)
    /// - Range: 0 (no overlap) to 1 (perfect overlap)
    ///
    /// Visual example:
    /// ```
    /// Box A: ┌────────┐
    ///        │        │
    /// Box B: │  ┌─────┼────┐
    ///        │  │▓▓▓▓▓│    │  ▓ = Intersection
    ///        └──┼─────┘    │
    ///           │          │
    ///           └──────────┘
    ///
    /// Intersection = shaded area (▓)
    /// Union = total area covered by both boxes
    /// IoU = intersection / union
    /// ```
    ///
    /// - Parameters:
    ///   - box1: First bounding box
    ///   - box2: Second bounding box
    /// - Returns: IoU value (0-1), where 1 = boxes are identical
    private func calculateIOU(_ box1: CGRect, _ box2: CGRect) -> Float {
        // CGRect.intersection(): Computes overlapping rectangle
        // Returns a rectangle representing where the two boxes overlap
        let intersection = box1.intersection(box2)

        // isNull: True if boxes don't overlap at all
        guard !intersection.isNull else {
            return 0  // No overlap = IoU is 0
        }

        // Calculate area of overlapping region
        let intersectionArea = intersection.width * intersection.height

        // Calculate union: total area covered by both boxes
        // Union = Area(box1) + Area(box2) - Intersection
        // (subtract intersection because it's counted twice otherwise)
        let unionArea = box1.width * box1.height + box2.width * box2.height - intersectionArea

        // IoU = Intersection / Union
        return Float(intersectionArea / unionArea)
    }

    // MARK: - COCO Class Names

    private let cocoClassNames = [
        "background", "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "street sign", "stop sign", "parking meter", "bench", "bird", "cat",
        "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "hat", "backpack", "umbrella",
        "shoe", "eye glasses", "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball",
        "kite", "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle",
        "plate", "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich",
        "orange", "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch", "potted plant",
        "bed", "mirror", "dining table", "window", "desk", "toilet", "door", "tv", "laptop", "mouse",
        "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink", "refrigerator",
        "blender", "book", "clock", "vase", "scissors", "teddy bear", "hair drier", "toothbrush", "hair brush"
    ]
}

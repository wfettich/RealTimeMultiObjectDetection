//
//  DetectionOverlayView.swift
//  RT_MultiObjectDetection
//
//  Created by Claude on 07.11.2025.
//

import UIKit

class DetectionOverlayView: UIView {

    // MARK: - Properties

    private var detections: [Detection] = []

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    // MARK: - Public Methods

    func update(with detections: [Detection]) {
        self.detections = detections
        setNeedsDisplay()
    }

    func clear() {
        detections = []
        setNeedsDisplay()
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard let context = UIGraphicsGetCurrentContext() else { return }

        for detection in detections {
            drawBoundingBox(detection, in: context)
        }
    }

    private func drawBoundingBox(_ detection: Detection, in context: CGContext) {
        // Convert normalized coordinates (0-1) to view coordinates
        // Note: Vision uses bottom-left origin, UIKit uses top-left
        let viewWidth = bounds.width
        let viewHeight = bounds.height

        let x = detection.boundingBox.minX * viewWidth
        let y = (1 - detection.boundingBox.maxY) * viewHeight
        let width = detection.boundingBox.width * viewWidth
        let height = detection.boundingBox.height * viewHeight

        let rect = CGRect(x: x, y: y, width: width, height: height)

        // Draw bounding box
        context.setStrokeColor(UIColor.green.cgColor)
        context.setLineWidth(3.0)
        context.stroke(rect)

        // Draw label background
        let label = "\(detection.label) \(Int(detection.confidence * 100))%"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor.white
        ]

        let labelSize = label.size(withAttributes: attributes)
        let labelRect = CGRect(
            x: x,
            y: max(0, y - labelSize.height - 4),
            width: labelSize.width + 8,
            height: labelSize.height + 4
        )

        // Draw label background
        context.setFillColor(UIColor.green.withAlphaComponent(0.8).cgColor)
        context.fill(labelRect)

        // Draw label text
        let textPoint = CGPoint(x: labelRect.minX + 4, y: labelRect.minY + 2)
        label.draw(at: textPoint, withAttributes: attributes)
    }
}

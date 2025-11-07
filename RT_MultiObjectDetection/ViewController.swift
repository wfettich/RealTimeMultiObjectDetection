//
//  ViewController.swift
//  RT_MultiObjectDetection
//
//  Created by Walter Fettich on 07.11.2025.
//

import UIKit
import AVFoundation

class ViewController: UIViewController {

    // MARK: - Properties

    private let cameraManager = CameraManager()
    private let fpsCounter = FPSCounter()
    private let objectDetector = ObjectDetector()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var detectionOverlay: DetectionOverlayView!

    // UI Elements
    private let fpsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.text = "FPS: 0.0"
        return label
    }()

    private let inferenceLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        label.font = UIFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.text = "Inference: 0ms"
        return label
    }()

    private let toggleButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Start Camera", for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
        return button
    }()

    private var isCameraRunning = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .black

        // Add detection overlay
        detectionOverlay = DetectionOverlayView(frame: view.bounds)
        detectionOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(detectionOverlay)

        // Add FPS label
        view.addSubview(fpsLabel)
        NSLayoutConstraint.activate([
            fpsLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            fpsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fpsLabel.widthAnchor.constraint(equalToConstant: 120),
            fpsLabel.heightAnchor.constraint(equalToConstant: 40)
        ])

        // Add inference label
        view.addSubview(inferenceLabel)
        NSLayoutConstraint.activate([
            inferenceLabel.topAnchor.constraint(equalTo: fpsLabel.bottomAnchor, constant: 8),
            inferenceLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            inferenceLabel.widthAnchor.constraint(equalToConstant: 160),
            inferenceLabel.heightAnchor.constraint(equalToConstant: 40)
        ])

        // Add toggle button
        view.addSubview(toggleButton)
        NSLayoutConstraint.activate([
            toggleButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32),
            toggleButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])

        toggleButton.addTarget(self, action: #selector(toggleCamera), for: .touchUpInside)
    }

    private func setupCamera() {
        cameraManager.delegate = self

        // Request camera permission
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted else {
                DispatchQueue.main.async {
                    self?.showCameraPermissionAlert()
                }
                return
            }
            
            
            // Setup camera
            self?.cameraManager.setupCamera { [weak self] success in
                guard let self = self, success else {
                    print("Failed to setup camera")
                    return
                }
                
                DispatchQueue.main.async {
                    // Add preview layer
                    let preview = self.cameraManager.previewLayer
                    preview.frame = self.view.bounds
                    self.view.layer.insertSublayer(preview, at: 0)
                    self.previewLayer = preview
                }
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleCamera() {
        if isCameraRunning {
            stopCamera()
        } else {
            startCamera()
        }
    }

    private func startCamera() {
        cameraManager.startCamera()
        fpsCounter.reset()
        isCameraRunning = true
        toggleButton.setTitle("Stop Camera", for: .normal)
        toggleButton.setTitleColor(.black, for: .normal)
        toggleButton.backgroundColor = .systemRed
    }

    private func stopCamera() {
        cameraManager.stopCamera()
        fpsCounter.reset()
        isCameraRunning = false
        toggleButton.setTitle("Start Camera", for: .normal)
        toggleButton.setTitleColor(.white, for: .normal)
        toggleButton.backgroundColor = .systemBlue
        updateFPSLabel(fps: 0.0)
        updateInferenceLabel(time: 0.0)
        detectionOverlay.clear()
    }

    private func updateFPSLabel(fps: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.fpsLabel.text = String(format: "FPS: %.1f", fps)
        }
    }

    private func updateInferenceLabel(time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            self?.inferenceLabel.text = String(format: "Inference: %.0fms", time * 1000)
        }
    }

    private func showCameraPermissionAlert() {
        let alert = UIAlertController(
            title: "Camera Access Required",
            message: "Please enable camera access in Settings to use this app.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Settings", style: .default) { _ in
            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(settingsURL)
            }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
}

// MARK: - CameraManagerDelegate

extension ViewController: CameraManagerDelegate {

    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
        // Update FPS counter - only update UI when FPS value changes (once per second)
        if fpsCounter.tick() {
            updateFPSLabel(fps: fpsCounter.fps)
        }

        // Get pixel buffer from sample buffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        // Run object detection
        objectDetector.detect(in: pixelBuffer) { [weak self] detections, inferenceTime in
            guard let self = self else { return }

            // Update UI with results
            DispatchQueue.main.async {
                self.detectionOverlay.update(with: detections)
                self.updateInferenceLabel(time: inferenceTime)
            }
        }
    }
}


//
//  CameraManager.swift
//  RT_MultiObjectDetection
//
//  Created by Walter Fettich on 07.11.2025.
//

import AVFoundation
import UIKit

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
}

class CameraManager: NSObject {

    // MARK: - Properties

    weak var delegate: CameraManagerDelegate?

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.wf.cameraSessionQueue")
    private var videoOutput: AVCaptureVideoDataOutput?

    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    var isRunning: Bool {
        return captureSession.isRunning
    }

    // MARK: - Setup

    func setupCamera(completion: @escaping (Bool) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                // Configure session
                self.captureSession.beginConfiguration()
                self.captureSession.sessionPreset = .high

                // Add camera input
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }

                let cameraInput = try AVCaptureDeviceInput(device: camera)

                if self.captureSession.canAddInput(cameraInput) {
                    self.captureSession.addInput(cameraInput)
                } else {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }

                // Add video output
                let videoOutput = AVCaptureVideoDataOutput()
                videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
                videoOutput.alwaysDiscardsLateVideoFrames = false
                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]

                if self.captureSession.canAddOutput(videoOutput) {
                    self.captureSession.addOutput(videoOutput)
                    self.videoOutput = videoOutput

                    // Set video orientation
                    if let connection = videoOutput.connection(with: .video) {
                        connection.videoOrientation = .portrait
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(false)
                    }
                    return
                }

                self.captureSession.commitConfiguration()

                DispatchQueue.main.async {
                    completion(true)
                }

            } catch {
                print("Error setting up camera: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }

    // MARK: - Camera Control

    func startCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
        }
    }

    func stopCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        delegate?.cameraManager(self, didOutput: sampleBuffer)
    }
}

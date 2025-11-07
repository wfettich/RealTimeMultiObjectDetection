# RT_MultiObjectDetection

Real-time multi-object detection iOS app with adaptive performance optimization. This project demonstrates production-ready computer vision techniques with a focus on performance, thermal management, and battery efficiency.

## Overview

RT_MultiObjectDetection is a camera-based iOS application that detects and tracks multiple objects simultaneously using machine learning. The app identifies 80 different object classes (people, vehicles, animals, household items, etc.) and displays bounding boxes with confidence scores in real-time.

**Key Features:**
- Live camera feed with real-time object detection
- Visual bounding boxes and labels overlaid on detected objects
- Performance metrics display (FPS, inference time)
- Built with UIKit and AVFoundation
- YOLOv3-Tiny CoreML model for object detection

## Current Implementation Status

### ✅ Step 1: Basic Camera Capture (Complete)
- AVCaptureSession with live camera preview
- Real-time FPS counter
- Start/Stop camera controls
- **Baseline Performance**: 30+ FPS without ML processing

### ✅ Step 2: Basic Object Detection (Complete)
- Vision framework integration with CoreML
- YOLOv3-Tiny model (35.5 MB, 80 object classes)
- Real-time bounding box rendering
- Inference time tracking
- **Current Performance**: 10-20 FPS with object detection (intentionally unoptimized baseline)

### 🔄 Planned: Advanced Optimizations
- Multi-threaded inference pipeline (separate queues for capture, preprocessing, inference, postprocessing)
- Adaptive frame rate system (60fps → 30fps → 15fps based on battery/thermal state)
- Metal shaders for GPU-accelerated preprocessing
- Memory-mapped model weights
- Custom CoreML integration (bypassing Vision framework overhead)

## Technical Architecture

**Current Stack:**
- **Language**: Swift 5.0
- **UI Framework**: UIKit with Storyboards
- **Camera**: AVFoundation (AVCaptureSession)
- **ML Framework**: Vision + CoreML
- **Model**: YOLOv3-Tiny (quantized, 80 classes)
- **Deployment Target**: iOS 26.1

**Performance Metrics:**
- FPS Counter: Tracks camera frame rate
- Inference Timer: Measures ML processing time per frame
- Real-time display: Both metrics shown on-screen

## Project Structure

```
RT_MultiObjectDetection/
├── AppDelegate.swift           # Application lifecycle
├── SceneDelegate.swift         # Scene management
├── ViewController.swift        # Main UI and detection pipeline
├── CameraManager.swift         # AVCaptureSession wrapper
├── FPSCounter.swift           # Frame rate tracking utility
├── ObjectDetector.swift       # Vision/CoreML inference
├── DetectionOverlayView.swift # Bounding box rendering
├── YOLOv3Tiny.mlmodel         # CoreML object detection model (via Git LFS)
└── Info.plist                 # App configuration (includes camera permissions)
```

## Building and Running

### Prerequisites
- Xcode 26.1 or later
- macOS 15.0 (Sequoia) or later
- iOS Simulator or iOS device with iOS 26.1+

### Build Commands

```bash
# Build for simulator
xcodebuild -project RT_MultiObjectDetection.xcodeproj \
  -scheme RT_MultiObjectDetection \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# Run tests
xcodebuild test -project RT_MultiObjectDetection.xcodeproj \
  -scheme RT_MultiObjectDetection \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Running in Xcode
1. Open `RT_MultiObjectDetection.xcodeproj`
2. Select your target device/simulator
3. Press ⌘R to build and run
4. Grant camera permissions when prompted
5. Tap "Start Camera" to begin detection

## Performance Goals

### Baseline (Current)
- **FPS**: 10-20 fps
- **Inference Time**: 50-100ms per frame
- **Purpose**: Establishes "before" metrics for optimization

### Target (After Optimization)
- **FPS**: 30+ fps sustained
- **Inference Time**: <30ms per frame
- **Battery Drain**: <5% per hour of continuous use
- **CPU Usage**: <25% average
- **Thermal State**: Maintains "nominal" during 30-min operation
- **Energy Impact**: "Low" range in Instruments

## Model Information

**YOLOv3-Tiny**
- Size: 35.5 MB
- Input: 416x416 RGB image
- Output: Bounding boxes + class labels + confidence scores
- Classes: 80 (COCO dataset - person, car, dog, chair, etc.)
- Source: [Apple's Core ML Models](https://developer.apple.com/machine-learning/models/)
- Storage: Git LFS (tracked via .gitattributes)

## Git LFS Setup

This repository uses Git LFS to store the CoreML model efficiently:

```bash
# Install Git LFS (if not already installed)
brew install git-lfs

# Initialize Git LFS in your repository
git lfs install

# The .gitattributes file already tracks *.mlmodel files
# Pull LFS files after cloning
git lfs pull
```

## UI Overview

**On-Screen Elements:**
- **FPS Label** (top-left): Camera capture frame rate
- **Inference Label** (below FPS): ML processing time in milliseconds
- **Bounding Boxes**: Green boxes around detected objects with labels
- **Labels**: Show class name and confidence percentage (e.g., "person 85%")
- **Start/Stop Button** (bottom-center): Camera control

## Known Limitations (Baseline)

These are **intentional** for establishing baseline performance:
- No frame skipping (every frame processed)
- Frames delivered on main thread
- No preprocessing optimization
- Generic compute units (.all) instead of targeted hardware
- No multi-threading in inference pipeline
- Vision framework overhead included

These will be addressed in future optimization steps.

## Development Notes

- See `CLAUDE.md` for detailed technical architecture and development guidelines
- Model file must be added to Xcode project target for CoreML compilation
- Camera permissions are required (configured in Info.plist)
- Test on actual hardware for accurate performance metrics (simulator performance varies)

## License

This is a demonstration/portfolio project showcasing iOS computer vision techniques.

## Author

Created as a technical demonstration of real-time object detection with adaptive performance optimization on iOS.

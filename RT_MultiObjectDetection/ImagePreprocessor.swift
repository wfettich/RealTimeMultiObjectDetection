//
//  ImagePreprocessor.swift
//  RT_MultiObjectDetection
//
//  Created by Walter Fettich on 07.11.2025.
//

import Foundation
import CoreVideo
import CoreImage
import Accelerate

/// Handles manual image preprocessing for CoreML models
/// Provides two resize methods: CoreImage (GPU) and vImage (CPU with SIMD)
///
/// When to use which:
/// - CoreImage: Good for complex transforms, uses GPU, may have sync overhead
/// - vImage: Faster for simple operations, uses CPU SIMD, deterministic performance
class ImagePreprocessor {

    // MARK: - Properties

    /// Target width for model input (e.g., 300 for MobileNetV2, 416 for YOLO)
    private let targetWidth: Int

    /// Target height for model input (usually same as width for square inputs)
    private let targetHeight: Int

    /// CIContext for GPU-accelerated image operations
    /// - useSoftwareRenderer: false = forces GPU rendering for better performance
    /// - Reused across frames to avoid recreation overhead
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Initialization

    init(targetWidth: Int, targetHeight: Int) {
        self.targetWidth = targetWidth
        self.targetHeight = targetHeight
    }

    // MARK: - Preprocessing

    /// Resize and normalize pixel buffer for CoreML input
    /// Returns a new CVPixelBuffer ready for model inference
    ///
    /// - Parameter pixelBuffer: Input camera frame (typically 1920x1080 or similar)
    /// - Returns: Resized pixel buffer matching model input dimensions, or nil if resize fails
    ///
    /// Note: Normalization (0-1 range) is handled automatically by CoreML for most models
    func preprocess(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        // Resize pixel buffer from camera dimensions (e.g., 1920x1080) to model input size (e.g., 300x300)
        guard let resizedBuffer = resize(pixelBuffer, to: CGSize(width: targetWidth, height: targetHeight)) else {
            return nil
        }

        // Most CoreML models expect pixel values normalized to 0-1 range
        // CoreML handles this automatically during inference, so we just return the resized buffer
        return resizedBuffer
    }

    /// Resize pixel buffer to target dimensions using CoreImage (GPU-accelerated)
    ///
    /// Uses CoreImage + GPU for image scaling. Good for complex transforms, but may have
    /// CPU/GPU synchronization overhead. For simple resize, vImage may be faster.
    ///
    /// - Parameters:
    ///   - pixelBuffer: Source pixel buffer to resize
    ///   - size: Target dimensions (e.g., 300x300)
    /// - Returns: New resized pixel buffer, or nil if operation fails
    private func resize(_ pixelBuffer: CVPixelBuffer, to size: CGSize) -> CVPixelBuffer? {
        // Wrap CVPixelBuffer in CIImage for CoreImage processing
        // CIImage is a lazy representation - no pixel data copied yet
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Get source dimensions from the pixel buffer
        // CVPixelBufferGetWidth/Height: Returns the width/height in pixels
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)

        // Calculate scaling factors for width and height
        // For example: 1920x1080 → 300x300 = scaleX: 0.156, scaleY: 0.278
        // Note: This does NOT preserve aspect ratio (image will be stretched)
        let scaleX = size.width / CGFloat(sourceWidth)
        let scaleY = size.height / CGFloat(sourceHeight)

        // Apply affine transform to scale the image
        // CGAffineTransform creates a 2D transformation matrix
        // This is still a lazy operation - no pixels processed yet
        let resizedImage = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Create a new CVPixelBuffer to hold the resized output
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,              // Memory allocator (default is fine)
            Int(size.width),                  // Width in pixels
            Int(size.height),                 // Height in pixels
            kCVPixelFormatType_32BGRA,        // Pixel format: 32-bit BGRA (8 bits per channel)
            nil,                              // Pixel buffer attributes (none needed)
            &outputBuffer                     // Output parameter - receives created buffer
        )

        // Check if buffer creation succeeded (kCVReturnSuccess = 0)
        guard status == kCVReturnSuccess, let buffer = outputBuffer else {
            return nil
        }

        // ACTUALLY perform the resize by rendering to the output buffer
        // This triggers GPU execution of the transform we defined above
        // CIContext.render() writes the final pixels to the CVPixelBuffer
        context.render(resizedImage, to: buffer)

        return buffer
    }

    /// Alternative resize using vImage (CPU with SIMD optimizations)
    ///
    /// Uses Accelerate framework's vImage for CPU-based image scaling with SIMD instructions.
    /// Often faster than CoreImage for simple resize operations because:
    /// - No CPU/GPU synchronization overhead
    /// - Uses SIMD (Single Instruction Multiple Data) for parallel pixel processing
    /// - Deterministic performance (no GPU contention)
    ///
    /// Trade-off: Uses CPU instead of GPU, so may impact other CPU-bound tasks
    ///
    /// - Parameters:
    ///   - pixelBuffer: Source pixel buffer to resize
    ///   - size: Target dimensions (e.g., 300x300)
    /// - Returns: New resized pixel buffer, or nil if operation fails
    func resizeUsingVImage(_ pixelBuffer: CVPixelBuffer, to size: CGSize) -> CVPixelBuffer? {
        // Lock the pixel buffer to get access to raw memory
        // .readOnly flag: We won't modify source buffer, only read from it
        // This prevents other threads from accessing the buffer during resize
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)

        // defer: Ensures unlock happens when function exits (even on early return)
        // This is critical - forgetting to unlock causes memory/performance issues
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // Get pointer to the raw pixel data in memory
        // Returns UnsafeMutableRawPointer? to the first byte of pixel data
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        // Get source buffer dimensions and memory layout
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        // bytesPerRow: Number of bytes in one row of pixels
        // Usually width * 4 (for BGRA) but may include padding for alignment
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Create vImage_Buffer struct that describes the source image layout in memory
        // vImage uses this to understand how pixels are arranged
        var sourceBuffer = vImage_Buffer(
            data: baseAddress,                           // Pointer to pixel data
            height: vImagePixelCount(sourceHeight),      // Height in pixels
            width: vImagePixelCount(sourceWidth),        // Width in pixels
            rowBytes: sourceBytesPerRow                  // Bytes per row (stride)
        )

        // Create a new CVPixelBuffer for the resized output
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,              // Default memory allocator
            Int(size.width),                  // Destination width
            Int(size.height),                 // Destination height
            kCVPixelFormatType_32BGRA,        // Same format as source (BGRA, 32 bits/pixel)
            nil,                              // No special attributes
            &outputBuffer                     // Output parameter
        )

        // Verify destination buffer was created successfully
        guard status == kCVReturnSuccess, let destPixelBuffer = outputBuffer else {
            return nil
        }

        // Lock destination buffer for write access
        // No flags = read+write access (we'll write resized pixels here)
        CVPixelBufferLockBaseAddress(destPixelBuffer, [])

        // Ensure we unlock when done (critical for memory management)
        defer { CVPixelBufferUnlockBaseAddress(destPixelBuffer, []) }

        // Get pointer to destination pixel data
        guard let destBaseAddress = CVPixelBufferGetBaseAddress(destPixelBuffer) else {
            return nil
        }

        // Get destination buffer's memory layout
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(destPixelBuffer)

        // Create vImage_Buffer for destination (describes output layout)
        var destBuffer = vImage_Buffer(
            data: destBaseAddress,                      // Pointer to output pixels
            height: vImagePixelCount(size.height),      // Output height
            width: vImagePixelCount(size.width),        // Output width
            rowBytes: destBytesPerRow                   // Output stride
        )

        // Perform the actual resize operation using SIMD-optimized code
        // vImageScale_ARGB8888: Scales 32-bit ARGB/BGRA images
        // - sourceBuffer: Input image (by reference with &)
        // - destBuffer: Output image (by reference with &)
        // - nil: No temp buffer needed (vImage allocates internally if required)
        // - kvImageHighQualityResampling: Use high-quality interpolation (Lanczos)
        //   Alternative flags: kvImageNoFlags (faster, lower quality)
        let error = vImageScale_ARGB8888(
            &sourceBuffer,
            &destBuffer,
            nil,
            vImage_Flags(kvImageHighQualityResampling)
        )

        // Check if scaling succeeded
        // kvImageNoError = 0 means success
        // Other error codes indicate memory issues, invalid dimensions, etc.
        guard error == kvImageNoError else {
            return nil
        }

        // Return the resized buffer
        // Note: Buffers will be unlocked automatically by defer statements
        return destPixelBuffer
    }
}

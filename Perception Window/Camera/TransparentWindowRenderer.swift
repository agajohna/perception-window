//
//  TransparentWindowRenderer.swift
//  Perception Window
//

import ARKit
import CoreImage
import CoreVideo
import Metal
import MetalKit
import simd

#if os(iOS)

struct TransparentWindowDrawContext {
    let pixelBuffer: CVPixelBuffer
    let snapshot: ARFrameSnapshot
    let warpEnabled: Bool
    let sceneReference: VirtualEyeGeometry.SceneReference?
    let lockedCameraPosition: SIMD3<Float>?
    let lockedViewerLateral: SIMD2<Float>?
    let warpLockBaselineDeltas: [SIMD2<Float>]?
    let perceptionState: PerceptionState?
    /// Sampled every render frame — avoids 15 Hz fusion stair-steps on head parallax.
    let liveViewerPose: ViewerPoseEstimate?
}

final class TransparentWindowRenderer: NSObject {
    private struct FullscreenUniforms {
        var inverseDisplayTransform: simd_float3x3
        var parallaxOffset: SIMD2<Float>
        var viewportSize: SIMD2<Float>
        var windowMagnification: Float
        var padding: Float = 0
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let fullscreenPipelineState: MTLRenderPipelineState
    private let ciContext: CIContext
    private var textureCache: CVMetalTextureCache?
    private var conversionBuffer: CVPixelBuffer?
    private var stagingTexture: MTLTexture?

    private static let metalCompatibleAttributes: CFDictionary = {
        [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ] as NSDictionary
    }()

    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount = 0

    private let gridSize: Int
    private let lock = NSLock()
    private var sceneReference: VirtualEyeGeometry.SceneReference?
    private var parallaxSmoother = GlassViewParallaxSmoother()
    private var lastLockPosition: SIMD3<Float>?

    init?(gridSize: Int = PerceptionConfiguration.transparentWindowGridSize) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue = device.makeCommandQueue()
        else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.gridSize = gridSize
        self.ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])

        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "transparentWindowVertex"),
              let fragmentFunction = library.makeFunction(name: "transparentWindowFragment"),
              let fullscreenVertexFunction = library.makeFunction(name: "transparentWindowFullscreenVertex"),
              let fullscreenFragmentFunction = library.makeFunction(name: "transparentWindowFullscreenFragment")
        else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }

        let fullscreenDescriptor = MTLRenderPipelineDescriptor()
        fullscreenDescriptor.vertexFunction = fullscreenVertexFunction
        fullscreenDescriptor.fragmentFunction = fullscreenFragmentFunction
        fullscreenDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        guard let fullscreenPipelineState = try? device.makeRenderPipelineState(descriptor: fullscreenDescriptor) else {
            return nil
        }

        self.pipelineState = pipelineState
        self.fullscreenPipelineState = fullscreenPipelineState
        super.init()

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        buildStaticMesh()
    }

    func setSceneReference(_ reference: VirtualEyeGeometry.SceneReference?) {
        lock.lock()
        sceneReference = reference
        lock.unlock()
    }

    func resetParallaxSmoothing() {
        lock.lock()
        parallaxSmoother.reset()
        lastLockPosition = nil
        lock.unlock()
    }

    func draw(context: TransparentWindowDrawContext, in view: MTKView) -> (
        presented: Bool,
        failureReason: String?,
        renderMode: String,
        maxUVShiftPixels: Float,
        reprojectionHits: Int,
        gridPointCount: Int,
        cameraDeltaMeters: Float,
        windowMagnification: Float
    ) {
        let reference = context.warpEnabled ? context.sceneReference : nil
        let lockPosition = context.lockedCameraPosition ?? reference?.anchorCameraPosition
        let cameraDeltaMeters: Float
        if let lockPosition {
            let delta = context.snapshot.cameraTransform.position - lockPosition
            cameraDeltaMeters = simd_length(delta)
        } else {
            cameraDeltaMeters = 0
        }

        let reprojectionEnabled = PerceptionConfiguration.usesViewpointReprojection

        guard
            let drawable = view.currentDrawable,
            let passDescriptor = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            let reason: String
            if view.currentDrawable == nil {
                reason = "no drawable"
            } else if view.currentRenderPassDescriptor == nil {
                reason = "no pass descriptor"
            } else {
                reason = "no command buffer"
            }
            return (false, reason, "none", 0, 0, 0, cameraDeltaMeters, 1)
        }

        let viewportSize = context.snapshot.viewportSize
        guard viewportSize.width > 0, viewportSize.height > 0 else {
            return (false, "zero viewport", "none", 0, 0, 0, cameraDeltaMeters, 1)
        }

        let useReprojection = reprojectionEnabled
            && !PerceptionConfiguration.glassViewForcePassthroughPreview
            && reference != nil

        var renderMode = "passthrough"
        var maxUVShiftPixels: Float = 0
        var reprojectionHits = 0
        var gridPointCount = 0
        var parallaxOffset = SIMD2<Float>(0, 0)
        var useFullscreen = true

        let viewerPose = resolvedViewerPose(for: context)
        let eyeDistance = viewerPose?.isValid == true
            ? viewerPose!.eyeToScreenDistanceMeters
            : PerceptionConfiguration.virtualEyeDistanceMeters
        var windowMagnification = VirtualEyeGeometry.windowMagnification(
            snapshot: context.snapshot,
            eyeDistanceMeters: eyeDistance
        )

        if useReprojection, let reference {
            if PerceptionConfiguration.glassViewUsePlanarMotionWarp {
                if let lockPosition {
                    if let previousLock = lastLockPosition,
                       simd_length(lockPosition - previousLock) > 0.002 {
                        parallaxSmoother.reset()
                    }
                    lastLockPosition = lockPosition

                    renderMode = viewerPose?.isValid == true
                        ? "planarParallax+head"
                        : "planarParallax"
                    let rawOffset = VirtualEyeGeometry.combinedParallaxUVOffset(
                        snapshot: context.snapshot,
                        lockCameraPosition: lockPosition,
                        sceneDepthMeters: reference.sceneDepthMeters,
                        viewerPose: viewerPose,
                        lockedViewerLateral: context.lockedViewerLateral,
                        exaggerationGain: PerceptionConfiguration.glassViewWarpExaggerationGain
                    )
                    let smoothed = parallaxSmoother.apply(
                        offset: rawOffset,
                        magnification: windowMagnification
                    )
                    parallaxOffset = smoothed.offset
                    windowMagnification = smoothed.magnification
                } else {
                    renderMode = "planarParallax (no lock)"
                }
                let width = Float(context.snapshot.viewportSize.width)
                let height = Float(context.snapshot.viewportSize.height)
                maxUVShiftPixels = hypot(parallaxOffset.x * width, parallaxOffset.y * height)
                reprojectionHits = 1
                gridPointCount = 1
            } else {
                useFullscreen = false
                renderMode = "reprojection"
                let grid = updateReprojectionMesh(
                    snapshot: context.snapshot,
                    reference: reference,
                    lockBaselineDeltas: context.warpLockBaselineDeltas
                )
                maxUVShiftPixels = grid.maxUVShiftPixels
                reprojectionHits = grid.reprojectionHits
                gridPointCount = grid.gridPointCount
                applyForcedWarpVisualization(warpEnabled: true, to: vertexBuffer)
            }
        }

        guard let texture = makeTexture(from: context.pixelBuffer) else {
            let format = CVPixelBufferGetPixelFormatType(context.pixelBuffer)
            let reason = "texture upload failed (fmt \(format))"
            return (false, reason, renderMode, maxUVShiftPixels, reprojectionHits, gridPointCount, cameraDeltaMeters, windowMagnification)
        }

        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDescriptor.colorAttachments[0].loadAction = .clear

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            return (false, "no encoder", renderMode, maxUVShiftPixels, reprojectionHits, gridPointCount, cameraDeltaMeters, windowMagnification)
        }

        if useFullscreen {
            var uniforms = FullscreenUniforms(
                inverseDisplayTransform: context.snapshot.inverseDisplayTransform.asInverseDisplayMatrix,
                parallaxOffset: parallaxOffset,
                viewportSize: SIMD2(
                    Float(context.snapshot.viewportSize.width),
                    Float(context.snapshot.viewportSize.height)
                ),
                windowMagnification: windowMagnification
            )
            encoder.setRenderPipelineState(fullscreenPipelineState)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FullscreenUniforms>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        } else {
            guard let vertexBuffer, let indexBuffer else {
                encoder.endEncoding()
                let reason = vertexBuffer == nil ? "no vertex buffer" : "no index buffer"
                return (false, reason, renderMode, maxUVShiftPixels, reprojectionHits, gridPointCount, cameraDeltaMeters, windowMagnification)
            }
            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(indexBuffer, offset: 0, index: 1)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indexCount,
                indexType: .uint16,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )
        }

        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
        return (true, nil, renderMode, maxUVShiftPixels, reprojectionHits, gridPointCount, cameraDeltaMeters, windowMagnification)
    }

    private func resolvedViewerPose(for context: TransparentWindowDrawContext) -> ViewerPoseEstimate? {
        if let live = context.liveViewerPose, live.isValid {
            return live
        }
        guard let fused = context.perceptionState?.viewerPose, fused.isValid else { return nil }
        return fused
    }

    /// Debug: WARP shifts the right half of the image — must be visible if Metal is on screen.
    private func applyForcedWarpVisualization(warpEnabled: Bool, to vertexBuffer: MTLBuffer?) {
        guard PerceptionConfiguration.glassViewDebugForcedSplitOffset,
              warpEnabled,
              let vertexBuffer else { return }

        struct GPUVertex {
            var position: SIMD2<Float>
            var cameraUV: SIMD2<Float>
            var valid: Float
            var padding: Float
        }

        let count = gridSize * gridSize
        let pointer = vertexBuffer.contents().bindMemory(to: GPUVertex.self, capacity: count)
        for index in 0..<count {
            guard pointer[index].valid > 0.5 else { continue }
            if pointer[index].position.x >= 0 {
                pointer[index].cameraUV.x = min(pointer[index].cameraUV.x + 0.22, 1)
            }
        }
    }

    private func buildStaticMesh() {
        struct GPUVertex {
            var position: SIMD2<Float>
            var cameraUV: SIMD2<Float>
            var valid: Float
            var padding: Float = 0
        }

        var vertices: [GPUVertex] = []
        var indices: [UInt16] = []

        for row in 0..<gridSize {
            for column in 0..<gridSize {
                let u = Float(column) / Float(gridSize - 1)
                let v = Float(row) / Float(gridSize - 1)
                let x = u * 2 - 1
                let y = 1 - v * 2
                vertices.append(GPUVertex(position: SIMD2(x, y), cameraUV: .zero, valid: 1))
            }
        }

        for row in 0..<(gridSize - 1) {
            for column in 0..<(gridSize - 1) {
                let topLeft = UInt16(row * gridSize + column)
                let topRight = UInt16(row * gridSize + column + 1)
                let bottomLeft = UInt16((row + 1) * gridSize + column)
                let bottomRight = UInt16((row + 1) * gridSize + column + 1)

                indices.append(contentsOf: [topLeft, bottomLeft, topRight, topRight, bottomLeft, bottomRight])
            }
        }

        indexCount = indices.count
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<GPUVertex>.stride * vertices.count,
            options: .storageModeShared
        )
        indexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * indices.count,
            options: .storageModeShared
        )
    }

    private func updateDirectPassthroughMesh() {
        guard let vertexBuffer else { return }

        struct GPUVertex {
            var position: SIMD2<Float>
            var cameraUV: SIMD2<Float>
            var valid: Float
            var padding: Float = 0
        }

        let pointer = vertexBuffer.contents().bindMemory(to: GPUVertex.self, capacity: gridSize * gridSize)

        for row in 0..<gridSize {
            for column in 0..<gridSize {
                let index = row * gridSize + column
                let u = Float(column) / Float(gridSize - 1)
                let v = Float(row) / Float(gridSize - 1)
                pointer[index].position = SIMD2(u * 2 - 1, 1 - v * 2)
                pointer[index].cameraUV = SIMD2(u, 1 - v)
                pointer[index].valid = 1
            }
        }
    }

    private func updatePassthroughMesh(inverseDisplayTransform: CGAffineTransform) {
        guard let vertexBuffer else { return }

        let samples = VirtualEyeGeometry.passthroughGrid(
            inverseDisplayTransform: inverseDisplayTransform,
            gridSize: gridSize
        )
        writeSamples(samples, to: vertexBuffer)
    }

    private func updateReprojectionMesh(
        snapshot: ARFrameSnapshot,
        reference: VirtualEyeGeometry.SceneReference,
        lockBaselineDeltas: [SIMD2<Float>]?
    ) -> VirtualEyeGeometry.SampleGridResult {
        guard let vertexBuffer else {
            return VirtualEyeGeometry.SampleGridResult(
                samples: [],
                maxUVShiftPixels: 0,
                reprojectionHits: 0,
                gridPointCount: 0,
                reprojectionDeltas: []
            )
        }

        let grid = VirtualEyeGeometry.makeSampleGrid(
            snapshot: snapshot,
            reference: reference,
            gridSize: gridSize,
            exaggerationGain: PerceptionConfiguration.glassViewWarpExaggerationGain,
            lockBaselineDeltas: lockBaselineDeltas
        )
        writeSamples(grid.samples, to: vertexBuffer)
        return grid
    }

    private func writeSamples(_ samples: [VirtualEyeGeometry.ScreenSample], to vertexBuffer: MTLBuffer) {
        struct GPUVertex {
            var position: SIMD2<Float>
            var cameraUV: SIMD2<Float>
            var valid: Float
            var padding: Float = 0
        }

        let pointer = vertexBuffer.contents().bindMemory(to: GPUVertex.self, capacity: gridSize * gridSize)

        for (index, sample) in samples.enumerated() {
            let u = sample.displayUV.x
            let v = sample.displayUV.y
            pointer[index].position = SIMD2(u * 2 - 1, 1 - v * 2)
            pointer[index].cameraUV = sample.cameraUV
            pointer[index].valid = sample.isValid ? 1 : 0
        }
    }

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        if format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            guard let bgra = convertToBGRA(pixelBuffer) else { return nil }
            return uploadBGRA(bgra)
        }

        return uploadBGRA(pixelBuffer)
    }

    private func uploadBGRA(_ pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        if let cached = makeBGRATextureFromCache(from: pixelBuffer) {
            return cached
        }
        return makeBGRATextureFromBytes(pixelBuffer)
    }

    private func convertToBGRA(_ yuvBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(yuvBuffer)
        let height = CVPixelBufferGetHeight(yuvBuffer)

        if conversionBuffer == nil
            || CVPixelBufferGetWidth(conversionBuffer!) != width
            || CVPixelBufferGetHeight(conversionBuffer!) != height {
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(
                kCFAllocatorDefault,
                width,
                height,
                kCVPixelFormatType_32BGRA,
                Self.metalCompatibleAttributes,
                &buffer
            )
            guard status == kCVReturnSuccess else { return nil }
            conversionBuffer = buffer
        }

        guard let conversionBuffer else { return nil }

        let image = CIImage(cvPixelBuffer: yuvBuffer)
        ciContext.render(
            image,
            to: conversionBuffer,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return conversionBuffer
    }

    private func makeBGRATextureFromCache(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache else { return nil }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    private func makeBGRATextureFromBytes(_ pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        if stagingTexture == nil
            || stagingTexture?.width != width
            || stagingTexture?.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: width,
                height: height,
                mipmapped: false
            )
            descriptor.usage = [.shaderRead]
            stagingTexture = device.makeTexture(descriptor: descriptor)
        }

        guard let texture = stagingTexture else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: baseAddress,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer)
        )
        return texture
    }
}

#endif

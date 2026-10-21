import AVFoundation
import Vision
import Combine
import Foundation

final class FocusDetectionManager: NSObject, ObservableObject {
    @Published var latestMetric: FocusMetric?
    @Published var attentionTrend: [FocusMetric] = []
    @Published var permissionDenied = false
    @Published var isUserVisible = true

    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let visionHandler = VNSequenceRequestHandler()
    private let analysisQueue = DispatchQueue(label: "focusweaver.camera.queue")

    private var blinkHistory: [Double] = []
    private var headPoseHistory: [Double] = []
    private var interruptions: Int = 0
    private var lastDistractionDate: Date?
    private var faceLossCounter: Int = 0

    override init() {
        super.init()
        configureSession()
    }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async { [weak self] in
                self?.permissionDenied = !granted
            }
            guard granted, let self else { return }
            self.analysisQueue.async { [weak self] in
                guard let self else { return }
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }
    }

    func stop() {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func registerDistraction() {
        interruptions += 1
    }

    func resetCounters() {
        interruptions = 0
        lastDistractionDate = nil
        faceLossCounter = 0
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.attentionTrend.removeAll()
            self.latestMetric = nil
            self.isUserVisible = true
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .medium

        guard let device = preferredVideoDevice(),
              let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]

        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        session.commitConfiguration()
    }

    private func preferredVideoDevice() -> AVCaptureDevice? {
        let builtInDiscovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        if let builtIn = builtInDiscovery.devices.first {
            return builtIn
        }

        if #available(macOS 14.0, *) {
            let externalDiscovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.external],
                mediaType: .video,
                position: .unspecified
            )
            return externalDiscovery.devices.first ?? AVCaptureDevice.default(for: .video)
        } else {
            let externalDiscovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.externalUnknown],
                mediaType: .video,
                position: .unspecified
            )
            return externalDiscovery.devices.first ?? AVCaptureDevice.default(for: .video)
        }
    }

    private func handle(observation: VNFaceObservation) {
        registerPresence()
        let yaw = observation.yaw?.doubleValue ?? 0
        let pitch = observation.pitch?.doubleValue ?? 0
        let roll = observation.roll?.doubleValue ?? 0
        let headVariance = (abs(yaw) + abs(pitch) + abs(roll)) / 3
        headPoseHistory.append(headVariance)
        headPoseHistory = headPoseHistory.suffix(30)

        let blinkRate = blinkProbability(from: observation)
        blinkHistory.append(blinkRate)
        blinkHistory = blinkHistory.suffix(60)

        let attentionScore = max(0, 1 - (headVariance * 1.2 + blinkRate * 0.5))
        if attentionScore < 0.35, shouldRegisterDistraction() {
            interruptions += 1
            lastDistractionDate = Date()
        }
        let metric = FocusMetric(
            attentionScore: attentionScore,
            blinkRate: blinkRate,
            headPoseVariance: headVariance,
            distractionsDetected: interruptions
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.latestMetric = metric
            self.attentionTrend.append(metric)
            self.attentionTrend = Array(self.attentionTrend.suffix(120))
        }
    }

    private func handleNoFace() {
        faceLossCounter += 1
        if faceLossCounter > 15 {
            DispatchQueue.main.async { [weak self] in
                self?.isUserVisible = false
            }
        }
    }

    private func registerPresence() {
        faceLossCounter = 0
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.isUserVisible {
                self.isUserVisible = true
            }
        }
    }

    private func blinkProbability(from observation: VNFaceObservation) -> Double {
        guard let leftEye = observation.landmarks?.leftEye?.normalizedPoints,
              let rightEye = observation.landmarks?.rightEye?.normalizedPoints else {
            return 0.2
        }
        let leftRatio = eyeAspectRatio(points: leftEye)
        let rightRatio = eyeAspectRatio(points: rightEye)
        let ratio = (leftRatio + rightRatio) / 2
        return min(1, max(0, (0.3 - ratio) * 4))
    }

    private func eyeAspectRatio(points: [CGPoint]) -> Double {
        guard points.count >= 6 else { return 0.25 }
        let top = (points[1].y + points[2].y) / 2
        let bottom = (points[4].y + points[5].y) / 2
        let height = abs(top - bottom)
        let left = points[0].x
        let right = points[3].x
        let width = abs(right - left)
        return Double(height / max(width, 0.01))
    }

    private func shouldRegisterDistraction() -> Bool {
        guard let lastDistractionDate else { return true }
        return Date().timeIntervalSince(lastDistractionDate) > 10
    }
}

extension FocusDetectionManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectFaceLandmarksRequest { [weak self] request, _ in
            if let observation = (request.results as? [VNFaceObservation])?.first {
                self?.handle(observation: observation)
            } else {
                self?.handleNoFace()
            }
        }

        do {
            try visionHandler.perform([request], on: pixelBuffer)
        } catch {
            print("Vision error: \(error.localizedDescription)")
        }
    }
}

extension FocusDetectionManager: @unchecked Sendable {}

import AVFoundation
import Vision
import CoreImage
import Combine

final class MovementCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var image: CGImage?
    @Published private(set) var pose: BodyPose?
    @Published private(set) var message = "准备好后，开启摄像头。"
    @Published private(set) var running = false
    var onPose: ((BodyPose?, TimeInterval) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "rise.movement.camera", qos: .userInitiated)
    private let context = CIContext()
    private var configured = false
    private var generation = 0 // Main thread only; invalidates queued permission/frame callbacks.
    private var lastFrame: TimeInterval = 0 // Camera queue only.
    private var streamGeneration = 0 // Camera queue only.
    private var observer: NSObjectProtocol?

    override init() {
        super.init()
        observer = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError, object: session, queue: .main
        ) { [weak self] _ in
            self?.stop()
            self?.message = "摄像头连接中断，请重新开启。"
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func start() {
        generation += 1
        let token = generation
        message = "正在连接摄像头…"
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: configureAndStart(token)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    if allowed { self.configureAndStart(token) }
                    else { self.message = "未获得摄像头权限，请在系统设置 → 隐私与安全性 → 摄像头中允许 RISE。" }
                }
            }
        default:
            message = "摄像头不可用，请在系统设置 → 隐私与安全性 → 摄像头中允许 RISE。"
        }
    }

    func stop() {
        generation += 1
        running = false
        image = nil
        pose = nil
        onPose?(nil, ProcessInfo.processInfo.systemUptime)
        queue.async { [weak self] in self?.session.stopRunning() }
    }

    private func configureAndStart(_ token: Int) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if !self.configured {
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }
                    self.session.sessionPreset = .vga640x480
                    guard let camera = AVCaptureDevice.default(for: .video) else {
                        throw CameraError.unavailable
                    }
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard self.session.canAddInput(input) else { throw CameraError.unavailable }
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    guard self.session.canAddOutput(output) else { throw CameraError.unavailable }
                    self.session.addInput(input)
                    self.session.addOutput(output)
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                        connection.automaticallyAdjustsVideoMirroring = false
                        connection.isVideoMirrored = false
                    }
                    self.configured = true
                }
                self.streamGeneration = token
                self.session.startRunning()
                let active = self.session.isRunning
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.running = active
                    self.message = active ? "请让头顶、双手和髋部都出现在画面中。" : "摄像头未能启动，请关闭其他占用摄像头的应用后重试。"
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.generation == token else { return }
                    self.message = "无法打开摄像头，请检查设备连接后重试。"
                }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 0.09,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let token = streamGeneration
        let request = VNDetectHumanBodyPoseRequest()
        var detected: BodyPose?
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            // Multiple people make ownership ambiguous; never count such frames.
            if let results = request.results, results.count == 1,
               let joints = try results.first?.recognizedPoints(.all) {
                let mapping: [(BodyJoint, VNHumanBodyPoseObservation.JointName)] = [
                    (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
                    (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
                    (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
                    (.leftHip, .leftHip), (.rightHip, .rightHip)
                ]
                var points: [BodyJoint: CGPoint] = [:]
                for (key, name) in mapping {
                    if let point = joints[name], point.confidence >= 0.45 { points[key] = point.location }
                }
                detected = BodyPose(points: points)
            }
        } catch { detected = nil }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let frame = context.createCGImage(ciImage, from: ciImage.extent)
        let result = detected
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.generation == token else { return }
            self.image = frame
            self.pose = result
            self.onPose?(result, now)
        }
    }

    private enum CameraError: Error { case unavailable }
}

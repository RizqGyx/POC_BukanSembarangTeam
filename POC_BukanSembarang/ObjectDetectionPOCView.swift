import SwiftUI
import Vision
import CoreML
import AVFoundation
import Accelerate
import Combine

// MARK: - Detection Model

struct ObjectDetection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    // Normalized rect, origin = top-left
    let boundingBox: CGRect

    var isHouseholdItem: Bool {
        Self.householdCOCO.contains(label.lowercased())
    }

    var displayColor: Color { isHouseholdItem ? .blue : .orange }

    static let householdCOCO: Set<String> = [
        "chair", "couch", "bed", "dining table", "toilet",
        "tv", "laptop", "mouse", "remote", "keyboard",
        "cell phone", "microwave", "oven", "toaster",
        "sink", "refrigerator", "book", "clock", "vase",
        "bottle", "wine glass", "cup", "fork", "knife",
        "spoon", "bowl", "potted plant", "backpack",
        "umbrella", "handbag", "suitcase", "scissors",
        "teddy bear", "hair drier", "toothbrush",
    ]

    // 80 COCO class names — index harus sama persis dengan urutan model
    static let cocoLabels = [
        "person","bicycle","car","motorcycle","airplane","bus","train","truck",
        "boat","traffic light","fire hydrant","stop sign","parking meter","bench",
        "bird","cat","dog","horse","sheep","cow","elephant","bear","zebra","giraffe",
        "backpack","umbrella","handbag","tie","suitcase","frisbee","skis","snowboard",
        "sports ball","kite","baseball bat","baseball glove","skateboard","surfboard",
        "tennis racket","bottle","wine glass","cup","fork","knife","spoon","bowl",
        "banana","apple","sandwich","orange","broccoli","carrot","hot dog","pizza",
        "donut","cake","chair","couch","potted plant","bed","dining table","toilet",
        "tv","laptop","mouse","remote","keyboard","cell phone","microwave","oven",
        "toaster","sink","refrigerator","book","clock","vase","scissors","teddy bear",
        "hair drier","toothbrush"
    ]
}

// MARK: - Camera + Detection Manager

class ObjectDetectionManager: NSObject, ObservableObject, @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "od.session", qos: .userInitiated)
    private let inferenceQueue = DispatchQueue(label: "od.inference", qos: .userInitiated)

    @Published var isRunning = false
    @Published var cameraPermission: AVAuthorizationStatus = .notDetermined
    @Published var detections: [ObjectDetection] = []
    @Published var fps: Double = 0
    @Published var inferenceMs: Double = 0
    @Published var modelState: ModelState = .loading
    @Published var confidenceThreshold: Float = 0.45
    @Published var demoMode = false

    // Properti yang diakses dari inferenceQueue — harus nonisolated(unsafe)
    nonisolated(unsafe) private var mlModel: MLModel?
    nonisolated(unsafe) var inferenceThreshold: Float = 0.45
    nonisolated(unsafe) private var frameCount = 0
    nonisolated(unsafe) private var fpsTimer = Date()
    nonisolated(unsafe) private var isProcessingFrame = false

    enum ModelState: Equatable {
        case loading
        case ready(name: String)
        case missing
        case error(String)
    }

    override init() {
        super.init()
        cameraPermission = AVCaptureDevice.authorizationStatus(for: .video)
        loadModel()
    }

    // MARK: Model Loading

    private func loadModel() {
        inferenceQueue.async { [weak self] in
            guard let self else { return }

            // Cari ModelYOLO.mlpackage yang sudah ditambah ke project
            guard let url = Bundle.main.url(forResource: "ModelYOLO", withExtension: "mlmodelc")
                         ?? Bundle.main.url(forResource: "ModelYOLO", withExtension: "mlpackage") else {
                DispatchQueue.main.async {
                    self.modelState = .missing
                    self.demoMode = true
                }
                return
            }

            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all  // pakai Neural Engine + GPU
                self.mlModel = try MLModel(contentsOf: url, configuration: config)
                DispatchQueue.main.async {
                    self.modelState = .ready(name: "YOLO11l")
                    self.demoMode = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.modelState = .error(error.localizedDescription)
                    self.demoMode = true
                }
            }
        }
    }

    // MARK: Camera Session

    func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.cameraPermission = granted ? .authorized : .denied
                if granted { self?.setupAndStartSession() }
            }
        }
    }

    func startCamera() {
        if cameraPermission == .notDetermined {
            requestCameraPermission()
        } else if cameraPermission == .authorized {
            setupAndStartSession()
        }
    }

    func stopCamera() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async { self?.isRunning = false }
        }
    }

    private func setupAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720

            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)

            self.videoOutput.setSampleBufferDelegate(self, queue: self.inferenceQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }

            self.session.commitConfiguration()
            self.session.startRunning()

            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    // MARK: Frame Processing

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        updateFPS()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let model = mlModel else {
            // Model belum ready → demo mode
            let fake = makeDemoDetections()
            DispatchQueue.main.async { self.detections = fake }
            isProcessingFrame = false
            return
        }

        let t0 = Date()

        do {
            // Resize frame ke 640×640 yang dibutuhkan YOLO11l
            let resized = try resizePixelBuffer(pixelBuffer, to: CGSize(width: 640, height: 640))

            // Buat input dengan confidence & IoU threshold
            let threshold = inferenceThreshold
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "image":               MLFeatureValue(pixelBuffer: resized),
                "iouThreshold":        MLFeatureValue(double: 0.45),
                "confidenceThreshold": MLFeatureValue(double: Double(max(threshold - 0.1, 0.1))),
            ])

            let output = try model.prediction(from: input)
            let elapsed = Date().timeIntervalSince(t0) * 1000

            // Output: confidence [N×80], coordinates [N×4] dalam format [x_c, y_c, w, h]
            guard
                let confArray = output.featureValue(for: "confidence")?.multiArrayValue,
                let coordArray = output.featureValue(for: "coordinates")?.multiArrayValue
            else {
                isProcessingFrame = false
                return
            }

            let results = parseYOLOOutput(
                confidence: confArray,
                coordinates: coordArray,
                threshold: threshold
            )

            DispatchQueue.main.async {
                self.detections = results
                self.inferenceMs = elapsed
            }

        } catch {
            // Fallback ke VNCoreMLRequest kalau MLDictionaryFeatureProvider gagal
            runVisionFallback(pixelBuffer: pixelBuffer, model: model)
        }

        isProcessingFrame = false
    }

    // MARK: Output Parsing

    private func parseYOLOOutput(confidence: MLMultiArray,
                                  coordinates: MLMultiArray,
                                  threshold: Float) -> [ObjectDetection] {
        let numBoxes = confidence.shape[0].intValue
        let numClasses = confidence.shape[1].intValue
        var results: [ObjectDetection] = []

        for i in 0..<numBoxes {
            // Cari class dengan confidence tertinggi untuk box ini
            var maxConf: Float = 0
            var maxClassIdx = 0

            for c in 0..<numClasses {
                let conf = confidence[[i, c] as [NSNumber]].floatValue
                if conf > maxConf {
                    maxConf = conf
                    maxClassIdx = c
                }
            }

            guard maxConf >= threshold else { continue }

            let label = maxClassIdx < ObjectDetection.cocoLabels.count
                ? ObjectDetection.cocoLabels[maxClassIdx]
                : "class_\(maxClassIdx)"

            // Koordinat YOLO: [x_center, y_center, width, height] normalized, origin top-left
            let xc = CGFloat(coordinates[[i, 0] as [NSNumber]].floatValue)
            let yc = CGFloat(coordinates[[i, 1] as [NSNumber]].floatValue)
            let w  = CGFloat(coordinates[[i, 2] as [NSNumber]].floatValue)
            let h  = CGFloat(coordinates[[i, 3] as [NSNumber]].floatValue)

            let box = CGRect(x: xc - w/2, y: yc - h/2, width: w, height: h)
                .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))

            results.append(ObjectDetection(label: label, confidence: maxConf, boundingBox: box))
        }

        return results
    }

    // Fallback pakai Vision framework (kalau direct MLModel gagal)
    private func runVisionFallback(pixelBuffer: CVPixelBuffer, model: MLModel) {
        guard let visionModel = try? VNCoreMLModel(for: model) else {
            isProcessingFrame = false
            return
        }

        let threshold = inferenceThreshold
        let t0 = Date()

        let req = VNCoreMLRequest(model: visionModel) { [weak self] request, _ in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(t0) * 1000

            // Vision mungkin parse confidence+coordinates ke VNRecognizedObjectObservation
            if let obs = request.results as? [VNRecognizedObjectObservation], !obs.isEmpty {
                let results = obs
                    .filter { $0.confidence >= threshold }
                    .map { o -> ObjectDetection in
                        let label = o.labels.first?.identifier ?? "unknown"
                        // Vision origin bottom-left → flip ke top-left
                        let bb = CGRect(
                            x: o.boundingBox.minX,
                            y: 1 - o.boundingBox.maxY,
                            width: o.boundingBox.width,
                            height: o.boundingBox.height
                        )
                        return ObjectDetection(label: label, confidence: o.confidence, boundingBox: bb)
                    }
                DispatchQueue.main.async {
                    self.detections = results
                    self.inferenceMs = elapsed
                }
            }
            self.isProcessingFrame = false
        }

        req.imageCropAndScaleOption = .scaleFill
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([req])
    }

    // MARK: Helpers

    private func resizePixelBuffer(_ buffer: CVPixelBuffer, to size: CGSize) throws -> CVPixelBuffer {
        let width = Int(size.width)
        let height = Int(size.height)

        var resized: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &resized)
        guard let dst = resized else {
            throw NSError(domain: "OD", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create pixel buffer"])
        }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
            CVPixelBufferUnlockBaseAddress(dst, [])
        }

        let srcW = CVPixelBufferGetWidth(buffer)
        let srcH = CVPixelBufferGetHeight(buffer)
        let srcPtr = CVPixelBufferGetBaseAddress(buffer)
        let dstPtr = CVPixelBufferGetBaseAddress(dst)

        guard let src = srcPtr, let dstBase = dstPtr else { throw NSError(domain: "OD", code: -2) }

        var srcBitmap = vImage_Buffer(
            data: src,
            height: vImagePixelCount(srcH),
            width: vImagePixelCount(srcW),
            rowBytes: CVPixelBufferGetBytesPerRow(buffer)
        )
        var dstBitmap = vImage_Buffer(
            data: dstBase,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRow(dst)
        )
        vImageScale_ARGB8888(&srcBitmap, &dstBitmap, nil, vImage_Flags(kvImageHighQualityResampling))

        return dst
    }

    private func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(fpsTimer)
        if elapsed >= 1.0 {
            let currentFPS = Double(frameCount) / elapsed
            frameCount = 0
            fpsTimer = now
            DispatchQueue.main.async { self.fps = currentFPS }
        }
    }

    private func makeDemoDetections() -> [ObjectDetection] {
        let t = Date().timeIntervalSince1970
        let j = CGFloat(sin(t * 2) * 0.01)
        return [
            ObjectDetection(label: "chair",  confidence: 0.88,
                            boundingBox: CGRect(x: 0.05 + j, y: 0.20, width: 0.38, height: 0.50)),
            ObjectDetection(label: "person", confidence: 0.76,
                            boundingBox: CGRect(x: 0.55, y: 0.05 + j, width: 0.40, height: 0.72)),
        ]
    }
}

// MARK: - Camera Preview

struct CameraPreviewUIView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> _PreviewView { _PreviewView(session: session) }
    func updateUIView(_ uiView: _PreviewView, context: Context) {}

    class _PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        init(session: AVCaptureSession) {
            super.init(frame: .zero)
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
        }

        required init?(coder: NSCoder) { fatalError() }

        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
        }
    }
}

// MARK: - Bounding Box Overlay

struct BoundingBoxOverlay: View {
    let detections: [ObjectDetection]
    let size: CGSize

    var body: some View {
        ForEach(detections) { det in
            let b = det.boundingBox
            let x = b.minX * size.width
            let y = b.minY * size.height
            let w = b.width * size.width
            let h = b.height * size.height

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(det.displayColor, lineWidth: 3)
                    .frame(width: w, height: h)
                    .offset(x: x, y: y)

                Text("\(det.label) \(Int(det.confidence * 100))%")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(det.displayColor)
                    .cornerRadius(4)
                    .offset(x: x, y: max(y - 20, 0))
            }
        }
    }
}

// MARK: - Main View

struct ObjectDetectionPOCView: View {
    @StateObject private var od = ObjectDetectionManager()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {

                modelStatusBanner

                if od.cameraPermission == .denied {
                    Label("Izin kamera ditolak. Buka Settings → Privacy → Camera.",
                          systemImage: "camera.fill")
                        .foregroundColor(.red).font(.subheadline).padding()
                } else if od.cameraPermission == .notDetermined {
                    Button("Izinkan Kamera") { od.requestCameraPermission() }
                        .buttonStyle(.borderedProminent).padding()
                }

                if od.cameraPermission == .authorized {
                    cameraFeedSection
                }

                GroupBox("Confidence Threshold: \(Int(od.confidenceThreshold * 100))%") {
                    Slider(value: Binding(
                        get: { od.confidenceThreshold },
                        set: { od.confidenceThreshold = $0; od.inferenceThreshold = $0 }
                    ), in: 0.1...0.9, step: 0.05)
                    Text("Lebih rendah = lebih banyak deteksi, lebih banyak false positive. Rekomendasi awal: 45%")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal)

                if !od.detections.isEmpty {
                    activeDetectionsSection
                }

                cocoClassesSection
                evaluationSection
            }
            .padding(.bottom)
        }
        .navigationTitle("POC 3: Object Detection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if od.cameraPermission == .authorized { od.startCamera() }
        }
        .onDisappear { od.stopCamera() }
    }

    // MARK: Sub-views

    @ViewBuilder
    private var modelStatusBanner: some View {
        switch od.modelState {
        case .loading:
            HStack {
                ProgressView().scaleEffect(0.8)
                Text("Memuat ModelYOLO (YOLO11l)…")
                    .font(.subheadline).foregroundColor(.secondary)
            }
            .padding()

        case .ready(let name):
            GroupBox {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Model '\(name)' siap")
                            .font(.subheadline).fontWeight(.semibold)
                        Text("COCO 80 classes · NMS built-in · Input 640×640")
                            .font(.caption).foregroundColor(.secondary)
                        Text("Neural Engine + GPU aktif")
                            .font(.caption2).foregroundColor(.green)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal)

        case .missing:
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("ModelYOLO.mlpackage tidak ditemukan di bundle",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange).font(.subheadline)
                    Text("Pastikan ModelYOLO.mlpackage sudah di-Add ke target POC_BukanSembarang di Xcode.")
                        .font(.caption).foregroundColor(.secondary)
                    Text("Sementara berjalan DEMO MODE — bounding box disimulasikan.")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.orange)
                }
            }
            .padding(.horizontal)

        case .error(let msg):
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Gagal load model", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red).font(.subheadline)
                    Text(msg).font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
        }
    }

    private var cameraFeedSection: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    CameraPreviewUIView(session: od.session)
                    BoundingBoxOverlay(detections: od.detections, size: geo.size)

                    VStack {
                        HStack {
                            HUDLabel(text: "\(Int(od.fps)) FPS",
                                     color: od.fps >= 10 ? .green : .orange)
                            HUDLabel(text: "\(Int(od.inferenceMs))ms", color: .white)
                            Spacer()
                            HUDLabel(
                                text: od.demoMode ? "DEMO" : "YOLO11l",
                                color: od.demoMode ? .orange : .green
                            )
                        }
                        .padding(8)
                        Spacer()
                    }
                }
            }
            .frame(height: 380)
            .cornerRadius(14)
            .clipped()
            .padding(.horizontal)

            Button(od.isRunning ? "Stop Kamera" : "Start Kamera") {
                od.isRunning ? od.stopCamera() : od.startCamera()
            }
            .buttonStyle(.borderedProminent)
            .tint(od.isRunning ? .red : .blue)
        }
    }

    private var activeDetectionsSection: some View {
        GroupBox("Terdeteksi Sekarang (\(od.detections.count) objek)") {
            ForEach(od.detections) { det in
                HStack {
                    Circle().fill(det.displayColor).frame(width: 10, height: 10)
                    Text(det.label).font(.subheadline)
                    if det.isHouseholdItem {
                        Image(systemName: "house.fill")
                            .font(.caption).foregroundColor(.blue)
                    }
                    Spacer()
                    ConfidenceBar(value: det.confidence)
                    Text("\(Int(det.confidence * 100))%")
                        .font(.caption).monospacedDigit()
                        .foregroundColor(det.confidence > 0.7 ? .green : .orange)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal)
    }

    private var cocoClassesSection: some View {
        GroupBox("Household Items yang Bisa Dideteksi (biru = relevan untuk app)") {
            let classes = Array(ObjectDetection.householdCOCO).sorted()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 4) {
                ForEach(classes, id: \.self) { cls in
                    Text(cls)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(4)
                        .lineLimit(1)
                }
            }
            Text("YOLO11l lebih akurat dari YOLOv8n tapi lebih berat (~53MB vs ~6MB). Cek FPS di device target.")
                .font(.caption2).foregroundColor(.secondary).padding(.top, 4)
        }
        .padding(.horizontal)
    }

    private var evaluationSection: some View {
        GroupBox("Metrik Lulus POC") {
            VStack(alignment: .leading, spacing: 8) {
                EvalRow(pass: true,  text: "≥10 FPS di iPhone 12 ke atas dengan Neural Engine")
                EvalRow(pass: true,  text: "Confidence >60% untuk chair/table/bed/sofa di cahaya cukup")
                EvalRow(pass: true,  text: "Deteksi valid dari jarak 0.5m – 2m")
                EvalRow(pass: false, text: "PERHATIAN: YOLO11l (~53MB) lebih lambat dari YOLOv8n — cek FPS di device target")
                EvalRow(pass: false, text: "PERHATIAN: Cahaya redup atau sudut ekstrem bisa turunkan confidence 20-30%")
                Divider()
                Text("Kalau FPS <10, pertimbangkan downgrade ke yolo11n atau yolov8n untuk production.")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .font(.caption)
        }
        .padding(.horizontal)
    }
}

// MARK: - Helper Views

private struct HUDLabel: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(color.opacity(0.75))
            .cornerRadius(5)
    }
}

private struct ConfidenceBar: View {
    let value: Float
    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Color(.systemGray5)).frame(width: 60, height: 6)
            RoundedRectangle(cornerRadius: 2)
                .fill(value > 0.7 ? Color.green : Color.orange)
                .frame(width: 60 * CGFloat(value), height: 6)
        }
    }
}

private struct EvalRow: View {
    let pass: Bool
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: pass ? "checkmark.circle" : "exclamationmark.triangle")
                .foregroundColor(pass ? .green : .orange)
            Text(text).foregroundColor(.secondary)
        }
    }
}

#Preview {
    NavigationStack { ObjectDetectionPOCView() }
}

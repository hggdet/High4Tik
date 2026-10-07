import SwiftUI
import PhotosUI
import AVFoundation
import Photos
import UIKit
import VideoToolbox
import CoreImage
import CoreImage.CIFilterBuiltins
import UserNotifications
import BackgroundTasks

// MARK: - App

@main
struct High4TikApp: App {
    init() {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: JobBridge.id, using: .main) { task in
                guard let task = task as? BGContinuedProcessingTask else { return }
                JobBridge.started = true
                task.progress.totalUnitCount = 1000
                task.expirationHandler = { Converter.cancelRequested = true }
                guard let work = JobBridge.work else {
                    task.setTaskCompleted(success: false)
                    return
                }
                work({ p in task.progress.completedUnitCount = Int64(p * 1000) },
                     { ok in task.setTaskCompleted(success: ok) })
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

// MARK: - Background job bridge

typealias JobWork = (@escaping (Double) -> Void, @escaping (Bool) -> Void) -> Void

enum JobBridge {
    static let id = "com.abdtench.high4tik.process"
    static var work: JobWork?
    static var started = false
    static var inBackground = false
}

// MARK: - Picked video

struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(
            contentType: .movie,
            exporting: { SentTransferredFile($0.url) },
            importing: { received in
                let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("in_\(UUID().uuidString).\(ext)")
                try FileManager.default.copyItem(at: received.file, to: dst)
                return PickedMovie(url: dst)
            }
        )
    }
}

// MARK: - Helpers

let isArabic = (Locale.preferredLanguages.first ?? "en").hasPrefix("ar")
func t(_ ar: String, _ en: String) -> String { isArabic ? ar : en }

extension View {
    /// Liquid Glass on iOS 26+, frosted material fallback before that.
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
            .overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 1))
        #endif
    }
}

struct WhitePill: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            Color.clear.glassEffect(
                Glass.regular.tint(Color.white.opacity(scheme == .dark ? 0.8 : 0.5)),
                in: Capsule())
        } else {
            Capsule().fill(Color.white).shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        }
        #else
        Capsule().fill(Color.white).shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        #endif
    }
}

struct Seg<T: Hashable>: View {
    let items: [(String, T)]
    @Binding var sel: T
    @Namespace private var ns
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let on = items[i].1 == sel
                Text(items[i].0)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(on ? Color.black : Color.primary)
                    .background {
                        if on { WhitePill().matchedGeometryEffect(id: "pill", in: ns) }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        guard !on else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                            sel = items[i].1
                        }
                    }
            }
        }
        .padding(4)
        .background(Color(uiColor: .systemGray5), in: Capsule())
    }
}

func makeThumb(_ url: URL) async -> UIImage? {
    let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    g.appliesPreferredTrackTransform = true
    g.maximumSize = CGSize(width: 900, height: 900)
    guard let r = try? await g.image(at: .zero) else { return nil }
    return UIImage(cgImage: r.image)
}

// MARK: - Before / After

/// Grabs the middle frame and crops the centre (same normalized area for both clips),
/// so the zoomed comparison shows real detail differences.
func frameCrop(_ url: URL) async -> UIImage? {
    let asset = AVURLAsset(url: url)
    guard let dur = try? await asset.load(.duration) else { return nil }
    let g = AVAssetImageGenerator(asset: asset)
    g.appliesPreferredTrackTransform = true
    g.requestedTimeToleranceBefore = .zero
    g.requestedTimeToleranceAfter = .zero
    let t = CMTime(seconds: dur.seconds * 0.5, preferredTimescale: 600)
    guard let r = try? await g.image(at: t) else { return nil }
    let cg = r.image
    let w = CGFloat(cg.width), h = CGFloat(cg.height)
    let nw: CGFloat = 0.3
    let nh: CGFloat = min(0.3 * w / h, 1)
    let rect = CGRect(x: (1 - nw) / 2 * w, y: (1 - nh) / 2 * h, width: nw * w, height: nh * h)
    guard let c = cg.cropping(to: rect.integral) else { return nil }
    return UIImage(cgImage: c)
}

struct CompareView: View {
    let before: UIImage
    let after: UIImage
    @State private var x: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .topLeading) {
                Image(uiImage: after).resizable().scaledToFill()
                    .frame(width: w, height: h).clipped()
                Image(uiImage: before).resizable().scaledToFill()
                    .frame(width: w, height: h).clipped()
                    .mask(alignment: .leading) { Rectangle().frame(width: w * x) }
                Rectangle().fill(Color.white).frame(width: 2, height: h)
                    .offset(x: w * x - 1)
                Circle().fill(Color.white).frame(width: 34, height: 34)
                    .overlay(Image(systemName: "arrow.left.and.right")
                        .font(.footnote.weight(.bold)).foregroundStyle(Color.black))
                    .shadow(color: .black.opacity(0.25), radius: 6)
                    .offset(x: w * x - 17, y: h / 2 - 17)
                HStack {
                    Text("Original").padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Text("High4Tik").padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary)
                .padding(12)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                x = min(max(v.location.x / w, 0), 1)
            })
        }
        .aspectRatio(1, contentMode: .fit)
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - UI

struct ContentView: View {
    @State private var items: [PhotosPickerItem] = []
    @State private var movies: [URL] = []
    @State private var results: [URL] = []
    @State private var thumb: UIImage?
    @AppStorage("codecRaw") private var codecRaw = Codec.hevc.rawValue
    @AppStorage("side") private var side = 3840
    @AppStorage("mbps") private var mbps = 40
    @State private var clipDuration: Double = 0
    @AppStorage("sharpen") private var sharpen = true
    @State private var progress = 0.0
    @State private var busy = false
    @State private var loading = false
    @State private var failed = false
    @State private var status = ""
    @State private var result: URL?
    @State private var beforeImg: UIImage?
    @State private var afterImg: UIImage?
    @State private var showCompare = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            ZStack {
                Color(uiColor: .systemBackground)
                RadialGradient(colors: [Color.primary.opacity(0.10), .clear],
                               center: .top, startRadius: 0, endRadius: 460)
            }
            .ignoresSafeArea()
            GeometryReader { geo in
                ScrollView { content.frame(minHeight: geo.size.height) }
                    .scrollIndicators(.hidden)
            }
        }
        .fontDesign(.rounded)
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
        .onChange(of: scenePhase) { phase in
            JobBridge.inBackground = (phase != .active)
            if phase == .background && busy && !JobBridge.started { notifyReturn() }
        }
        .sheet(isPresented: $showCompare) {
            if let b = beforeImg, let a = afterImg {
                VStack(spacing: 16) {
                    Text(t("قبل / بعد (مقرّب)", "Before / After (zoomed)")).font(.headline)
                    CompareView(before: b, after: a).padding(.horizontal, 20)
                    Text(t("اسحب الخط", "Drag the line")).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 28)
                .presentationDetents([.large])
            }
        }
        .onChange(of: items) { new in
            guard !new.isEmpty else { return }
            loading = true
            failed = false
            status = ""
            Task {
                var urls: [URL] = []
                for it in new {
                    if let m = try? await it.loadTransferable(type: PickedMovie.self) { urls.append(m.url) }
                }
                if urls.isEmpty {
                    failed = true
                    status = t("ما انحمّل المقطع، جرّب مرة ثانية", "Couldn't load the video, try again")
                } else {
                    movies = urls
                    result = nil
                    results = []
                    progress = 0
                    thumb = await makeThumb(urls[0])
                    clipDuration = (try? await AVURLAsset(url: urls[0]).load(.duration).seconds) ?? 0
                    if urls.count < new.count {
                        failed = true
                        status = t("انحمّل \(urls.count) من \(new.count)", "Loaded \(urls.count) of \(new.count)")
                    }
                }
                loading = false
                items = []
            }
        }
    }

    var content: some View {
        VStack(spacing: 14) {
            Text("High4Tik")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

            PhotosPicker(selection: $items, maxSelectionCount: 1, matching: .videos, preferredItemEncoding: .current) {
                ZStack {
                    if let img = thumb {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .padding(12)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 36, weight: .light))
                            Text(t("اختر مقطع", "Choose video")).font(.headline)
                        }
                        .foregroundStyle(Color.primary)
                    }
                    if loading { ProgressView().controlSize(.large) }
                    if movies.count > 1 {
                        VStack {
                            HStack {
                                Spacer()
                                Text("×\(movies.count)")
                                    .font(.footnote.weight(.bold))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                            Spacer()
                        }
                        .padding(18)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy || loading)
            .glass(RoundedRectangle(cornerRadius: 32, style: .continuous), interactive: true)

            Seg(items: [("4K", 3840), ("2K", 2560)], sel: $side)
            Seg(items: [("HEVC", Codec.hevc), ("H.264", Codec.h264)], sel: codecBinding)
            Seg(items: [("40 Mbps", 40), ("60 Mbps", 60)], sel: $mbps)
            Seg(items: [(t("حدة", "Sharp"), true), (t("بدون", "Off"), false)], sel: $sharpen)

            if clipDuration > 0 && !movies.isEmpty && !busy {
                Text(t("الحجم المتوقع ≈ \(Int(estMB)) MB", "Estimated size ≈ \(Int(estMB)) MB")
                     + (capped ? t(" • الجودة محدودة لتبقى تحت 250MB", " • quality capped to stay under 250 MB") : ""))
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }

            actions.padding(.top, 6)

            if !status.isEmpty {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(failed ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 16)

            VStack(spacing: 10) {
                Text(t("عبدالباسط خضير", "Abdul Basit Khudair"))
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    socialLink("Telegram", "paperplane.fill", "https://t.me/ipafilesfor")
                    socialLink("TikTok", "music.note", "https://www.tiktok.com/@087.n")
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
    }

    func socialLink(_ title: String, _ icon: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 132, height: 44)
        }
        .glass(Capsule(), interactive: true)
    }

    @ViewBuilder var actions: some View {
        if busy {
            HStack(spacing: 14) {
                ProgressView(value: progress).tint(.primary)
                Text("\(Int(progress * 100))%")
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .frame(height: 60)
            .glass(Capsule())
        } else {
            HStack(spacing: 12) {
                Button(action: start) {
                    Text(result == nil ? t("ابدأ", "Start") : t("أعد", "Redo"))
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color.primary, in: Capsule())
                }
                .disabled(movies.isEmpty || loading)
                .opacity(movies.isEmpty ? 0.35 : 1)

                if !results.isEmpty {
                    ShareLink(items: results) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 60, height: 60)
                    }
                    .glass(Circle(), interactive: true)
                    if beforeImg != nil && afterImg != nil {
                        Button { showCompare = true } label: {
                            Image(systemName: "square.split.2x1")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .frame(width: 60, height: 60)
                        }
                        .glass(Circle(), interactive: true)
                    }
                }
            }
        }
    }

    var codec: Codec { Codec(rawValue: codecRaw) ?? .hevc }

    /// TikTok's phone upload gets heavier compression on big files, so stay under ~250 MB
    static let sizeCapMB = 250.0
    var effMbps: Double {
        guard clipDuration > 0 else { return Double(mbps) }
        let cap = (Self.sizeCapMB * 8) / clipDuration - 0.2
        return max(min(Double(mbps), cap), 6)
    }
    var capped: Bool { clipDuration > 0 && effMbps < Double(mbps) - 0.05 }
    var estMB: Double { (effMbps * 1_000_000 + 192_000) * clipDuration / 8 / 1_000_000 }
    var codecBinding: Binding<Codec> {
        Binding(get: { codec }, set: { codecRaw = $0.rawValue })
    }

    func notifyDone(_ ok: Bool) {
        guard UIApplication.shared.applicationState != .active else { return }
        let c = UNMutableNotificationContent()
        c.title = "High4Tik"
        c.body = ok ? t("خلص المقطع وانحفظ بالصور", "Done — saved to Photos")
                    : t("فشلت المعالجة", "Processing failed")
        c.sound = .default
        let req = UNNotificationRequest(
            identifier: UUID().uuidString, content: c,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    func notifyReturn() {
        let c = UNMutableNotificationContent()
        c.title = "High4Tik"
        c.body = t("ارجع للتطبيق حتى تكمل المعالجة", "Return to the app to finish processing")
        c.sound = .default
        let req = UNNotificationRequest(
            identifier: "h4t.return", content: c,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    func start() {
        guard !movies.isEmpty else { return }
        busy = true
        failed = false
        result = nil
        results = []
        beforeImg = nil
        afterImg = nil
        progress = 0
        status = t("خلّي التطبيق مفتوح", "Keep the app open")
        UIApplication.shared.isIdleTimerDisabled = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            JobBridge.started = false
            JobBridge.work = { report, done in runJob(report: report, done: done) }
            let req = BGContinuedProcessingTaskRequest(
                identifier: JobBridge.id,
                title: "High4Tik",
                subtitle: t("جاري المعالجة", "Processing"))
            req.strategy = .fail
            do {
                try BGTaskScheduler.shared.submit(req)
                status = t("تقدر تطلع من التطبيق", "You can leave the app")
                // Safety net: if the system never starts the task, run normally
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if !JobBridge.started {
                        JobBridge.work = nil
                        status = t("خلّي التطبيق مفتوح", "Keep the app open")
                        runJob(report: { _ in }, done: { _ in })
                    }
                }
                return
            } catch {
                JobBridge.work = nil
            }
        }
        #endif
        runJob(report: { _ in }, done: { _ in })
    }

    func runJob(report: @escaping (Double) -> Void, done: @escaping (Bool) -> Void) {
        let inputs = movies
        let opt = Options(codec: codec, longSide: side, mbps: effMbps, sharpen: sharpen)
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask { }
        Converter.cancelRequested = false
        Task {
            var outs: [URL] = []
            var ok = false
            do {
                for (i, input) in inputs.enumerated() {
                    let out = try await Converter.run(input: input, opt: opt) { p in
                        let total = (Double(i) + p) / Double(inputs.count)
                        DispatchQueue.main.async {
                            progress = total
                            report(total)
                        }
                    }
                    try await saveToPhotos(out)
                    outs.append(out)
                }
                notifyDone(true)
                results = outs
                result = outs.last
                beforeImg = await frameCrop(inputs[0])
                afterImg = await frameCrop(outs[0])
                progress = 1
                status = t("انحفظ بالصور", "Saved to Photos")
                ok = true
            } catch {
                failed = true
                status = error.localizedDescription
                notifyDone(false)
                if !outs.isEmpty { results = outs; result = outs.last }
            }
            busy = false
            UIApplication.shared.isIdleTimerDisabled = false
            if bg != .invalid { UIApplication.shared.endBackgroundTask(bg) }
            done(ok)
        }
    }

    func saveToPhotos(_ url: URL) async throws {
        let s = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard s == .authorized || s == .limited else {
            throw NSError(domain: "h4t", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                                        t("ما في صلاحية لحفظ الصور", "Photos access denied")])
        }
        try await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}

// MARK: - Converter

enum Codec: String, CaseIterable { case hevc = "HEVC", h264 = "H.264" }

struct Options {
    var codec: Codec
    var longSide: Int
    var mbps: Double
    var sharpen: Bool
}

enum Converter {
    static var cancelRequested = false
    static func fail(_ m: String) -> NSError {
        NSError(domain: "h4t", code: 2, userInfo: [NSLocalizedDescriptionKey: m])
    }

    static func run(input: URL, opt: Options, progress: @escaping (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: input)
        guard let vt = try await asset.loadTracks(withMediaType: .video).first else {
            throw fail("المقطع ما فيه فيديو")
        }
        let duration = try await asset.load(.duration)
        let natural = try await vt.load(.naturalSize)
        let pt = try await vt.load(.preferredTransform)
        let fpsRaw = try await vt.load(.nominalFrameRate)
        let at = try await asset.loadTracks(withMediaType: .audio).first

        // HDR detection (iPhone videos are often HLG / Dolby Vision)
        let fds = try await vt.load(.formatDescriptions)
        let tfv = fds.first.flatMap {
            CMFormatDescriptionGetExtension($0, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        }
        let isPQ = tfv == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String)
        let isHLG = tfv == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String)
        let hdr = isPQ || isHLG

        // Display size after rotation, then scale so the long side = target
        let disp = natural.applying(pt)
        let w = abs(disp.width), h = abs(disp.height)
        let k = CGFloat(opt.longSide) / max(w, h)
        let W = Int((w * k / 2).rounded()) * 2
        let H = Int((h * k / 2).rounded()) * 2
        let minDur = try await vt.load(.minFrameDuration)
        let fromMin = (minDur.isNumeric && minDur.seconds > 0) ? Int((1.0 / minDur.seconds).rounded()) : 0
        let fps = min(max(Int(fpsRaw.rounded()), fromMin, 24), 60)

        // Video composition: rotate + scale
        let comp: AVMutableVideoComposition
        if hdr {
            // HDR: keep the simple transform path (no filters) to protect the colours
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vt)
            layer.setTransform(pt.concatenating(CGAffineTransform(scaleX: k, y: k)), at: .zero)
            let instr = AVMutableVideoCompositionInstruction()
            instr.timeRange = CMTimeRange(start: .zero, duration: duration)
            instr.layerInstructions = [layer]
            comp = AVMutableVideoComposition()
            comp.instructions = [instr]
        } else {
            // SDR: Lanczos upscale (much crisper than bilinear) + very mild sharpening
            let ci = CIContext(options: [.workingFormat: CIFormat.RGBAh])
            // The GPU is off-limits in the background, so render on the CPU there
            let cpu = CIContext(options: [.workingFormat: CIFormat.RGBAh, .useSoftwareRenderer: true])
            let doSharpen = opt.sharpen
            let tw = CGFloat(W), th = CGFloat(H)
            comp = AVMutableVideoComposition(asset: asset) { req in
                var img = req.sourceImage
                img = img.transformed(by: CGAffineTransform(translationX: -img.extent.minX, y: -img.extent.minY))
                let sc = tw / max(img.extent.width, 1)
                let lz = CIFilter.lanczosScaleTransform()
                lz.inputImage = img
                lz.scale = Float(sc)
                lz.aspectRatio = 1
                var out = lz.outputImage ?? img
                if doSharpen {
                    let um = CIFilter.unsharpMask()
                    um.inputImage = out
                    um.radius = 2.0
                    um.intensity = 0.45
                    out = um.outputImage ?? out
                }
                out = out.cropped(to: CGRect(x: 0, y: 0, width: tw, height: th))
                req.finish(with: out, context: JobBridge.inBackground ? cpu : ci)
            }
        }
        comp.renderSize = CGSize(width: W, height: H)
        comp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        // Copy the source's own colour tags so colours stay identical
        func srcExt(_ key: CFString) -> String? {
            fds.first.flatMap { CMFormatDescriptionGetExtension($0, extensionKey: key) as? String }
        }
        let okPrim: Set<String> = [AVVideoColorPrimaries_ITU_R_709_2, AVVideoColorPrimaries_ITU_R_2020, AVVideoColorPrimaries_P3_D65]
        let okTrans: Set<String> = [AVVideoTransferFunction_ITU_R_709_2, AVVideoTransferFunction_ITU_R_2100_HLG, AVVideoTransferFunction_SMPTE_ST_2084_PQ]
        let okMat: Set<String> = [AVVideoYCbCrMatrix_ITU_R_709_2, AVVideoYCbCrMatrix_ITU_R_2020, AVVideoYCbCrMatrix_ITU_R_601_4]
        let cPrim = srcExt(kCMFormatDescriptionExtension_ColorPrimaries).flatMap { okPrim.contains($0) ? $0 : nil }
            ?? (hdr ? AVVideoColorPrimaries_ITU_R_2020 : AVVideoColorPrimaries_ITU_R_709_2)
        let cTrans = tfv.flatMap { okTrans.contains($0) ? $0 : nil }
            ?? AVVideoTransferFunction_ITU_R_709_2
        let cMat = srcExt(kCMFormatDescriptionExtension_YCbCrMatrix).flatMap { okMat.contains($0) ? $0 : nil }
            ?? (hdr ? AVVideoYCbCrMatrix_ITU_R_2020 : AVVideoYCbCrMatrix_ITU_R_709_2)
        comp.colorPrimaries = cPrim
        comp.colorTransferFunction = cTrans
        comp.colorYCbCrMatrix = cMat

        // Reader
        let reader = try AVAssetReader(asset: asset)
        let vOut = AVAssetReaderVideoCompositionOutput(
            videoTracks: [vt],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                (hdr ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)])
        vOut.videoComposition = comp
        guard reader.canAdd(vOut) else { throw fail("فشل إعداد القراءة") }
        reader.add(vOut)

        var aOut: AVAssetReaderTrackOutput?
        if let at = at {
            let o = AVAssetReaderTrackOutput(track: at, outputSettings: nil)
            if reader.canAdd(o) { reader.add(o); aOut = o }
        }

        // Writer
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("High4Tik_\(W)x\(H)_\(Int(Date().timeIntervalSince1970)).mp4")
        try? FileManager.default.removeItem(at: outURL)
        let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true

        var props: [String: Any] = [
            AVVideoAverageBitRateKey: Int(opt.mbps * 1_000_000),
            AVVideoExpectedSourceFrameRateKey: fps,
            AVVideoMaxKeyFrameIntervalKey: fps * 2
        ]
        let useHEVC = hdr || opt.codec == .hevc
        if hdr {
            props[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
        } else if !useHEVC {
            props[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
        }
        let vSettings: [String: Any] = [
            AVVideoCodecKey: useHEVC ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: W,
            AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: props,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: cPrim,
                AVVideoTransferFunctionKey: cTrans,
                AVVideoYCbCrMatrixKey: cMat
            ]
        ]
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(vIn) else { throw fail("فشل إعداد الكتابة") }
        writer.add(vIn)

        var aIn: AVAssetWriterInput?
        if let at = at, aOut != nil {
            let hint = try await at.load(.formatDescriptions).first
            let i = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: hint)
            i.expectsMediaDataInRealTime = false
            if writer.canAdd(i) { writer.add(i); aIn = i }
        }

        let total = max(duration.seconds, 0.001)

        return try await withCheckedThrowingContinuation { cont in
            let q = DispatchQueue(label: "high4tik.encode")
            let group = DispatchGroup()

            guard reader.startReading() else {
                cont.resume(throwing: reader.error ?? fail("فشل بدء القراءة")); return
            }
            guard writer.startWriting() else {
                cont.resume(throwing: writer.error ?? fail("فشل بدء الكتابة")); return
            }
            writer.startSession(atSourceTime: .zero)

            func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, video: Bool) {
                group.enter()
                input.requestMediaDataWhenReady(on: q) {
                    while input.isReadyForMoreMediaData {
                        if Converter.cancelRequested {
                            input.markAsFinished(); group.leave(); return
                        }
                        if let sb = output.copyNextSampleBuffer() {
                            if video {
                                let t = CMSampleBufferGetPresentationTimeStamp(sb).seconds
                                progress(min(max(t / total, 0), 1))
                            }
                            if !input.append(sb) {
                                input.markAsFinished(); group.leave(); return
                            }
                        } else {
                            input.markAsFinished(); group.leave(); return
                        }
                    }
                }
            }

            pump(vIn, vOut, video: true)
            if let ai = aIn, let ao = aOut { pump(ai, ao, video: false) }

            group.notify(queue: q) {
                if Converter.cancelRequested {
                    reader.cancelReading()
                    writer.cancelWriting()
                    cont.resume(throwing: fail(t("توقفت المعالجة، ارجع للتطبيق وأعدها", "Processing stopped, reopen the app and retry")))
                    return
                }
                if writer.status == .failed {
                    reader.cancelReading()
                    cont.resume(throwing: writer.error ?? fail("فشلت الكتابة"))
                    return
                }
                writer.finishWriting {
                    if writer.status == .completed {
                        cont.resume(returning: outURL)
                    } else {
                        cont.resume(throwing: writer.error ?? fail("فشل إنهاء الملف"))
                    }
                }
            }
        }
    }
}

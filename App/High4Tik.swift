import SwiftUI
import PhotosUI
import AVFoundation
import Photos
import UIKit
import VideoToolbox
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - App

@main
struct High4TikApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
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

// MARK: - UI

struct ContentView: View {
    @State private var item: PhotosPickerItem?
    @State private var movie: URL?
    @State private var thumb: UIImage?
    @State private var codec: Codec = .hevc
    @State private var side = 3840
    @State private var mbps = 40
    @State private var sharpen = true
    @State private var progress = 0.0
    @State private var busy = false
    @State private var loading = false
    @State private var failed = false
    @State private var status = ""
    @State private var result: URL?

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
        .onChange(of: item) { new in
            guard let new = new else { return }
            loading = true
            failed = false
            status = ""
            Task {
                if let m = try? await new.loadTransferable(type: PickedMovie.self) {
                    movie = m.url
                    result = nil
                    progress = 0
                    thumb = await makeThumb(m.url)
                } else {
                    failed = true
                    status = t("ما انحمّل المقطع، جرّب مرة ثانية", "Couldn't load the video, try again")
                }
                loading = false
                item = nil
            }
        }
    }

    var content: some View {
        VStack(spacing: 14) {
            Text("High4Tik")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

            PhotosPicker(selection: $item, matching: .videos, preferredItemEncoding: .current) {
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
                }
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy || loading)
            .glass(RoundedRectangle(cornerRadius: 32, style: .continuous), interactive: true)

            Seg(items: [("4K", 3840), ("2K", 2560)], sel: $side)
            Seg(items: [("HEVC", Codec.hevc), ("H.264", Codec.h264)], sel: $codec)
            Seg(items: [("40 Mbps", 40), ("60 Mbps", 60)], sel: $mbps)
            Seg(items: [(t("حدة", "Sharp"), true), (t("بدون", "Off"), false)], sel: $sharpen)

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
                .disabled(movie == nil || loading)
                .opacity(movie == nil ? 0.35 : 1)

                if let r = result {
                    ShareLink(item: r) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.primary)
                            .frame(width: 60, height: 60)
                    }
                    .glass(Circle(), interactive: true)
                }
            }
        }
    }

    func start() {
        guard let input = movie else { return }
        busy = true
        failed = false
        result = nil
        progress = 0
        status = t("خلّي التطبيق مفتوح", "Keep the app open")
        UIApplication.shared.isIdleTimerDisabled = true
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask { }
        let opt = Options(codec: codec, longSide: side, mbps: mbps, sharpen: sharpen)
        Task {
            do {
                let out = try await Converter.run(input: input, opt: opt) { p in
                    DispatchQueue.main.async { progress = p }
                }
                try await saveToPhotos(out)
                result = out
                progress = 1
                status = t("انحفظ بالصور", "Saved to Photos")
            } catch {
                failed = true
                status = error.localizedDescription
            }
            busy = false
            UIApplication.shared.isIdleTimerDisabled = false
            if bg != .invalid { UIApplication.shared.endBackgroundTask(bg) }
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
    var mbps: Int
    var sharpen: Bool
}

enum Converter {
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
                req.finish(with: out, context: ci)
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
            AVVideoAverageBitRateKey: opt.mbps * 1_000_000,
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

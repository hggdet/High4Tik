import SwiftUI
import PhotosUI
import AVFoundation
import Photos
import UIKit

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
                let dst = FileManager.default.temporaryDirectory
                    .appendingPathComponent("in_\(UUID().uuidString).mov")
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

struct Seg<T: Hashable>: View {
    let items: [(String, T)]
    @Binding var sel: T
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let on = items[i].1 == sel
                Text(items[i].0)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(on ? Color(uiColor: .systemBackground) : Color.primary)
                    .background(on ? Color.primary : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { sel = items[i].1 } }
            }
        }
        .padding(4)
        .glass(Capsule())
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
    @State private var progress = 0.0
    @State private var busy = false
    @State private var failed = false
    @State private var status = ""
    @State private var result: URL?

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            RadialGradient(colors: [Color.primary.opacity(0.10), .clear],
                           center: .top, startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) { content }
        .fontDesign(.rounded)
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
        .onChange(of: item) { _ in
            Task {
                guard let m = try? await item?.loadTransferable(type: PickedMovie.self) else { return }
                movie = m.url
                result = nil
                progress = 0
                status = ""
                thumb = await makeThumb(m.url)
            }
        }
    }

    var content: some View {
        VStack(spacing: 14) {
            Text("High4Tik")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)

            PhotosPicker(selection: $item, matching: .videos) {
                ZStack {
                    if let img = thumb {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 36, weight: .light))
                            Text(t("اختر مقطع", "Choose video")).font(.headline)
                        }
                        .foregroundStyle(Color.primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            }
            .buttonStyle(.plain)
            .glass(RoundedRectangle(cornerRadius: 32, style: .continuous), interactive: true)

            Seg(items: [("4K", 3840), ("2K", 2560)], sel: $side)
            Seg(items: [("HEVC", Codec.hevc), ("H.264", Codec.h264)], sel: $codec)
            Seg(items: [("25 Mbps", 25), ("40 Mbps", 40), ("60 Mbps", 60)], sel: $mbps)

            actions.padding(.top, 6)

            if !status.isEmpty {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(failed ? Color.red : Color.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .disabled(false)
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
                .disabled(movie == nil)
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
        let opt = Options(codec: codec, longSide: side, mbps: mbps)
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

        // Display size after rotation, then scale so the long side = target
        let disp = natural.applying(pt)
        let w = abs(disp.width), h = abs(disp.height)
        let k = CGFloat(opt.longSide) / max(w, h)
        let W = Int((w * k / 2).rounded()) * 2
        let H = Int((h * k / 2).rounded()) * 2
        let fps = Int(min(max(fpsRaw.rounded(), 24), 60))

        // Video composition: rotate + scale
        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vt)
        layer.setTransform(pt.concatenating(CGAffineTransform(scaleX: k, y: k)), at: .zero)
        let instr = AVMutableVideoCompositionInstruction()
        instr.timeRange = CMTimeRange(start: .zero, duration: duration)
        instr.layerInstructions = [layer]
        let comp = AVMutableVideoComposition()
        comp.renderSize = CGSize(width: W, height: H)
        comp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        comp.instructions = [instr]

        // Reader
        let reader = try AVAssetReader(asset: asset)
        let vOut = AVAssetReaderVideoCompositionOutput(
            videoTracks: [vt],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String:
                                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
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
        if opt.codec == .h264 { props[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        let vSettings: [String: Any] = [
            AVVideoCodecKey: opt.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: W,
            AVVideoHeightKey: H,
            AVVideoCompressionPropertiesKey: props
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

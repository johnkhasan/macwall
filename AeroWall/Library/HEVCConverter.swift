import AVFoundation

enum HEVCConverter {
    enum ConversionError: LocalizedError {
        case unsupported
        case failed(Error?)

        var errorDescription: String? {
            switch self {
            case .unsupported: return "This video cannot be converted to HEVC."
            case .failed(let error): return error?.localizedDescription ?? "HEVC conversion failed."
            }
        }
    }

    /// Picks the smallest HEVC preset that still covers the largest connected display.
    /// Size presets only scale down, never up.
    static func preset(videoSize: CGSize, displayLongestSide: CGFloat) -> String {
        let target = min(max(videoSize.width, videoSize.height), displayLongestSide)
        if target <= 1920 { return AVAssetExportPresetHEVC1920x1080 }
        if target <= 3840 { return AVAssetExportPresetHEVC3840x2160 }
        return AVAssetExportPresetHEVCHighestQuality
    }

    static func convert(
        asset: AVAsset,
        to destinationURL: URL,
        preset: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard await AVAssetExportSession.compatibility(ofExportPreset: preset, with: asset, outputFileType: .mov),
              let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConversionError.unsupported
        }
        session.shouldOptimizeForNetworkUse = false

        if #available(macOS 15.0, *) {
            let monitor = Task {
                for await state in session.states(updateInterval: 0.25) {
                    if case .exporting(let exportProgress) = state {
                        progress(exportProgress.fractionCompleted)
                    }
                }
            }
            defer { monitor.cancel() }
            do {
                try await session.export(to: destinationURL, as: .mov)
            } catch {
                throw ConversionError.failed(error)
            }
        } else {
            session.outputURL = destinationURL
            session.outputFileType = .mov
            let monitor = Task {
                while !Task.isCancelled {
                    progress(Double(session.progress))
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            defer { monitor.cancel() }
            await withCheckedContinuation { continuation in
                session.exportAsynchronously { continuation.resume() }
            }
            guard session.status == .completed else {
                throw ConversionError.failed(session.error)
            }
        }
        progress(1)
    }
}

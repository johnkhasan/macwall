import AVFoundation

class HEVCConverter {
    static let shared = HEVCConverter()
    
    func convertToHEVC(sourceURL: URL, destinationURL: URL, completion: @escaping (Bool) -> Void) {
        let asset = AVAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            completion(false)
            return
        }
        
        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                completion(exportSession.status == .completed)
            }
        }
    }
}

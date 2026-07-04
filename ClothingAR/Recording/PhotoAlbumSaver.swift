import Photos
import UIKit

// MARK: - PhotoAlbumSaver

final class PhotoAlbumSaver {

    /// 保存视频到系统相册
    /// - Parameters:
    ///   - fileURL: 临时文件的 URL
    ///   - completion: 完成回调 (success, errorMessage)
    static func saveVideo(at fileURL: URL, completion: @escaping (Bool, String?) -> Void) {
        // ── 检查文件是否存在 ──
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            completion(false, "视频文件不存在，保存失败")
            return
        }

        // ── 检查权限 ──
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            performSave(url: fileURL, completion: completion)

        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        performSave(url: fileURL, completion: completion)
                    } else {
                        completion(false, "需要相册写入权限才能保存视频")
                    }
                }
            }

        case .denied, .restricted:
            completion(false, "相册写入权限已被拒绝。请在"设置"中开启权限。")

        @unknown default:
            completion(false, "相册权限状态未知")
        }
    }

    // MARK: - Private

    private static func performSave(url: URL, completion: @escaping (Bool, String?) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .video, fileURL: url, options: nil)
        }) { success, error in
            DispatchQueue.main.async {
                if success {
                    // 保存成功后删除临时文件
                    try? FileManager.default.removeItem(at: url)
                    completion(true, nil)
                } else {
                    let msg = error?.localizedDescription ?? "保存失败"
                    completion(false, msg)
                }
            }
        }
    }

    // MARK: - Permission Check & Alert

    /// 检查权限，并在被拒绝时返回需要显示的 Alert
    static func checkPermissionAndAlert() -> UIAlertController? {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return nil

        case .denied, .restricted:
            let alert = UIAlertController(
                title: "需要相册权限",
                message: "请在"设置 > 隐私 > 照片"中允许 ClothingAR 写入照片",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "去设置", style: .default) { _ in
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            })
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            return alert

        default:
            return nil
        }
    }
}

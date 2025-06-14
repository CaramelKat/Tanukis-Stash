import Foundation
import Photos
import os.log
import SwiftUI

func determineAuthorizationStatus() -> PHAuthorizationStatus {
    var authorizationStatus = PHAuthorizationStatus.notDetermined
    authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    return authorizationStatus
}

func writeToPhotoAlbum(image: UIImage) {
    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
}

func getVideoLink(post: PostContent) -> URL? {
        var fileType: String {
            return String(post.file.ext)
        }
        let isWebm = fileType == "webm";
        let isMp4 = fileType == "mp4";
        
        if (isWebm) {
            // Look for a webm alternative
            if(post.sample.alternates != nil && post.sample.alternates!.variants != nil) {
                // varients exist, check for mp4
                let variants = post.sample.alternates!.variants!;
                if (variants.mp4 != nil && variants.mp4!.url != nil) {
                    return URL(string: variants.mp4!.url!);
                }
            }
        }
        else if (isMp4) {
            return URL(string: post.file.url!);
        }
        return nil
    }

func downloadVideoLinkAndCreateAsset(_ videoLink: String, showToast: Binding<Int>) {
        // use guard to make sure you have a valid url
        os_log("%{public}s", log: .default, "Downloading video from link: \(videoLink)");
        guard let videoURL = URL(string: videoLink) else { 
            Task { @MainActor in
                showToast.wrappedValue = 1 // Failed to save
                os_log("%{public}s %{public}s", log: .default, "URL is invalid", videoLink);
            }
            return 
        }

        guard let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { 
            Task { @MainActor in
                showToast.wrappedValue = 1 // Failed to save
                os_log("%{public}s", log: .default, "Documents directory URL is invalid");
            }
            return 
        }

        // set up your download task
        os_log("%{public}s %{public}s", log: .default, "Documents directory URL: \(documentsDirectoryURL)");
        os_log("%{public}s %{public}s", log: .default, "Video URL: \(videoURL)");
        os_log("%{public}s %{public}s", log: .default, "Starting download task for video");
        URLSession.shared.downloadTask(with: videoURL) { (location, response, error) -> Void in

        // use guard to unwrap your optional url
        guard let location = location else { 
            Task { @MainActor in
                showToast.wrappedValue = 1 // Failed to save
                os_log("%{public}s %{public}s", log: .default, "Location is nil, download failed");
            }
            return 
        }

        // create a deatination url with the server response suggested file name
        let destinationURL = documentsDirectoryURL.appendingPathComponent(response?.suggestedFilename ?? videoURL.lastPathComponent)
        os_log("%{public}s %{public}s", log: .default, "Destination URL: \(destinationURL)");

        // check if the file already exists at the destination url
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            os_log("%{public}s %{public}s", log: .default, "File already exists at destination URL, removing it");
            do {
                try FileManager.default.removeItem(at: destinationURL)
            } catch {
                Task { @MainActor in
                    showToast.wrappedValue = 1 // Failed to save
                    os_log("%{public}s %{public}s", log: .default, "Error removing existing file: \(String(describing: error))");
                }
                return
            }
        }

        do {
            // move the downloaded file to the destination url
            os_log("%{public}s %{public}s", log: .default, "Moving downloaded file to destination URL");
            try FileManager.default.moveItem(at: location, to: destinationURL)
            let authorizationStatus = determineAuthorizationStatus()
            if (authorizationStatus != .authorized) {
                Task { @MainActor in
                    showToast.wrappedValue = 3 // Not authorized
                    os_log("%{public}s %{public}s", log: .default, "Not authorized to save to photo library");
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: destinationURL)}) { completed, error in
                    if completed {
                        os_log("%{public}s %{public}s", log: .default, "Video saved successfully to photo library");
                        Task { @MainActor in
                            showToast.wrappedValue = 2 // Success
                        }
                        
                    } else {
                        print(error as Any)
                        os_log("%{public}s %{public}s", log: .default, "Failed to save video to photo library: \(String(describing: error))");
                        Task { @MainActor in
                            showToast.wrappedValue = 1 // Failed to save
                        }
                        
                    }
                    do {
                        try FileManager.default.removeItem(at: destinationURL) // Clean up the temporary file
                        os_log("%{public}s %{public}s", log: .default, "Temporary file removed successfully");
                    } catch {
                        os_log("%{public}s %{public}s", log: .default, "Error removing temporary file: \(String(describing: error))");
                    }
                }

        } catch { 
            print(error)
            Task { @MainActor in
                showToast.wrappedValue = 4 // Failed to save
                os_log("%{public}s %{public}s", log: .default, "Error moving file: \(String(describing: error))");
            }
        }

    }.resume()

}

func saveFile(post: PostContent, showToast: Binding<Int>) {
    let authorizationStatus = determineAuthorizationStatus()
    if (authorizationStatus != .authorized) {
        Task { @MainActor in
            showToast.wrappedValue = 3 // Not authorized
        }
        return
    }
    if (String(post.file.ext) == "gif") {
        var image: UIImage?
        let urlString = post.file.url
        
        let url = URL(string: urlString!)
        
        DispatchQueue.global().async {
            let data = try? Data(contentsOf: url!) //make sure your image in this url does exist, otherwise unwrap in a if let check / try-catch
            
            DispatchQueue.main.async {
                image = UIImage(data: data!)
                if(image != nil) {
                    writeToPhotoAlbum(image: image!);
                    showToast.wrappedValue = 2 // Success
                }
                else {
                    showToast.wrappedValue = 1 // Failed to save
                }
            }
        }
    }
    else if (String(post.file.ext) == "webm") {
        let videoLink = getVideoLink(post: post);
        if (videoLink != nil) {
            Task.init {
                downloadVideoLinkAndCreateAsset(videoLink!.absoluteString, showToast: showToast);
            }
        } else {
            showToast.wrappedValue = 1 // Failed to save
        }
    }
    else if (!["gif", "webm", "mp4"].contains(String(post.file.ext))) {
        var image: UIImage?
        let urlString = post.file.url
        
        let url = URL(string: urlString ?? "");

        if (url == nil) {
            Task { @MainActor in
                showToast.wrappedValue = 1 // Failed to save
            }
            return
        }

        DispatchQueue.global().async {
            let data = try? Data(contentsOf: url!)
            if data == nil {
                DispatchQueue.main.async {
                    showToast.wrappedValue = 1 // Failed to save
                }
                return
            }
            DispatchQueue.main.async {
                image = UIImage(data: data!)
                if(image != nil) {
                    writeToPhotoAlbum(image: image!)
                    showToast.wrappedValue = 2 // Success
                }
            }
        }
    }
    else {
        // Unsupported file type
        Task { @MainActor in
            showToast.wrappedValue = 1 // Failed to save
        }
    }
}
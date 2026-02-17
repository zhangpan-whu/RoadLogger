//
//  NetworkManager.swift
//  RoadLogger
//
//  Created by Pan Zhang on 2026/2/16.
//

import Foundation
import SwiftUI  // <--- 必须添加这一行，否则无法识别 ObservableObject
import Combine  // 显式导入 Combine 也是个好习惯

class NetworkManager: ObservableObject {
    // ⚠️ 把这里的 IP 换成你腾讯云服务器的公网 IP
    let serverUrl = "http://49.235.181.38:8000/upload"
    
    @Published var isUploading = false
    @Published var uploadMessage = ""
    
    func uploadFiles(videoUrl: URL, csvUrl: URL) {
        guard let url = URL(string: serverUrl) else { return }
        
        DispatchQueue.main.async {
            self.isUploading = true
            self.uploadMessage = "正在上传..."
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let httpBody = NSMutableData()
        
        // 添加视频文件
        if let videoData = try? Data(contentsOf: videoUrl) {
            httpBody.append("--\(boundary)\r\n".data(using: .utf8)!)
            httpBody.append("Content-Disposition: form-data; name=\"video\"; filename=\"video.mov\"\r\n".data(using: .utf8)!)
            httpBody.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
            httpBody.append(videoData)
            httpBody.append("\r\n".data(using: .utf8)!)
        }
        
        // 添加 CSV 文件
        if let csvData = try? Data(contentsOf: csvUrl) {
            httpBody.append("--\(boundary)\r\n".data(using: .utf8)!)
            httpBody.append("Content-Disposition: form-data; name=\"sensor\"; filename=\"data.csv\"\r\n".data(using: .utf8)!)
            httpBody.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
            httpBody.append(csvData)
            httpBody.append("\r\n".data(using: .utf8)!)
        }
        
        httpBody.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = httpBody as Data
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isUploading = false
                if let error = error {
                    self.uploadMessage = "上传失败: \(error.localizedDescription)"
                } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self.uploadMessage = "上传成功！请在网页查看。"
                } else {
                    self.uploadMessage = "服务器错误"
                }
            }
        }.resume()
    }
}

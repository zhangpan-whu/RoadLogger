//
//  NetworkManager.swift
//  RoadLogger
//
//  Created by Pan Zhang on 2026/1/31.
//

import Foundation
import UIKit
import CoreLocation
import SwiftUI
import Combine

class NetworkManager: ObservableObject {
    @Published var isUploading = false
    @Published var uploadMessage = ""
    
    private let serverUrl = "http://49.235.181.38:8000/upload" // 使用你的公网IP
    
    // 原有的 uploadFile 方法保留
    func uploadFile(to urlString: String, fileUrl: URL, fieldName: String, completion: @escaping (Bool, String?) -> Void) {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.uploadMessage = "无效的服务器URL"
            }
            completion(false, "Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // 准备文件数据
        guard let fileData = try? Data(contentsOf: fileUrl) else {
            DispatchQueue.main.async {
                self.uploadMessage = "无法读取文件"
            }
            completion(false, "Cannot read file")
            return
        }

        // 添加表单数据
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileUrl.lastPathComponent)\"\r\n".data(using: .utf8)!)
        
        // 根据文件扩展名判断 Content-Type
        let mimeType = getMimeType(for: fileUrl.pathExtension)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // 发起请求
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    print("Upload error: \(error)") // 添加调试信息
                    self.uploadMessage = "上传失败: \(error.localizedDescription)"
                }
                completion(false, error.localizedDescription)
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status Code: \(httpResponse.statusCode)") // 添加调试信息
                if let data = data {
                    print("Response Data: \(String(data: data, encoding: .utf8) ?? "nil")") // 添加调试信息
                }
                
                if httpResponse.statusCode == 200 {
                    DispatchQueue.main.async {
                        self.uploadMessage = "上传成功"
                    }
                    completion(true, nil)
                } else {
                    DispatchQueue.main.async {
                        self.uploadMessage = "服务器错误: \(httpResponse.statusCode)"
                    }
                    completion(false, "Server error: \(httpResponse.statusCode)")
                }
            } else {
                DispatchQueue.main.async {
                    self.uploadMessage = "无效的服务器响应"
                }
                completion(false, "Invalid response")
            }
        }

        task.resume()
    }
    
    // 新增：异步版本的上传方法 - 修改为使用公网IP
    // 【修改部分】修改返回类型，包含解析后的 AnalysisResponse
    func uploadFiles(videoUrl: URL, csvUrl: URL) async -> (Bool, AnalysisResponse?) {
        isUploading = true
        uploadMessage = "正在上传并分析(可能需要几十秒)..." // 【修改部分】更新提示语
        
        defer {
            isUploading = false
        }
        
        // 检查文件是否存在
        guard FileManager.default.fileExists(atPath: videoUrl.path) else {
            uploadMessage = "视频文件不存在: \(videoUrl.path)"
            return (false,nil)
        }
        
        guard FileManager.default.fileExists(atPath: csvUrl.path) else {
            uploadMessage = "CSV文件不存在: \(csvUrl.path)"
            return (false,nil)
        }
        
        let boundary = UUID().uuidString
        
        guard let videoData = try? Data(contentsOf: videoUrl),
              let csvData = try? Data(contentsOf: csvUrl) else {
            uploadMessage = "读取文件失败"
            return (false,nil)
        }
        
        print("Video size: \(videoData.count) bytes") // 添加调试信息
        print("CSV size: \(csvData.count) bytes") // 添加调试信息
        
        // 创建带超时的URLSession配置
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120 // 【修改部分】大模型分析较慢，将超时时间延长至 120 秒
        config.timeoutIntervalForResource = 300 // 300秒资源超时
        let session = URLSession(configuration: config)
        
        var request = URLRequest(url: URL(string: serverUrl)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // 设置用户代理，某些服务器可能需要
        request.setValue("RoadLogger-iOS/1.0", forHTTPHeaderField: "User-Agent")
        
        var body = Data()
        
        // 添加视频文件
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"video\"; filename=\"\(videoUrl.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/quicktime\r\n\r\n".data(using: .utf8)!)
        body.append(videoData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 添加CSV文件
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        // 【修改部分】将 name=\"sensor_data\" 改为 name=\"sensor\"，与 FastAPI 后端参数名对齐
        body.append("Content-Disposition: form-data; name=\"sensor\"; filename=\"\(csvUrl.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(csvData)
        body.append("\r\n".data(using: .utf8)!)
        
        // 结束边界
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        do {
//            print("开始上传到: \(serverUrl)") // 添加调试信息
//            print("请求体大小: \(request.httpBody?.count ?? 0) bytes") // 添加调试信息
            
            let (data, response) = try await session.data(for: request)
            
//            print("收到响应: \(response)") // 添加调试信息
//            if let httpResponse = response as? HTTPURLResponse {
//                print("HTTP 状态码: \(httpResponse.statusCode)") // 添加调试信息
//            }
            
//            let responseString = String(data: data, encoding: .utf8) ?? "无法解析响应"
//            print("响应内容: \(responseString)") // 添加调试信息
            
            guard let httpResponse = response as? HTTPURLResponse else {
                uploadMessage = "无效的HTTP响应"
                return (false, nil)
            }
            
            if httpResponse.statusCode == 200 {
                // 【修改部分】解析服务器返回的 JSON 数据
                do {
                    if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let responseData = jsonObject["data"] as? [String: Any] {
                        let jsonData = try JSONSerialization.data(withJSONObject: responseData)
                        let analysisResult = try JSONDecoder().decode(AnalysisResponse.self, from: jsonData)
                        uploadMessage = "云端分析完成"
                        return (true, analysisResult)
                    }
                } catch {
                    print("解析结果失败: \(error)")
                }
                uploadMessage = "上传成功，但解析结果失败"
                return (true, nil)
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? ""
                uploadMessage = "服务器错误: \(httpResponse.statusCode) - \(responseString)"
                return (false, nil)
            }
        } catch {
            print("上传错误: \(error)") // 添加调试信息
            if error._code == NSURLErrorTimedOut {
                uploadMessage = "上传超时，请检查网络连接和服务器状态"
            } else if error._code == NSURLErrorCannotConnectToHost {
                uploadMessage = "无法连接到服务器，请检查IP地址和端口"
            } else if error._code == NSURLErrorNetworkConnectionLost {
                uploadMessage = "网络连接中断"
            } else {
                uploadMessage = "上传失败: \(error.localizedDescription)"
            }
            return (false, nil)
        }
    }
    
    // 辅助方法：根据文件扩展名获取MIME类型
    private func getMimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "mov":
            return "video/quicktime"
        case "mp4":
            return "video/mp4"
        case "csv":
            return "text/csv"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        default:
            return "application/octet-stream"
        }
    }
}


//
//  ContentView.swift
//  RoadLogger
//
//  Created by Pan Zhang on 2026/1/31.
//


import SwiftUI
import AVFoundation
import CoreMotion
import Foundation

// 对应服务器返回的 JSON 结构
struct AnalysisResponse: Codable {
    let score: Int          // 驾驶评分
    let summary: String     // 场景总结/分析
    let details: String?    // 详细建议（可选）
}

struct ContentView: View {
    @StateObject var cameraManager = CameraManager()
    @StateObject var sensorManager = SensorManager()
    @StateObject var networkManager = NetworkManager() // 引入网络管理器
    
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var currentSessionTimestamp: Int = 0 // Unix 秒时间戳
    
    // 用于存储最近一次录制的文件路径
    @State private var lastVideoUrl: URL?
    @State private var lastCsvUrl: URL?
    
    var body: some View {
        ZStack {
            // 1. 相机预览层
            CameraPreview(session: cameraManager.session)
                .ignoresSafeArea()
            
            // 2. 渐变遮罩 (美观)
            VStack {
                LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 200)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            
            // 3. UI 内容
            VStack {
                // --- 顶部栏 ---
                HStack {
                    // 录制计时器
                    if cameraManager.isRecording {
                        HStack {
                            Circle().fill(Color.red).frame(width: 8, height: 8)
                            Text(formatTime(recordingTime))
                                .font(.system(.body, design: .monospaced))
                                .bold()
                                .foregroundColor(.white)
                        }
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                    } else {
                        Text("READY")
                            .font(.caption).bold()
                            .padding(6)
                            .background(Color.yellow)
                            .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // 上传状态提示
                    if !networkManager.uploadMessage.isEmpty {
                        Text(networkManager.uploadMessage)
                            .font(.caption)
                            .foregroundColor(networkManager.uploadMessage.contains("成功") ? .green : .red)
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(4)
                    }
                }
                .padding(.top, 50)
                .padding(.horizontal)
                
                Spacer()
                
                // --- 仪表盘数据 ---
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading) {
                        Text("ACCELERATION (G)")
                            .font(.caption2).bold().foregroundColor(.gray)
                        HStack {
                            DataBox(label: "X", value: sensorManager.acceleration.x)
                            DataBox(label: "Y", value: sensorManager.acceleration.y)
                            DataBox(label: "Z", value: sensorManager.acceleration.z)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
                
                // --- 底部控制栏 ---
                HStack {
                    // 上传按钮 (只有停止录制且有文件时才显示)
                    if !cameraManager.isRecording && lastVideoUrl != nil {
                        Button(action: {
                            if let v = lastVideoUrl, let c = lastCsvUrl {
                                networkManager.uploadFiles(videoUrl: v, csvUrl: c)
                            }
                        }) {
                            VStack {
                                Image(systemName: "icloud.and.arrow.up")
                                    .font(.title2)
                                Text("上传分析")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.blue.opacity(0.8))
                            .clipShape(Circle())
                        }
                    } else {
                        // 占位符，保持布局平衡
                        Color.clear.frame(width: 60, height: 60)
                    }
                    
                    Spacer()
                    
                    // 录制按钮
                    Button(action: toggleRecording) {
                        ZStack {
                            Circle().stroke(.white, lineWidth: 4).frame(width: 70, height: 70)
                            if cameraManager.isRecording {
                                RoundedRectangle(cornerRadius: 8).fill(.red).frame(width: 30, height: 30)
                            } else {
                                Circle().fill(.red).frame(width: 60, height: 60)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // 右侧占位 (未来可放设置)
                    Color.clear.frame(width: 60, height: 60)
                }
                .padding(.bottom, 40)
                .padding(.horizontal, 30)
            }
            
            // 上传时的 Loading 遮罩
            if networkManager.isUploading {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(2)
                        Text("正在上传到云端...")
                            .foregroundColor(.white)
                            .padding(.top, 20)
                    }
                }
            }
        }
    }
    
    // --- 逻辑处理 ---
    
    func toggleRecording() {
        if cameraManager.isRecording {
            // 停止录制
            cameraManager.stopRecording()
            sensorManager.stopRecording()
            stopTimer()
            
            // 获取刚刚生成的文件路径
            // 假设 CameraManager 和 SensorManager 把文件存到了 Documents 目录
            // 这里我们需要稍微“作弊”一下，手动构造刚才的文件名，或者去文件夹里找最新的
            // findLatestFiles()
            
            // 手动构造配对的文件 URL（因为你知道时间戳！）
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            lastVideoUrl = documents.appendingPathComponent("Video_\(currentSessionTimestamp).mov")
            lastCsvUrl   = documents.appendingPathComponent("Sensor_\(currentSessionTimestamp).csv")
            
        } else {
            // 开始：生成统一时间戳
            let timestamp = Int(Date().timeIntervalSince1970)
            currentSessionTimestamp = timestamp
            // 开始录制
            networkManager.uploadMessage = "" // 清空旧消息
            cameraManager.startRecording(sessionTimestamp: timestamp)
            sensorManager.startRecording(sessionTimestamp: timestamp)
            startTimer()
        }
    }

    func findLatestFiles() {
        // 这是一个简化的查找逻辑，假设你的 Manager 按照时间戳命名文件
        // 更好的做法是让 CameraManager 在停止录制时通过回调把 URL 传回来
        // 这里我们遍历 Documents 目录找最新的 mov 和 csv
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let fileURLs = try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            
            // 找最新的 .mov
            if let video = fileURLs.filter({ $0.pathExtension == "mov" }).sorted(by: {
                let d1 = try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate
                let d2 = try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate
                return d1 ?? Date() > d2 ?? Date()
            }).first {
                self.lastVideoUrl = video
            }
            
            // 找最新的 .csv
            if let csv = fileURLs.filter({ $0.pathExtension == "csv" }).sorted(by: {
                let d1 = try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate
                let d2 = try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate
                return d1 ?? Date() > d2 ?? Date()
            }).first {
                self.lastCsvUrl = csv
            }
            
            print("Found video: \(lastVideoUrl?.lastPathComponent ?? "nil")")
            
        } catch {
            print("Error finding files: \(error)")
        }
    }

    func startTimer() {
        recordingTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            recordingTime += 1
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        recordingTime = 0
    }
    
    func formatTime(_ totalSeconds: TimeInterval) -> String {
        let min = Int(totalSeconds) / 60
        let sec = Int(totalSeconds) % 60
        return String(format: "%02d:%02d", min, sec)
    }
}

// 小组件：数据显示框
struct DataBox: View {
    let label: String
    let value: Double
    var body: some View {
        VStack(spacing: 0) {
            Text(label).font(.system(size: 10)).foregroundColor(.yellow)
            Text(String(format: "%.1f", value))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(width: 40, height: 35)
        .background(Color.white.opacity(0.1))
        .cornerRadius(4)
    }
}

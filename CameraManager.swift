//
//  CameraManager.swift
//  RoadLogger
//
//  Created by Pan Zhang on 2026/1/31.
//
import SwiftUI  // <--- 必须添加这一行，否则无法识别 ObservableObject
import AVFoundation
import Combine  // 显式导入 Combine 也是个好习惯

class CameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    // 使用 @Published 让 UI 可以监听变化
    @Published var session = AVCaptureSession()
    @Published var isRecording = false
    
    private var movieOutput = AVCaptureMovieFileOutput()
    
    override init() {
        super.init()
        // 建议在初始化时检查权限，这里直接调用设置
        setupCamera()
    }
    
    func setupCamera() {
        // 所有的相机配置必须在 beginConfiguration 和 commitConfiguration 之间
        session.beginConfiguration()
        
        // 1. 设置视频输入 (后置广角摄像头)
        if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let videoInput = try? AVCaptureDeviceInput(device: videoDevice) {
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
        }
        
        // 2. 设置音频输入 (麦克风)
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            }
        }
        
        // 3. 设置文件输出 (用于录制)
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        
        session.commitConfiguration()
        
        // 4. 启动相机流 (必须在后台线程运行，否则会卡死 UI)
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
        }
    }
    
    func startRecording(sessionTimestamp: Int) {
        // 获取沙盒 Documents 路径
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // 生成唯一文件名
        let fileName = "Video_\(sessionTimestamp).mov"
        let fileUrl = documentsPath.appendingPathComponent(fileName)
        
        // 开始录制
        movieOutput.startRecording(to: fileUrl, recordingDelegate: self)
        
        // 更新 UI 状态 (确保在主线程)
        DispatchQueue.main.async {
            self.isRecording = true
        }
    }
    
    func stopRecording() {
        movieOutput.stopRecording()
        
        // 更新 UI 状态
        DispatchQueue.main.async {
            self.isRecording = false
        }
    }
    
    // AVCaptureFileOutputRecordingDelegate 代理方法：录制完成回调
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("录制出错: \(error.localizedDescription)")
        } else {
            print("视频已成功保存到: \(outputFileURL)")
        }
    }
}

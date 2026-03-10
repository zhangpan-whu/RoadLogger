//
//  CameraManager.swift
//  RoadLogger
//

import SwiftUI
import AVFoundation
import Combine

class CameraManager: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    @Published var session = AVCaptureSession()
    @Published var isRecording = false
    
    private var movieOutput = AVCaptureMovieFileOutput()
    
    override init() {
        super.init()
        checkPermissionsAndSetup()
    }
    
    // 新增：检查权限
    private func checkPermissionsAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async { self.setupCamera() }
                }
            }
        default:
            print("相机权限被拒绝")
        }
    }
    
    func setupCamera() {
        session.beginConfiguration()
        
        if let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let videoInput = try? AVCaptureDeviceInput(device: videoDevice) {
            if session.canAddInput(videoInput) { session.addInput(videoInput) }
        }
        
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice) {
            if session.canAddInput(audioInput) { session.addInput(audioInput) }
        }
        
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        
        session.commitConfiguration()
        
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
        }
    }
    
    func startRecording(sessionTimestamp: Int) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileName = "Video_\(sessionTimestamp).mov"
        let fileUrl = documentsPath.appendingPathComponent(fileName)
        
        movieOutput.startRecording(to: fileUrl, recordingDelegate: self)
        DispatchQueue.main.async { self.isRecording = true }
    }
    
    func stopRecording() {
        movieOutput.stopRecording()
        DispatchQueue.main.async { self.isRecording = false }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("录制出错: \(error.localizedDescription)")
        } else {
            print("视频已成功保存到: \(outputFileURL)")
        }
    }
}


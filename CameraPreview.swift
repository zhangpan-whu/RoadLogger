//
//  CameraPreview.swift
//  RoadLogger
//
//  Created by Pan Zhang on 2026/1/31.
//

import SwiftUI
import AVFoundation

//1. 创建一个自定义的UIView, 专门用于承载视频预览
class VideoPreviewView: UIView{
    // 关键修改： 告诉系统这个View的基础图层就是AVCaptureVideoPreviewLayer
    override class var layerClass: AnyClass{
        return AVCaptureVideoPreviewLayer.self
    }
    
    // 提供一个便捷属性来访问这个图层
    var videoPreviewLayer: AVCaptureVideoPreviewLayer{
        return layer as! AVCaptureVideoPreviewLayer
    }
}

// 2. SwiftUI包装器
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> VideoPreviewView {
        let view = VideoPreviewView()
        view.backgroundColor = .black // 设置背景色，避免加载时闪白
        
        // 将相机Session绑定在图层上
        view.videoPreviewLayer.session = session
        // 设置画面拉伸模式: 保持比例并填满屏幕
        view.videoPreviewLayer.videoGravity = .resizeAspectFill // 保持比例填满屏幕
        
        return view
    }
    
    // 更新 UIView (当布局发生变化时调用)
    func updateUIView(_ uiView: VideoPreviewView, context: Context) {
        // 因为重写了layerClass，系统会自动处理尺寸变化，这里不需要写任何代码了！
    }
}


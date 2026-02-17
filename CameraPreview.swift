//
//  CameraPreview.swift
//  RoadLogger
//
//  Created by Pan Zhang on 2026/1/31.
//

import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    // 创建 UIView
    func makeUIView(context: Context) -> UIView {
        // 1. 创建一个普通的 UIView，初始 frame 为零
        let view = UIView(frame: .zero)
        view.backgroundColor = .black // 设置背景色，避免加载时闪白
        
        // 2. 创建预览层
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill // 保持比例填满屏幕
        
        // 3. 将预览层添加到视图的 layer 中
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    // 更新 UIView (当布局发生变化时调用)
    func updateUIView(_ uiView: UIView, context: Context) {
        // 关键步骤：在布局更新时，修正 previewLayer 的大小
        // 这样无论屏幕旋转还是分屏，预览层都能正确填满
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.frame = uiView.bounds
        }
    }
}

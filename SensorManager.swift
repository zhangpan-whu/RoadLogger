//
//  SensorManager.swift
//  RoadLogger
//
//  Created by Pan Zhang on 2026/1/31.
//

import Foundation
import SwiftUI  // <--- 必须添加这一行，否则无法识别 ObservableObject
import CoreMotion
import CoreLocation
import Combine  // 显式导入 Combine 也是个好习惯

// 用于 UI 显示的简单结构体
struct ThreeAxisData {
    var x: Double = 0.0
    var y: Double = 0.0
    var z: Double = 0.0
}

// 用于 CSV 存储的详细数据点
struct SensorDataPoint {
    let timestamp: TimeInterval
    let accX: Double
    let accY: Double
    let accZ: Double
    let gyroX: Double
    let gyroY: Double
    let gyroZ: Double
    let lat: Double
    let lon: Double
    let speed: Double
}

class SensorManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    static let shared = SensorManager()
    
    private let motionManager = CMMotionManager()
    private let locationManager = CLLocationManager()
    
    // MARK: - UI 绑定的实时数据 (新增部分)
    // 这里的 @Published 属性会让 ContentView 自动刷新
    @Published var acceleration = ThreeAxisData()
    @Published var rotation = ThreeAxisData()
    @Published var currentSpeed: Double = 0.0
    @Published var currentLocation: CLLocation? // 新增：公开位置信息
    
    // MARK: - 录制状态
    @Published var isRecording = false
    
    // 内部数据存储
    private var dataPoints: [SensorDataPoint] = []
    private var timer: Timer?
    private var sessionTimestamp: Int = 0
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - 控制方法
    
    func startRecording(sessionTimestamp: Int) {
        guard !isRecording else { return }
        
        self.sessionTimestamp = sessionTimestamp // 👈 保存会话 ID
        // 清空旧数据
        dataPoints.removeAll()
        isRecording = true
        
        // 启动传感器 (10hz)
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1
            motionManager.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical)
        }
        
        locationManager.startUpdatingLocation()
        
        // 启动定时器：既用于采集数据存 CSV，也用于更新 UI
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateData()
        }
    }
    
    func stopRecording() -> URL? {
        guard isRecording else { return nil }
        
        isRecording = false
        timer?.invalidate()
        timer = nil
        
        motionManager.stopDeviceMotionUpdates()
        locationManager.stopUpdatingLocation()
        
        // 重置 UI 显示
        self.acceleration = ThreeAxisData()
        self.rotation = ThreeAxisData()
        self.currentSpeed = 0.0
        
        return saveCSV()
    }
    
    // MARK: - 数据更新逻辑
    
    private func updateData() {
        let timestamp = Date().timeIntervalSince1970
        
        // 1. 获取原始数据
        var accX = 0.0, accY = 0.0, accZ = 0.0
        var gyroX = 0.0, gyroY = 0.0, gyroZ = 0.0
        
        if let data = motionManager.deviceMotion {
            accX = data.userAcceleration.x
            accY = data.userAcceleration.y
            accZ = data.userAcceleration.z
            gyroX = data.rotationRate.x
            gyroY = data.rotationRate.y
            gyroZ = data.rotationRate.z
        }
        
        let lat = currentLocation?.coordinate.latitude ?? 0.0
        let lon = currentLocation?.coordinate.longitude ?? 0.0
        let speed = max(0, (currentLocation?.speed ?? 0.0) * 3.6) // km/h
        
        // 2. 更新 UI (@Published 属性)
        // 这一步解决了 "Value of type 'SensorManager' has no member 'acceleration'" 的报错
        self.acceleration = ThreeAxisData(x: accX, y: accY, z: accZ)
        self.rotation = ThreeAxisData(x: gyroX, y: gyroY, z: gyroZ)
        self.currentSpeed = speed
        
        // 3. 如果正在录制，保存到内存数组
        if isRecording {
            let point = SensorDataPoint(
                timestamp: timestamp,
                accX: accX, accY: accY, accZ: accZ,
                gyroX: gyroX, gyroY: gyroY, gyroZ: gyroZ,
                lat: lat, lon: lon, speed: speed
            )
            dataPoints.append(point)
        }
    }
    
    // MARK: - CSV 导出
    
    private func saveCSV() -> URL? {
        let fileName = "Sensor_\(sessionTimestamp).csv"
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(fileName)
        
        var csvText = "SamplingTime,AccelerationX,AccelerationY,AccelerationZ,GyroX,GyroY,GyroZ,Latitude,Longitude,speed\n"
        
        for point in dataPoints {
            let line = String(format: "%.3f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.6f,%.6f,%.2f\n",
                              point.timestamp,
                              point.accX, point.accY, point.accZ,
                              point.gyroX, point.gyroY, point.gyroZ,
                              point.lat, point.lon, point.speed)
            csvText.append(line)
        }
        
        do {
            try csvText.write(to: path, atomically: true, encoding: .utf8)
            return path
        } catch {
            print("CSV Error: \(error)")
            return nil
        }
    }
    
    // MARK: - Location Delegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        self.currentLocation = latest
    }
}


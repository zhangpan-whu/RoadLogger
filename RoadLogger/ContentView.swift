//
//  ContentView.swift
//  RoadLogger
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

// 新增：端侧分析结果结构
struct EdgeAnalysisResult: Codable {
    var hardAccelerationCount: Int = 0 // 急加速次数
    var hardBrakingCount: Int = 0      // 急刹车次数
    var hardCorneringCount: Int = 0    // 急转向次数
}

// 历史记录数据结构
struct DrivingRecord: Codable, Identifiable {
    let id = UUID()
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval
    let location: LocationCoordinate2D
    let videoUrl: String
    let csvUrl: String
    var analysisResult: AnalysisResponse?
    var edgeAnalysisResult: EdgeAnalysisResult? // 新增端侧分析结果
    var uploadStatus: String // "pending", "uploaded", "failed", "analyzed"
    
    struct LocationCoordinate2D: Codable {
        let latitude: Double
        let longitude: Double
    }
    
    init(startTime: Date, endTime: Date, duration: TimeInterval, location: CLLocationCoordinate2D,
         videoUrl: URL, csvUrl: URL, analysisResult: AnalysisResponse?, uploadStatus: String) {
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.location = LocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
        self.videoUrl = videoUrl.path
        self.csvUrl = csvUrl.path
        self.analysisResult = analysisResult
        self.uploadStatus = uploadStatus
    }
    
    var getVideoUrl: URL { return URL(fileURLWithPath: videoUrl) }
    var getCsvUrl: URL { return URL(fileURLWithPath: csvUrl) }
    var getCLLocation: CLLocationCoordinate2D { return CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude) }
}

struct ContentView: View {
    @StateObject var cameraManager = CameraManager()
    @StateObject var sensorManager = SensorManager()
    @StateObject var networkManager = NetworkManager()
    
    @State private var recordingTime: TimeInterval = 0
    @State private var timer: Timer? = nil
    @State private var currentSessionTimestamp: Int = 0
    
    @State private var drivingRecords: [DrivingRecord] = []
    @State private var lastVideoUrl: URL?
    @State private var lastCsvUrl: URL?
    @State private var showHistory = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // 1. 相机预览层
                CameraPreview(session: cameraManager.session)
                    .ignoresSafeArea()
                
                // 2. 渐变遮罩 (优化：避开中间区域)
                VStack {
                    LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 120)
                    Spacer()
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 180)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                
                // 3. UI 内容
                VStack {
                    // --- 顶部栏 ---
                    HStack {
                        if cameraManager.isRecording {
                            HStack {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                                Text(formatTime(recordingTime))
                                    .font(.system(.body, design: .monospaced)).bold().foregroundColor(.white)
                            }
                            .padding(8).background(.ultraThinMaterial).cornerRadius(8)
                        } else {
                            Text("准备就绪")
                                .font(.caption).bold().padding(6).background(Color.green).foregroundColor(.white).cornerRadius(4)
                        }
                        
                        Spacer()
                        
                        Button(action: { showHistory.toggle() }) {
                            Image(systemName: "clock.arrow.circlepath").foregroundColor(.white).font(.title2)
                        }
                        .sheet(isPresented: $showHistory) {
                            HistoryView(records: $drivingRecords)
                        }
                    }
                    .padding(.top, 50).padding(.horizontal)
                    
                    Spacer()
                    
                    // --- 仪表盘数据 ---
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading) {
                            Text("传感器数据").font(.caption2).bold().foregroundColor(.gray)
                            HStack {
                                DataBox(label: "X", value: sensorManager.acceleration.x)
                                DataBox(label: "Y", value: sensorManager.acceleration.y)
                                DataBox(label: "Z", value: sensorManager.acceleration.z)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("速度 (km/h)").font(.caption2).bold().foregroundColor(.gray)
                            Text("\(Int(sensorManager.currentSpeed))")
                                .font(.system(.headline, design: .monospaced)).foregroundColor(.white).frame(width: 50)
                        }
                    }
                    .padding(.horizontal).padding(.bottom, 20)
                    
                    // --- 底部控制栏 ---
                    HStack {
                        Color.clear.frame(width: 60, height: 60)
                        Spacer()
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
                        if !cameraManager.isRecording && lastVideoUrl != nil {
                            NavigationLink(destination: RecordDetailView(record: drivingRecords.last, records: $drivingRecords)) {
                                VStack {
                                    Image(systemName: "info.circle").font(.title2)
                                    Text("查看详情").font(.caption2)
                                }
                                .foregroundColor(.white).frame(width: 60, height: 60).background(Color.orange.opacity(0.8)).clipShape(Circle())
                            }
                        } else {
                            Color.clear.frame(width: 60, height: 60)
                        }
                    }
                    .padding(.bottom, 40).padding(.horizontal, 30)
                }
            }
        }
        .onAppear {
            loadRecordsFromStorage()
        }
    }
    
    func saveCurrentRecord(videoUrl: URL, csvUrl: URL, duration: TimeInterval) {
        let endTime = Date()
        let startTime = endTime.addingTimeInterval(-duration)
        let location = CLLocationCoordinate2D(
            latitude: sensorManager.currentLocation?.coordinate.latitude ?? 0,
            longitude: sensorManager.currentLocation?.coordinate.longitude ?? 0
        )
        
        let newRecord = DrivingRecord(
            startTime: startTime, endTime: endTime, duration: duration, location: location,
            videoUrl: videoUrl, csvUrl: csvUrl, analysisResult: nil, uploadStatus: "pending"
        )
        
        drivingRecords.append(newRecord)
        saveRecordsToStorage()
    }
    
    func saveRecordsToStorage() {
        if let encoded = try? JSONEncoder().encode(drivingRecords) {
            UserDefaults.standard.set(encoded, forKey: "DrivingRecords")
        }
    }
    
    func loadRecordsFromStorage() {
        if let data = UserDefaults.standard.data(forKey: "DrivingRecords"),
           let decoded = try? JSONDecoder().decode([DrivingRecord].self, from: data) {
            drivingRecords = decoded
        }
    }
    
    func toggleRecording() {
        if cameraManager.isRecording {
            // 修复 Bug：先保存当前的时间，再停止 Timer
            let finalDuration = recordingTime
            
            cameraManager.stopRecording()
            sensorManager.stopRecording()
            stopTimer()
            
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            lastVideoUrl = documents.appendingPathComponent("Video_\(currentSessionTimestamp).mov")
            lastCsvUrl   = documents.appendingPathComponent("Sensor_\(currentSessionTimestamp).csv")
            
            if let videoUrl = lastVideoUrl, let csvUrl = lastCsvUrl {
                saveCurrentRecord(videoUrl: videoUrl, csvUrl: csvUrl, duration: finalDuration)
            }
        } else {
            let timestamp = Int(Date().timeIntervalSince1970)
            currentSessionTimestamp = timestamp
            networkManager.uploadMessage = ""
            cameraManager.startRecording(sessionTimestamp: timestamp)
            sensorManager.startRecording(sessionTimestamp: timestamp)
            startTimer()
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

// 历史记录视图
struct HistoryView: View {
    @Binding var records: [DrivingRecord]
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            List {
                ForEach(records.reversed(), id: \.id) { record in
                    NavigationLink(destination: RecordDetailView(record: record, records: $records)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(formatDate(record.startTime)).font(.headline)
                                Spacer()
                                Text(formatDuration(record.duration)).font(.subheadline).foregroundColor(.secondary)
                            }
                            Text(getLocationDescription(record.getCLLocation)).font(.subheadline).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onDelete(perform: deleteRecords)
            }
            .navigationTitle("历史记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("删除所有") {
                        records.removeAll()
                        UserDefaults.standard.removeObject(forKey: "DrivingRecords")
                    }.foregroundColor(.red)
                }
            }
        }
    }
    
    func deleteRecords(offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: "DrivingRecords")
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%dm%ds", minutes, seconds)
    }
    
    func getLocationDescription(_ location: CLLocationCoordinate2D) -> String {
        if location.latitude == 0 && location.longitude == 0 { return "未知位置" }
        return String(format: "纬度: %.4f, 经度: %.4f", location.latitude, location.longitude)
    }
}

// 记录详情视图
struct RecordDetailView: View {
    let record: DrivingRecord?
    @Binding var records: [DrivingRecord]
    @StateObject var networkManager = NetworkManager()
    @State private var updatedRecord: DrivingRecord?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var currentRecord: DrivingRecord? {
        updatedRecord ?? record
    }
    
    var body: some View {
        if let rec = currentRecord {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox(label: Label("基本信息", systemImage: "info.circle")) {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(title: "开始时间", value: formatDate(rec.startTime))
                            InfoRow(title: "持续时间", value: formatDuration(rec.duration))
                        }
                    }
                    
                    // 按钮区域
                    HStack(spacing: 16) {
                        // 端侧分析按钮
                        Button(action: { performEdgeAnalysis(for: rec) }) {
                            HStack {
                                Image(systemName: "cpu")
                                Text("端侧分析")
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).padding().background(Color.orange).cornerRadius(10)
                        }
                        
                        // 云端上传按钮
                        Button(action: { Task { await uploadRecord(record: rec) } }) {
                            HStack {
                                Image(systemName: "icloud.and.arrow.up")
                                Text("上传分析")
                            }
                            .foregroundColor(.white).frame(maxWidth: .infinity).padding()
                            .background(rec.uploadStatus == "analyzed" ? Color.gray : Color.blue)
                            .cornerRadius(10)
                        }
                        .disabled(rec.uploadStatus == "uploaded" || rec.uploadStatus == "analyzed")
                    }
                    
                    if !networkManager.uploadMessage.isEmpty {
                        Text(networkManager.uploadMessage)
                            .font(.caption).foregroundColor(networkManager.uploadMessage.contains("成功") ? .green : .red)
                            .padding(6).background(.ultraThinMaterial).cornerRadius(4)
                    }
                    
                    // 结果展示区
                    VStack(spacing: 16) {
                        // 端侧分析结果
                        if let edgeResult = rec.edgeAnalysisResult {
                            GroupBox(label: Label("端侧分析结果 (本地)", systemImage: "bolt.car")) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { Text("不舒适急加速:"); Spacer(); Text("\(edgeResult.hardAccelerationCount) 次").bold().foregroundColor(edgeResult.hardAccelerationCount > 0 ? .red : .green) }
                                    HStack { Text("不舒适急刹车:"); Spacer(); Text("\(edgeResult.hardBrakingCount) 次").bold().foregroundColor(edgeResult.hardBrakingCount > 0 ? .red : .green) }
                                    HStack { Text("不舒适急转向:"); Spacer(); Text("\(edgeResult.hardCorneringCount) 次").bold().foregroundColor(edgeResult.hardCorneringCount > 0 ? .red : .green) }
                                }
                            }
                        }
                        
                        // 云端分析结果
                        if let cloudResult = rec.analysisResult {
                            GroupBox(label: Label("云端分析结果 (大模型)", systemImage: "brain")) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { Text("驾驶评分:"); Spacer(); Text("\(cloudResult.score)/100").fontWeight(.bold).foregroundColor(scoreColor(cloudResult.score)) }
                                    Text("场景总结:").fontWeight(.bold)
                                    Text(cloudResult.summary).multilineTextAlignment(.leading)
                                    if let details = cloudResult.details {
                                        Text("详细建议:").fontWeight(.bold)
                                        Text(details).multilineTextAlignment(.leading)
                                    }
                                }
                            }
                        } else if rec.uploadStatus == "analyzed" {
                            Text("已完成分析，但暂无结果").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center)
                        } else if rec.uploadStatus == "uploaded" {
                            Text("已上传，等待云端分析...").foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("记录详情")
            .navigationBarTitleDisplayMode(.inline)
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("提示"), message: Text(alertMessage), dismissButton: .default(Text("确定")))
            }
        } else {
            Text("记录不存在").frame(maxWidth: .infinity, maxHeight: .infinity).foregroundColor(.secondary)
        }
    }
    
    // 执行端侧分析
    func performEdgeAnalysis(for record: DrivingRecord) {
        let csvUrl = record.getCsvUrl
        guard let content = try? String(contentsOf: csvUrl) else {
            alertMessage = "无法读取本地传感器数据"
            showingAlert = true
            return
        }
        
        let lines = content.components(separatedBy: .newlines)
        var hardAcc = 0
        var hardBrake = 0
        var hardCorner = 0
        
        // 简单阈值设定 (1g ≈ 9.8m/s^2)
        // 假设 Y 轴为纵向，X 轴为横向。根据实际手机摆放可能需要调整
        let accThreshold = 0.35 // 约 3.4 m/s^2
        let gyroThreshold = 0.5 // 约 28度/秒
        
        for (index, line) in lines.enumerated() {
            if index == 0 || line.isEmpty { continue } // 跳过表头和空行
            let columns = line.components(separatedBy: ",")
            if columns.count >= 7 {
                if let accX = Double(columns[1]), let accY = Double(columns[2]), let gyroZ = Double(columns[6]) {
                    // 简易判断逻辑 (实际可加入时间防抖)
                    if accY > accThreshold { hardAcc += 1 }
                    if accY < -accThreshold { hardBrake += 1 }
                    if abs(accX) > accThreshold || abs(gyroZ) > gyroThreshold { hardCorner += 1 }
                }
            }
        }
        
        // 由于采样率是10Hz，连续超标会被多次计算。这里做个简单的除以系数来估算“次数”
        let result = EdgeAnalysisResult(
            hardAccelerationCount: hardAcc / 5,
            hardBrakingCount: hardBrake / 5,
            hardCorneringCount: hardCorner / 5
        )
        
        updateRecordEdgeResult(id: record.id, result: result)
    }
    
    func updateRecordEdgeResult(id: UUID, result: EdgeAnalysisResult) {
        if let index = records.firstIndex(where: { $0.id == id }) {
            var updated = records[index]
            updated.edgeAnalysisResult = result
            records[index] = updated
            updatedRecord = updated
            saveRecordsToStorage()
        }
    }
    
    func uploadRecord(record: DrivingRecord) async {
        networkManager.uploadMessage = "正在上传..."
        let success = await networkManager.uploadFiles(videoUrl: record.getVideoUrl, csvUrl: record.getCsvUrl)
        
        if success {
            networkManager.uploadMessage = "上传成功，等待分析结果..."
            updateRecordStatus(id: record.id, status: "uploaded")
            await fetchAnalysisResult(recordId: record.id)
        } else {
            updateRecordStatus(id: record.id, status: "failed")
            alertMessage = "上传失败，请检查网络连接或服务器配置"
            showingAlert = true
        }
    }
    
    func fetchAnalysisResult(recordId: UUID) async {
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let index = records.firstIndex(where: { $0.id == recordId }),
               let _ = records[index].analysisResult {
                updateRecordStatus(id: recordId, status: "analyzed")
                break
            }
        }
    }
    
    func updateRecordStatus(id: UUID, status: String) {
        if let index = records.firstIndex(where: { $0.id == id }) {
            var updated = records[index]
            updated.uploadStatus = status
            
            if status == "analyzed" {
                let mockResult = AnalysisResponse(score: 85, summary: "驾驶平稳，无急加速或急刹车", details: "建议继续保持良好驾驶习惯")
                updated.analysisResult = mockResult
            }
            
            records[index] = updated
            updatedRecord = updated
            saveRecordsToStorage()
        }
    }
    
    func saveRecordsToStorage() {
        if let encoded = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(encoded, forKey: "DrivingRecords")
        }
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%dm %ds", minutes, seconds)
    }
    
    func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .green }
        else if score >= 60 { return .orange }
        else { return .red }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack {
            Text(title).foregroundColor(.secondary)
            Spacer()
            Text(value).fontWeight(.medium)
        }
    }
}

struct DataBox: View {
    let label: String
    let value: Double
    var body: some View {
        VStack(spacing: 0) {
            Text(label).font(.system(size: 10)).foregroundColor(.yellow)
            Text(String(format: "%.1f", value)).font(.system(.caption, design: .monospaced)).foregroundColor(.white)
        }
        .frame(width: 40, height: 35).background(Color.white.opacity(0.1)).cornerRadius(4)
    }
}

import Foundation
import Combine
import CoreMotion // for accelerator and gyroscope
import CoreHaptics // for vibration
import AudioToolbox.AudioServices
import UIKit

class RecorderCalibrate: ObservableObject {
    
    internal struct RecordSetting {
        var samplingRate: Double = 200
        var maxData: Int = 200
    }
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let manager = CMMotionManager()
    private let vibrator = Vibrator()
    
    private let haveStarted: Bool = false // boolean for vibration check
    private var timerUpdate: AnyCancellable? = nil // timer to update data
    private var timerCountDown: AnyCancellable? = nil // timer to count down before calibrate
    private var timerVibrate: AnyCancellable? = nil // timer to calibrate
    
    var samplingInterval: Double { 1.0 / setting.samplingRate }
    
    @Published var setting: RecorderCalibrate.RecordSetting = RecordSetting()
    @Published var isCalibrating: Bool = false {
        willSet {
            newValue ? startCalibrating() : stopCalibrating()
        }
    }
    
    @Published var accelerometerVectorData: [Double] = []
    @Published var gyroscopeDataY: [Double] = []
    
    @Published var intensityStr: String = ""
    
    
    private let sampleListFileName: String = "sampleList.json"
    private var sampleListFileURL: URL {
        FileManager.default.documentDirectoryURL(appending: sampleListFileName)
    }
    
    // MARK: - Initializer
    
    init() {
        // loadSampleListFromDisk()
    }
    
    // MARK: - De-Initializer
    deinit {
        
    }

    // MARK: - Methods
    
    internal func startCalibrating() {
        guard manager.isDeviceAvailable == true else { return }
        
        self.intensityStr = "Starting in 3"
        
        // start vibrating
        vibrator.vibrateInSeconds(duration: 20)
        
        // Set sampling intervals
        manager.accelerometerUpdateInterval = samplingInterval
        manager.gyroUpdateInterval          = samplingInterval
        
        // Start data updates
        manager.startAccelerometerUpdates()
        manager.startGyroUpdates()
         
        self.startCountingDownTimer()
        
    }
    
    private func startCountingDownTimer() {
        // activate timer for counting down
        var elapsedSeconds = 0
        timerCountDown = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { date in
                elapsedSeconds += 1
                if elapsedSeconds > 3 {
                    self.intensityStr = "Remaining time: 5"
                    self.startMeasuringTimer()
                    self.timerCountDown?.cancel()
                } else {
                    self.intensityStr = "Starting in " + String(3 - elapsedSeconds)
                }
            
        }
    }
    
    private func startMeasuringTimer() {
        // Activate timer
        timerUpdate = Timer.publish(every: samplingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { date in
                guard let accelerometerData = self.manager.accelerometerData,
                    let gyroData = self.manager.gyroData
                    else { return }
                
                self.updateData(accelerometerData:accelerometerData, gyroData:gyroData)

        }
        
        // activate timer for calibration
        var elapsedSeconds = 0
        timerVibrate = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { date in
                elapsedSeconds += 1
                if elapsedSeconds > 5 {
                    // let intensity = String(format: "%.10f", self.getIntensity())
                    self.intensityStr = String(self.getIntensity())
                    print("Intensity: " + self.intensityStr)
                    self.exportToCSV(fileName: "calibration.csv")
                    self.isCalibrating = false
                    self.timerVibrate?.cancel()
                } else {
                    self.intensityStr = "Remaining time: " + String(5 - elapsedSeconds)
                }
            
        }
    }
    
    
    
    internal func stopCalibrating() {
        
        guard manager.isDeviceAvailable == true else { return }
        
        // Invalidate timer
        self.timerUpdate?.cancel()
        self.timerVibrate?.cancel()
        self.timerCountDown?.cancel()
        
        // Stop data updates
        manager.stopAccelerometerUpdates()
        manager.stopGyroUpdates()
        
        self.clearAccelerometerArray()
        self.clearGyroscopeArray()
        
        // cancel the vibration
        vibrator.stopHaptics()
    }
    
    private func updateData(accelerometerData: CMAccelerometerData, gyroData: CMGyroData) -> Void {
        // add accelerometer data to the array
        let currAccelerometerData = sqrt(pow(accelerometerData.acceleration.x, 2) + pow(accelerometerData.acceleration.y, 2) +
             pow(accelerometerData.acceleration.z, 2))
        self.accelerometerVectorData.append(currAccelerometerData)
        
        // add gyroscope data to the array
        // self.gyroscopeDataY.append(gyroData.rotationRate.y)
        
    }
    
    private func getIntensity() -> Double {
        let smoothedAccelerometer = Pressure.calculateSmoothedAverage(values: self.accelerometerVectorData, windowSize: 2)
        print("The other value can be: " + String(self.getDatapoint(sensorData: self.accelerometerVectorData)))
        return Pressure.calculateIntensity(accelerometer: smoothedAccelerometer)
    }
    
    // MARK: - Clear the data
    
    public func clearAccelerometerArray() {
        if (!accelerometerVectorData.isEmpty) {
            self.accelerometerVectorData.removeAll()
        }
    }
    
    public func clearGyroscopeArray() {
        if (!gyroscopeDataY.isEmpty) {
            self.gyroscopeDataY.removeAll()
        }
    }
    
    // MARK: - Get DataPoint
    func getDatapoint(sensorData: [Double]) -> Double {
        var squaredDifferences: [Double]
        squaredDifferences = Pressure.calculateSmoothedAverage(values: sensorData, windowSize: 2)
        for i in 0..<squaredDifferences.count {
            squaredDifferences[i] = squaredDifferences[i] - sensorData[i]
            squaredDifferences[i] = squaredDifferences[i] * squaredDifferences[i]
        }
        
        let average = squaredDifferences.reduce(0, +) / Double(squaredDifferences.count)
        let standardDeviation = sqrt(average)
        return standardDeviation
    }
    
    func exportToCSV(fileName: String) {
        let smoothedAccelerometerVectorData = Pressure.calculateSmoothedAverage(values: self.accelerometerVectorData, windowSize: 2)
        let intensityArr = Pressure.calculateIntensityArr(accelerometer: smoothedAccelerometerVectorData)
        var csvText = "accelerometerVectorData,smoothedAccelerometerVectorData,intensityArr,intensity\n"
        
        for i in 0..<accelerometerVectorData.count {
            if (i == 0) {
                let newLine = "\(accelerometerVectorData[i]),\(smoothedAccelerometerVectorData[i]),\(intensityArr[i]),\(self.getIntensity())\n"
                csvText += newLine
            } else {
                let newLine = "\(accelerometerVectorData[i]),\(smoothedAccelerometerVectorData[i]),\(intensityArr[i])\n"
                csvText += newLine
            }
            
        }
        
        // Create a temporary URL for the file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        
        do {
            try csvText.write(to: tempURL, atomically: true, encoding: .utf8)
            // Create a UIActivityViewController with the temporary file as the activity item
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            // Present the share sheet
            UIApplication.shared.keyWindow?.rootViewController?.present(activityVC, animated: true, completion: nil)
            print("CSV file created at path: \(tempURL)")
        } catch {
            print("Error creating CSV file: \(error)")
        }
    }
    
}

private extension CMMotionManager {
    
    var isDeviceAvailable: Bool {
        return isAccelerometerAvailable
            && isGyroAvailable
    }
}

//
//  BLEManager.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
//

import Foundation
import CoreBluetooth
import Observation

/// BLE 管理器：负责与 BMS 通过蓝牙低功耗通信
/// 非定期后台任务，在收到 BMS 数据后更新 BMSDataStore 缓存
@Observable
final class BLEManager: NSObject {
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var dataStore: BMSDataStore

    // TODO: 根据实际 BMS 设备修改这些 UUID
    private let bmsServiceUUID = CBUUID(string: "0000FF00-0000-1000-8000-00805F9B34FB")
    private let bmsCharacteristicUUID = CBUUID(string: "0000FF01-0000-1000-8000-00805F9B34FB")

    var isScanning: Bool = false

    init(dataStore: BMSDataStore) {
        self.dataStore = dataStore
        super.init()
    }

    /// 开始扫描 BMS 设备
    func startScanning() {
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        dataStore.connectionState = .scanning
        isScanning = true
    }

    /// 停止扫描
    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
        if connectedPeripheral == nil {
            dataStore.connectionState = .disconnected
        }
    }

    /// 断开连接
    func disconnect() {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        dataStore.connectionState = .disconnected
    }

    // MARK: - 数据解析

    /// 解析从 BMS 收到的原始数据
    /// TODO: 根据实际 BMS 协议实现解析逻辑
    private func parseBMSData(_ data: Data) -> BMSData? {
        // 占位实现 — 请根据你的 BMS 协议替换
        // 常见 BMS 协议（如 JBD/小米/大中）通常包含：
        //   - 总电压 (2 bytes, *0.01V)
        //   - 电流 (2 bytes, *0.01A, 有符号)
        //   - SOC (1-2 bytes, %)
        //   - Cell 电压数组 (每个 2 bytes, *0.001V)

        guard data.count >= 4 else { return nil }

        // 示例解析（需替换为真实协议）：
        // let totalVoltage = Double(UInt16(data[0]) << 8 | UInt16(data[1])) * 0.01
        // let current = Double(Int16(bitPattern: UInt16(data[2]) << 8 | UInt16(data[3]))) * 0.01
        // let soc = Double(data[4])
        // ...

        return nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if isScanning {
                    central.scanForPeripherals(withServices: [bmsServiceUUID], options: nil)
                }
            case .poweredOff, .unauthorized, .unsupported:
                dataStore.connectionState = .disconnected
                isScanning = false
            default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any],
                                     rssi RSSI: NSNumber) {
        Task { @MainActor in
            // 找到 BMS 设备，停止扫描并连接
            central.stopScan()
            isScanning = false
            connectedPeripheral = peripheral
            dataStore.connectionState = .connecting
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            dataStore.connectionState = .connected
            peripheral.delegate = self
            peripheral.discoverServices([bmsServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDisconnectPeripheral peripheral: CBPeripheral,
                                     error: Error?) {
        Task { @MainActor in
            dataStore.connectionState = .disconnected
            connectedPeripheral = nil
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let services = peripheral.services else { return }
            for service in services {
                peripheral.discoverCharacteristics([bmsCharacteristicUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverCharacteristicsFor service: CBService,
                                 error: Error?) {
        Task { @MainActor in
            guard let characteristics = service.characteristics else { return }
            for characteristic in characteristics {
                if characteristic.uuid == bmsCharacteristicUUID {
                    // 订阅通知，BMS 会非定期推送数据
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didUpdateValueFor characteristic: CBCharacteristic,
                                 error: Error?) {
        Task { @MainActor in
            guard let data = characteristic.value else { return }

            if let bmsData = parseBMSData(data) {
                dataStore.update(with: bmsData)
            }
        }
    }
}

//
//  BLEManager.swift
//  BMSTracker
//
//  Created by 王如军 on 3/3/26.
//

import Foundation
import CoreBluetooth
import Observation
import os

private let logger = Logger(subsystem: "com.linetkux.BMSTracker", category: "BLE")

// MARK: - 发现的 BLE 设备模型

/// 表示一个已发现的 JK-BMS BLE 设备
struct DiscoveredDevice: Identifiable, Hashable {
    let id: UUID               // CBPeripheral.identifier
    let name: String           // 广播名 (如 "JK-B2A24S15P")
    var rssi: Int              // 信号强度
    let peripheral: CBPeripheral
    let matchReason: String    // 匹配原因: "name" / "FFE0" / "both"

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - JK-BMS 协议版本

enum JKProtocolVersion: String, CustomStringConvertible {
    case unknown   = "unknown"
    case jk04      = "JK04"        // 旧版 (float32 电压)
    case jk02_24s  = "JK02_24S"    // JK02 24S
    case jk02_32s  = "JK02_32S"    // JK02 32S (JK_ 前缀)

    var description: String { rawValue }
}

// MARK: - BLE Manager

/// BLE 管理器：负责与 JK-BMS 通过蓝牙低功耗通信
/// 完整实现扫描→设备列表→连接→帧组装→协议解析全流程
@Observable
final class BLEManager: NSObject {
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var dataStore: BMSDataStore

    // JK-BMS BLE UUID (协议文档 Section 9)
    private let jkServiceUUID = CBUUID(string: "FFE0")
    private let jkCharUUID    = CBUUID(string: "FFE1")
    private let jkWriteCharUUID = CBUUID(string: "FFE2")  // 旧 BLE 模块的写入特征

    // 写入命令码
    private let CMD_CELL_INFO: UInt8   = 0x96
    private let CMD_DEVICE_INFO: UInt8 = 0x97

    // 帧组装缓冲区
    private var frameBuffer = Data()
    private let expectedFrameSize = 300
    private let maxFrameSize = 400

    // 协议版本 (首次收到 Type 0x03 后确定)
    private var protocolVersion: JKProtocolVersion = .unknown
    private var cellInfoReceived = false
    private var cellInfoRetryTimer: Timer?

    // 公开状态
    var isScanning: Bool = false
    var discoveredDevices: [DiscoveredDevice] = []
    var totalDiscoveredCount: Int = 0  // 扫描到的所有 BLE 设备数量 (含非 JK)

    init(dataStore: BMSDataStore) {
        self.dataStore = dataStore
        super.init()
    }

    // MARK: - 公开方法

    /// 开始扫描 JK-BMS 设备
    func startScanning() {
        discoveredDevices.removeAll()
        totalDiscoveredCount = 0
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else if centralManager?.state == .poweredOn {
            beginScan()
        }
        // 如果 state 还不是 poweredOn，centralManagerDidUpdateState 会回调后启动扫描
        isScanning = true
        dataStore.connectionState = .scanning
    }

    /// 停止扫描
    func stopScanning() {
        logger.info("停止扫描")
        centralManager?.stopScan()
        isScanning = false
        if connectedPeripheral == nil {
            dataStore.connectionState = .disconnected
        }
    }

    /// 连接到用户选择的设备
    func connect(to device: DiscoveredDevice) {
        logger.info("连接设备: \(device.name, privacy: .public) (\(device.id)), RSSI=\(device.rssi)")
        centralManager?.stopScan()
        isScanning = false
        connectedPeripheral = device.peripheral
        connectedPeripheral?.delegate = self
        dataStore.connectionState = .connecting
        centralManager?.connect(device.peripheral, options: nil)
    }

    /// 断开连接
    func disconnect() {
        cellInfoRetryTimer?.invalidate()
        cellInfoRetryTimer = nil
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        frameBuffer = Data()
        protocolVersion = .unknown
        cellInfoReceived = false
        dataStore.connectionState = .disconnected
    }

    // MARK: - 私有方法

    private func beginScan() {
        logger.info("开始扫描所有 BLE 设备 (不按 service UUID 过滤，回调里按名称过滤 JK)")
        // 不传 withServices 过滤: 扫描所有 BLE 设备，在 didDiscover 里按名称过滤
        // 这样可以统计总设备数，也避免某些 BMS 不在广播中包含 FFE0 service 的情况
        centralManager?.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    /// 构造 20 字节写入命令帧 (文档 Section 3)
    private func buildCommand(_ address: UInt8, value: UInt32 = 0, length: UInt8 = 0) -> Data {
        var frame: [UInt8] = [
            0xAA, 0x55, 0x90, 0xEB,  // 帧头 (与接收帧 55 AA EB 90 反序)
            address, length,
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00  // CRC 占位
        ]
        let crc = frame[0..<19].reduce(UInt8(0), &+)
        frame[19] = crc
        return Data(frame)
    }

    /// 发送命令到 BMS
    private func sendCommand(_ address: UInt8, value: UInt32 = 0, length: UInt8 = 0) {
        guard let wc = writeCharacteristic, let peripheral = connectedPeripheral else {
            logger.warning("sendCommand(0x\(String(address, radix: 16))) 失败: 未连接或无 writeCharacteristic")
            return
        }
        let cmd = buildCommand(address, value: value, length: length)
        let writeType: CBCharacteristicWriteType =
            wc.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        logger.debug("发送命令: 0x\(String(address, radix: 16)), \(cmd.count) bytes, writeType=\(writeType == .withResponse ? "withResponse" : "withoutResponse")")
        peripheral.writeValue(cmd, for: wc, type: writeType)
    }

    // MARK: - 帧组装 (文档 Section 9.2)

    private func assembleFrame(_ data: Data) {
        let isHeader = data.count >= 4
            && data[0] == 0x55 && data[1] == 0xAA
            && data[2] == 0xEB && data[3] == 0x90

        if isHeader {
            // 新帧头检测到 → 开始新帧
            let frameType: String = data.count > 4
                ? "0x\(String(data[4], radix: 16))"
                : "?"
            if !frameBuffer.isEmpty {
                logger.notice("新帧头: 丢弃未完成帧 \(self.frameBuffer.count, privacy: .public) bytes")
            }
            logger.notice("帧头检测: frameType=\(frameType, privacy: .public), 数据包=\(data.count, privacy: .public) bytes")
            frameBuffer = Data()
        } else if frameBuffer.isEmpty {
            // 尚未收到帧头 → 丢弃数据 (防止 CRC 失败后错位累积)
            return
        }

        frameBuffer.append(data)
        logger.debug("帧组装: +\(data.count) bytes, 缓冲区=\(self.frameBuffer.count)/\(self.expectedFrameSize) bytes")

        // 防止异常累积
        if frameBuffer.count > maxFrameSize {
            logger.warning("帧超过最大长度 \(self.frameBuffer.count, privacy: .public), 丢弃")
            frameBuffer = Data()
            return
        }

        // 组装完成检查
        if frameBuffer.count >= expectedFrameSize {
            let bytes = [UInt8](frameBuffer)
            let computedCRC = bytes[0..<299].reduce(UInt8(0), &+)
            let remoteCRC = bytes[299]

            guard computedCRC == remoteCRC else {
                // Dump first 8 bytes to help debug alignment
                let hexHead = bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
                logger.warning("CRC mismatch: computed=0x\(String(computedCRC, radix: 16), privacy: .public), remote=0x\(String(remoteCRC, radix: 16), privacy: .public), head=\(hexHead, privacy: .public)")
                frameBuffer = Data()
                return
            }

            // CRC 通过 → 解析
            logger.notice("帧完整: \(bytes.count, privacy: .public) bytes, CRC=0x\(String(remoteCRC, radix: 16), privacy: .public) OK")
            let completeFrame = Array(bytes[0..<300])
            frameBuffer = Data()
            parseFrame(completeFrame)
        }
    }

    // MARK: - 帧分发 (文档 Section 11.2 Step 5)

    private func parseFrame(_ data: [UInt8]) {
        let frameType = data[4]
        logger.notice("解析帧: Type=0x\(String(frameType, radix: 16), privacy: .public), protocol=\(String(describing: self.protocolVersion), privacy: .public)")
        switch frameType {
        case 0x03:
            parseDeviceInfo(data)
        case 0x02:
            switch protocolVersion {
            case .jk04:     parseJK04CellInfo(data)
            case .jk02_32s: parseJK02CellInfo(data, is32S: true)
            default:        parseJK02CellInfo(data, is32S: false)
            }
        case 0x01:
            // Settings 帧 — 暂不解析
            break
        default:
            break
        }
    }

    // MARK: - 设备信息解析 + 协议版本检测 (文档 Section 7.6)

    private func parseDeviceInfo(_ data: [UInt8]) {
        let vendorID = String(bytes: data[6..<22], encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters.union(.init(charactersIn: "\0"))) ?? ""
        let swVersion = String(bytes: data[30..<38], encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters.union(.init(charactersIn: "\0"))) ?? ""

        // 协议版本检测 (文档 Section 7.7)
        if vendorID.hasPrefix("JK_") {
            protocolVersion = .jk02_32s
        } else if vendorID.hasPrefix("JK-") {
            let major = Int(swVersion.prefix(while: { $0 != "." })) ?? 10
            protocolVersion = major < 10 ? .jk04 : .jk02_24s
        }

        logger.info("Device: \(vendorID, privacy: .public), FW: \(swVersion, privacy: .public), Protocol: \(self.protocolVersion)")

        // 延迟发送 0x96: BMS 可能需要间隔才能处理下一条命令
        // esphome 在单独的 update() 周期中发送 0x96 (不是立即)
        cellInfoReceived = false
        scheduleCellInfoRequest()
    }

    /// 定期发送 0x96 直到收到 Cell Info (模仿 esphome update() 周期)
    private func scheduleCellInfoRequest() {
        cellInfoRetryTimer?.invalidate()
        cellInfoRetryTimer = nil
        
        Task { @MainActor [weak self] in
            // 首次延迟 1 秒 (给 BMS 处理时间)
            try? await Task.sleep(for: .seconds(1))
            guard let self, self.connectedPeripheral != nil, !self.cellInfoReceived else { return }
            
            logger.notice("发送 0x96 请求电芯数据 (首次)")
            self.sendCommand(self.CMD_CELL_INFO)
            
            // 如果 3 秒后仍未收到, 继续重试, 最多重试 5 次
            for attempt in 2...6 {
                try? await Task.sleep(for: .seconds(3))
                guard self.connectedPeripheral != nil, !self.cellInfoReceived else { return }
                logger.notice("发送 0x96 请求电芯数据 (重试 #\(attempt, privacy: .public))")
                self.sendCommand(self.CMD_CELL_INFO)
            }
        }
    }

    // MARK: - JK02 Cell Info 解析 (文档 Section 2 / Section 11.2 Step 6)

    private func parseJK02CellInfo(_ data: [UInt8], is32S: Bool) {
        cellInfoReceived = true
        var effectiveIs32S = is32S

        // 自动检测 32S 帧格式:
        // 有些 "JK-" 前缀的设备 (如 JK-BD4A20S4P) 实际使用 32S 帧布局
        // 24S: totalVoltage at offset 118, 32S: at offset 150 (118+32)
        if !effectiveIs32S {
            var cellSum: Double = 0
            for i in 0..<24 {
                let v = Double(uint16LE(data, i * 2 + 6)) * 0.001
                if v > 0 { cellSum += v }
            }
            let totalV_24S = Double(uint32LE(data, 118)) * 0.001
            let totalV_32S = Double(uint32LE(data, 150)) * 0.001

            if totalV_24S < 1.0 && cellSum > 5.0 && totalV_32S > 5.0
                && abs(totalV_32S - cellSum) < cellSum * 0.1 {
                logger.notice("⚠️ 自动切换到 32S 帧格式: 24S=\(String(format: "%.1f", totalV_24S), privacy: .public)V 32S=\(String(format: "%.1f", totalV_32S), privacy: .public)V 电芯和=\(String(format: "%.1f", cellSum), privacy: .public)V")
                effectiveIs32S = true
                if protocolVersion == .jk02_24s {
                    protocolVersion = .jk02_32s
                }
            }
        }

        let offset = effectiveIs32S ? 16 : 0
        let cellCount = effectiveIs32S ? 32 : 24

        var cellVoltages: [Double] = []
        for i in 0..<cellCount {
            let v = Double(uint16LE(data, i * 2 + 6)) * 0.001
            if v > 0 { cellVoltages.append(v) }
        }

        let ofs2 = offset * 2
        let totalVoltage = Double(uint32LE(data, 118 + ofs2)) * 0.001
        let current = Double(Int32(bitPattern: uint32LE(data, 126 + ofs2))) * 0.001
        let soc = Double(data[141 + ofs2])

        // 温度 (esphome 参考)
        let temp1 = Double(Int16(bitPattern: uint16LE(data, 130 + ofs2))) * 0.1
        let temp2 = Double(Int16(bitPattern: uint16LE(data, 132 + ofs2))) * 0.1
        // 32S: MOS 温度在 112+ofs2; 24S: 在 134+ofs2
        let mosfetTemp: Double
        if effectiveIs32S {
            mosfetTemp = Double(Int16(bitPattern: uint16LE(data, 112 + ofs2))) * 0.1
        } else {
            mosfetTemp = Double(Int16(bitPattern: uint16LE(data, 134 + ofs2))) * 0.1
        }

        // 容量信息 (Section 2.11)
        let remainCapacity = Double(uint32LE(data, 142 + ofs2)) * 0.001
        let fullChargeCapacity = Double(uint32LE(data, 146 + ofs2)) * 0.001
        let cycleCount = Int(uint32LE(data, 150 + ofs2))
        let totalCycleCapacity = Double(uint32LE(data, 154 + ofs2)) * 0.001

        let bmsData = BMSData(
            current: current,
            soc: soc,
            totalVoltage: totalVoltage,
            cellVoltages: cellVoltages,
            temp1: temp1,
            temp2: temp2,
            mosfetTemp: mosfetTemp,
            remainCapacity: remainCapacity,
            fullChargeCapacity: fullChargeCapacity,
            cycleCount: cycleCount,
            totalCycleCapacity: totalCycleCapacity,
            lastUpdated: Date()
        )
        logger.notice("📊 CellInfo: V=\(String(format: "%.2f", totalVoltage), privacy: .public)V I=\(String(format: "%.2f", current), privacy: .public)A SOC=\(String(format: "%.0f", soc), privacy: .public)% cells=\(cellVoltages.count, privacy: .public) T1=\(String(format: "%.1f", temp1), privacy: .public)°C T2=\(String(format: "%.1f", temp2), privacy: .public)°C MOS=\(String(format: "%.1f", mosfetTemp), privacy: .public)°C remain=\(String(format: "%.1f", remainCapacity), privacy: .public)Ah full=\(String(format: "%.1f", fullChargeCapacity), privacy: .public)Ah cycles=\(cycleCount, privacy: .public)")
        dataStore.update(with: bmsData)
    }

    // MARK: - JK04 Cell Info 解析 (文档 Section 2B / Section 11.2 Step 7)

    private func parseJK04CellInfo(_ data: [UInt8]) {
        cellInfoReceived = true
        var cellVoltages: [Double] = []
        var totalVoltage: Double = 0

        for i in 0..<24 {
            let v = Double(ieeeFloat(uint32LE(data, i * 4 + 6)))
            if v > 0 {
                cellVoltages.append(v)
                totalVoltage += v
            }
        }

        // JK04 Cell Info 帧不含电流和 SOC
        let bmsData = BMSData(
            current: 0,
            soc: 0,
            totalVoltage: totalVoltage,
            cellVoltages: cellVoltages,
            temp1: 0, temp2: 0, mosfetTemp: 0,
            remainCapacity: 0, fullChargeCapacity: 0,
            cycleCount: 0, totalCycleCapacity: 0,
            lastUpdated: Date()
        )
        dataStore.update(with: bmsData)
    }

    // MARK: - 字节读取辅助

    private func uint16LE(_ data: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func uint32LE(_ data: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) |
        (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }

    private func ieeeFloat(_ raw: UInt32) -> Float {
        Float(bitPattern: raw)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if isScanning {
                    beginScan()
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
            totalDiscoveredCount += 1

            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
                ?? peripheral.name
                ?? "Unknown"
            let rssi = RSSI.intValue
            let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []

            // 判断匹配条件:
            // 1. 设备名以 "JK-" 或 "JK_" 开头 (文档 Section 7)
            // 2. 广播中包含 FFE0 service UUID (JK-BMS 的 GATT service)
            // esphome 按 MAC 地址直连，不做名称过滤; 我们同时支持名称和 service UUID 匹配
            let nameMatch = name.hasPrefix("JK-") || name.hasPrefix("JK_")
            let serviceMatch = serviceUUIDs.contains(self.jkServiceUUID)

            guard nameMatch || serviceMatch else {
                // 非 JK 设备，仅计数不入列表
                if totalDiscoveredCount <= 20 || totalDiscoveredCount % 50 == 0 {
                    logger.debug("跳过设备 #\(self.totalDiscoveredCount): \(name, privacy: .public), services=\(serviceUUIDs.map { $0.uuidString }, privacy: .public)")
                }
                return
            }

            let reason = (nameMatch && serviceMatch) ? "both" : (nameMatch ? "name" : "FFE0")
            logger.notice("✅ JK-BMS 匹配 #\(self.discoveredDevices.count + 1): \(name, privacy: .public), RSSI=\(rssi), reason=\(reason, privacy: .public), services=\(serviceUUIDs.map { $0.uuidString }, privacy: .public)")

            // 更新已发现列表 (去重)
            if let idx = discoveredDevices.firstIndex(where: { $0.id == peripheral.identifier }) {
                discoveredDevices[idx].rssi = rssi
            } else {
                discoveredDevices.append(DiscoveredDevice(
                    id: peripheral.identifier,
                    name: name,
                    rssi: rssi,
                    peripheral: peripheral,
                    matchReason: reason
                ))
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            dataStore.connectionState = .connected
            peripheral.delegate = self
            peripheral.discoverServices([jkServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didFailToConnect peripheral: CBPeripheral,
                                     error: Error?) {
        Task { @MainActor in
            logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown")")
            dataStore.connectionState = .disconnected
            connectedPeripheral = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                     didDisconnectPeripheral peripheral: CBPeripheral,
                                     error: Error?) {
        Task { @MainActor in
            dataStore.connectionState = .disconnected
            connectedPeripheral = nil
            writeCharacteristic = nil
            notifyCharacteristic = nil
            frameBuffer = Data()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let services = peripheral.services else { return }
            logger.info("发现 \(services.count) 个服务: \(services.map { $0.uuid.uuidString }, privacy: .public)")
            for service in services where service.uuid == jkServiceUUID {
                // 发现 FFE1 和 FFE2 (旧模块用 FFE2 写入, 文档 Section 9.1)
                peripheral.discoverCharacteristics([jkCharUUID, jkWriteCharUUID], for: service)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didDiscoverCharacteristicsFor service: CBService,
                                 error: Error?) {
        Task { @MainActor in
            guard let characteristics = service.characteristics else { return }

            for char in characteristics {
                logger.info("特征: \(char.uuid.uuidString, privacy: .public), properties=0x\(String(char.properties.rawValue, radix: 16), privacy: .public)")

                if char.uuid == jkCharUUID {
                    // FFE1: 可能同时有 Write 和 Notify, 也可能拆成两个 handle
                    if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                        notifyCharacteristic = char
                    }
                    if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                        writeCharacteristic = char
                    }
                } else if char.uuid == jkWriteCharUUID {
                    // FFE2: 旧模块备用写入特征 — 仅在 FFE1 没有写入能力时使用
                    // esphome 始终用 FFE1 写入命令, FFE2 只是 fallback
                    if writeCharacteristic == nil,
                       char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                        writeCharacteristic = char
                        logger.info("使用旧模块 FFE2 作为写入特征 (FFE1 无写入能力)")
                    } else {
                        logger.info("跳过 FFE2 写入: FFE1 已具备写入能力")
                    }
                }
            }

            // 订阅通知 (文档 Section 11.2 Step 3)
            if let nc = notifyCharacteristic {
                peripheral.setNotifyValue(true, for: nc)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                 error: Error?) {
        Task { @MainActor in
            guard error == nil else {
                logger.error("Notification subscription failed: \(error!)")
                return
            }
            // 订阅成功 → 发送 0x97 触发 BMS 推送数据 (文档 Section 3)
            sendCommand(CMD_DEVICE_INFO)
            logger.info("Subscribed to notifications, sent 0x97 device info request")
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                 didUpdateValueFor characteristic: CBCharacteristic,
                                 error: Error?) {
        Task { @MainActor in
            guard let data = characteristic.value, error == nil else { return }
            // 帧组装 (文档 Section 9.2 / Section 11.2 Step 4)
            assembleFrame(data)
        }
    }
}

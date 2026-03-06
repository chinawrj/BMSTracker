# JK-BMS BLE 协议字段详解

> 通过反编译极空BMS 5.12.0 APK（QML数据绑定 + 原生C++协议解析）并结合开源社区
> [esphome-jk-bms](https://github.com/syssi/esphome-jk-bms) 的逆向分析整理。

---

## 1. 帧格式概览

```
┌──────────┬──────────┬─────────┬──────────────────────────┬──────┐
│ Header   │ Cmd/Type │ Counter │ Data (292 bytes)         │ CRC  │
│ 4 bytes  │ 1 byte   │ 1 byte  │                          │ 1 B  │
└──────────┴──────────┴─────────┴──────────────────────────┴──────┘
  55 AA EB 90   0x02      N         ...                       sum
```

- **Header**: `55 AA EB 90`（固定4字节，注意APK中存储顺序为 `AA 55 90 EB`）
- **BLE Service/Characteristic**: UUID `0xFFE0` / `0xFFE1`
- **帧总长**: 300 字节
- **CRC**: 字节[0..298]的简单求和，取低8位，存放在字节[299]
- **字节序**: 小端 (Little-Endian)

### 帧类型 (Byte 4)

| 帧类型 | 含义 | 对应命令 |
|--------|------|---------|
| `0x01` | 设置/配置帧 | 命令 `0x97` 请求 |
| `0x02` | 实时电芯数据帧 | 命令 `0x96` 请求 |
| `0x03` | 设备信息帧 | 命令 `0x97` 请求 |

### 协议版本

| 版本 | 说明 | 电芯数 | 电芯电压字节 |
|------|------|--------|-------------|
| JK04 | 旧版 | 24S | float32 (4字节/电芯) |
| JK02_24S | 新版24S | 最多24S | uint16 (2字节/电芯) |
| JK02_32S | 新版32S | 最多32S | uint16 (2字节/电芯) |

---

## 2. 实时数据帧 (Type 0x02) - JK02_24S 协议

**这是你最关心的帧，包含电压、电流、温度、SOC等所有实时数据。**

### 发送请求

```
发送: AA 55 90 EB 96 00 00 00 00 00 00 00 00 00 00 00 00 00 00 [CRC]
        Header     Cmd Len ---------- Data (全0) ----------    CRC
```

### 接收响应 (300字节)

> 以下 `offset` 对于 JK02_24S = 0，JK02_32S = 16

#### 2.1 帧头与计数器

| 偏移 | 长度 | QML字段 | 含义 | 系数 | 单位 |
|------|------|---------|------|------|------|
| 0 | 4 | — | 帧头 `55 AA EB 90` | — | — |
| 4 | 1 | — | 帧类型 `0x02` | — | — |
| 5 | 1 | — | 帧计数器（递增） | — | — |

#### 2.2 单体电压 `cellVol` ⭐

| 偏移 | 长度 | QML字段 | 含义 | 系数 | 单位 |
|------|------|---------|------|------|------|
| 6 | 2 | `cellVol.dataAt(0)` | 电芯1电压 | ×0.001 | V |
| 8 | 2 | `cellVol.dataAt(1)` | 电芯2电压 | ×0.001 | V |
| 10 | 2 | `cellVol.dataAt(2)` | 电芯3电压 | ×0.001 | V |
| ... | ... | ... | ... | ... | ... |
| 6+2×(N-1) | 2 | `cellVol.dataAt(N-1)` | 电芯N电压 | ×0.001 | V |

- 24S: 偏移 6~53，共24个电芯，每个2字节（uint16 LE）
- 32S: 偏移 6~69，共32个电芯，每个2字节
- **示例**: `0xFF 0x0C` = 0x0CFF = 3327 → 3.327V

#### 2.3 电芯状态位

| 偏移 | 长度 | QML字段 | 含义 | 说明 |
|------|------|---------|------|------|
| 54+ofs | 4 | `cellStatus` | 启用电芯掩码 | 每bit代表一个电芯是否启用 |

```
0x0F 0x00 0x00 0x00 → 4个电芯启用
0xFF 0x00 0x00 0x00 → 8个电芯启用
0xFF 0xFF 0x00 0x00 → 16个电芯启用
0xFF 0xFF 0xFF 0x00 → 24个电芯启用
0xFF 0xFF 0xFF 0xFF → 32个电芯启用
```

#### 2.4 电芯统计

| 偏移 | 长度 | QML字段 | 含义 | 系数 | 单位 |
|------|------|---------|------|------|------|
| 58+ofs | 2 | `cellVolAve` | 单体电压平均值 | ×0.001 | V |
| 60+ofs | 2 | `maxVoltDelta` | 最大压差 | ×0.001 | V |
| 62+ofs | 1 | `celMaxVol` | 最高电压电芯编号 | +1 | — |
| 63+ofs | 1 | `celMinVol` | 最低电压电芯编号 | +1 | — |

#### 2.5 单体引线电阻 `cellWireRes`

| 偏移 | 长度 | QML字段 | 含义 | 系数 | 单位 |
|------|------|---------|------|------|------|
| 64+ofs | 2 | `cellWireRes.dataAt(0)` | 电芯1引线电阻 | ×0.001 | Ω |
| 66+ofs | 2 | `cellWireRes.dataAt(1)` | 电芯2引线电阻 | ×0.001 | Ω |
| ... | ... | ... | ... | ... | ... |

- 24S: 偏移 64~111，共24个，每个2字节
- 32S: 偏移 80~143，共32个，每个2字节

#### 2.6 线电阻告警

| 偏移 | 长度 | QML字段 | 含义 |
|------|------|---------|------|
| 114+ofs2 | 4 | `cellWireResStat` | 线电阻告警掩码（每bit对应一个电芯） |

> `ofs2 = offset × 2`（24S: 0, 32S: 32）

#### 2.7 电池总体参数 ⭐

| 偏移 | 长度 | QML字段 | 含义 | 系数 | 单位 | 数据类型 |
|------|------|---------|------|------|------|---------|
| **118+ofs2** | **4** | **`batVol`** | **电池总电压** | **×0.001** | **V** | uint32 LE |
| **122+ofs2** | **4** | **`batWatt`** | **电池功率** | **×0.001** | **W** | uint32 LE ⚠️ |
| **126+ofs2** | **4** | **`batCurrent`** | **电池电流** | **×0.001** | **A** | **int32 LE (有符号)** |

- 电流为有符号数：正=充电，负=放电
- ⚠️ **`batWatt` (偏移122) 为无符号 uint32，无法表示放电功率为负数。** esphome 项目实际上不使用此字段，而是自行计算 `power = batVol × batCurrent`，这样充电时功率为正，放电时为负。建议实际使用时也采用 `batVol × batCurrent` 计算功率。
- **示例**: 总电压 `0x03 0xD0 0x00 0x00` = 0xD003 = 53251 → 53.251V

#### 2.8 温度传感器 `batTemp` ⭐

| 偏移 | 长度 | QML字段 | 含义 | 系数 | 单位 | 数据类型 |
|------|------|---------|------|------|------|---------|
| 130+ofs2 | 2 | `batTemp.dataAt(0)` | 温度传感器 T1 | ×0.1 | °C | int16 LE (有符号) |
| 132+ofs2 | 2 | `batTemp.dataAt(1)` | 温度传感器 T2 | ×0.1 | °C | int16 LE |
| 134+ofs2 | 2 | `sysMosTemp` | MOS管温度 | ×0.1 | °C | int16 LE |

- ⚠️ **32S 版本重要差异**：
  - MOS管温度移至 **偏移 112+offset**（=128），格式同上 int16 ×0.1°C
  - 偏移 134+ofs2（=166）**变为系统报警掩码**（Big-Endian读取），不再是MOS温度
- 温度传感器3-5仅32S版本支持，**注意编号与地址是反序的**：
  - 偏移 222+ofs2: **T5**（不是T3）
  - 偏移 224+ofs2: **T4**
  - 偏移 226+ofs2: **T3**（不是T5）

- **示例**: `0xBE 0x00` = 0x00BE = 190 → 19.0°C

#### 2.9 系统报警 `sysAlarm`

| 偏移 | 长度 | QML字段 | 含义 | 数据类型 |
|------|------|---------|------|----------|
| 136+ofs2 | 2 | `sysAlarm` | 系统报警掩码 | ⚠️ **uint16 Big-Endian** |

> ⚠️ **唯一的大端字段**：此字段的读取方式为 `(data[136] << 8) | data[137]`，与帧中所有其他字段（Little-Endian）不同。
>
> 对于32S版本，此字段移至偏移 134+ofs2（=166），原24S的偏移136处为正常报警位。

**报警位定义**：

| Bit | 含义 |
|-----|------|
| bit 0 | 充电过温保护 (Charge Overtemperature) |
| bit 1 | 充电低温保护 (Charge Undertemperature) |
| bit 2 | 协处理器通信错误 |
| bit 3 | 单体欠压 (Cell Undervoltage) |
| bit 4 | 电池组欠压 (Pack Undervoltage) |
| bit 5 | 放电过流 (Discharge Overcurrent) |
| bit 6 | 放电短路 (Discharge Short Circuit) |
| bit 7 | 放电过温 (Discharge Overtemperature) |
| bit 8 | 线电阻异常 (Wire Resistance) |
| bit 9 | MOS管过温 (MOSFET Overtemperature) |
| bit 10 | 电芯数量不匹配 |
| bit 11 | 电流传感器异常 |
| bit 12 | 单体过压 (Cell Overvoltage) |
| bit 13 | 电池组过压 (Pack Overvoltage) |
| bit 14 | 充电过流保护 (Charge Overcurrent) |
| bit 15 | 充电短路 (Charge Short Circuit) |

#### 2.10 均衡 (Balance)

| 偏移 | 长度 | QML字段 | 含义 | 系数 | 单位 |
|------|------|---------|------|------|------|
| 138+ofs2 | 2 | `equCurrent` | 均衡电流 | ×0.001 | A |
| 140+ofs2 | 1 | `equStatus` | 均衡状态 | — | — |

**均衡状态**：
- `0x00`: 关闭
- `0x01`: 充电均衡中（`equStatus.testBit(0)` = 最低电芯正在充电）
- `0x02`: 放电均衡中（`equStatus.testBit(1)` = 最高电芯正在放电）

#### 2.11 SOC / 容量信息 ⭐

| 偏移 | 长度 | QML字段 | 含义 | 系数 | 单位 |
|------|------|---------|------|------|------|
| **141+ofs2** | **1** | **`socRelativeStateOfCharge`** | **剩余电量百分比** | **1** | **%** |
| **142+ofs2** | **4** | **`socCapabilityRemain`** | **剩余容量** | **×0.001** | **Ah** |
| **146+ofs2** | **4** | **`socFullChargeCapacity`** | **电池实际容量（满充容量）** | **×0.001** | **Ah** |
| **150+ofs2** | **4** | **`socCycleCount`** | **循环次数** | **1** | **次** |
| **154+ofs2** | **4** | **`socCycleCapacity`** | **累计循环容量** | **×0.001** | **Ah** |
| 158+ofs2 | 1 | — | SOH（健康度） | 1 | % |

#### 2.12 充放电开关状态 `sysMosStatus`

| 偏移 | 长度 | QML字段 | 含义 |
|------|------|---------|------|
| 162+ofs2 | 4 | — | 总运行时间 (秒) |
| 166+ofs2 | 1 | `sysMosStatus.itemAt(0)` | 充电MOS开关 (0=关, 1=开) |
| 167+ofs2 | 1 | `sysMosStatus.itemAt(1)` | 放电MOS开关 (0=关, 1=开) |
| 168+ofs2 | 1 | — | 预充电状态 |
| 169+ofs2 | 1 | — | 均衡工作指示 |

#### 2.13 保护解除倒计时

| 偏移 | 长度 | QML字段 | 含义 | 单位 |
|------|------|---------|------|------|
| 170+ofs2 | 2 | `timeDcOCPR` | 放电过流保护解除倒计时 | s |
| 172+ofs2 | 2 | `timeDcSCPR` | 放电短路保护解除倒计时 | s |
| 174+ofs2 | 2 | `timeCOCPR` | 充电过流保护解除倒计时 | s |
| 176+ofs2 | 2 | `timeCSCPR` | 充电短路保护解除倒计时 | s |
| 178+ofs2 | 2 | `timeUVPR` | 单体欠压保护解除倒计时 | s |
| 180+ofs2 | 2 | `timeOVPR` | 单体过压保护解除倒计时 | s |

#### 2.14 温度传感器存在标志

| 偏移 | 长度 | QML字段 | 含义 |
|------|------|---------|------|
| 182+ofs2 | 2 | `tempSensorAbsent` | 温度传感器存在掩码 |

- `bit 0`: MOS温度传感器存在
- `bit 1`: T1温度传感器存在
- `bit 2`: T2温度传感器存在
- `bit 3`: T3温度传感器存在（32S）
- `bit 4`: T4温度传感器存在（32S）
- `bit 5`: T5温度传感器存在（32S）

#### 2.15 其他字段

以下字段在 esphome 源码中均有解析，适用于所有协议版本（除特别标注外）：

| 偏移 | 长度 | 含义 | 系数 | 单位 | 备注 |
|------|------|------|------|------|------|
| 158+ofs2 | 1 | SOH（健康度） | 1 | % | |
| 159+ofs2 | 1 | 预充电状态 | — | 0/1 | |
| 160+ofs2 | 2 | 用户报警 | — | — | 通常为 0xC5 0x09 |
| 162+ofs2 | 4 | 总运行时间 | 1 | 秒 | |
| 183+ofs2 | 1 | 加热状态 | — | 0/1 | |
| 186+ofs2 | 2 | 紧急时间倒计时 | 1 | 秒 | 32S: 用于紧急开关判断 |
| 188+ofs2 | 2 | 放电电流校正因子 | 1 | — | 仅调试用 |
| 190+ofs2 | 2 | 充电电流传感器电压 | ×0.001 | V | 仅调试用 |
| 192+ofs2 | 2 | 放电电流传感器电压 | ×0.001 | V | 仅调试用 |
| 194+ofs2 | 4 | 电池电压校正因子 | 1 | — | 仅调试用 |
| 202+ofs2 | 4 | 电池电压(IEEE754) | IEEE float | V | 仅调试用 |
| 204+ofs2 | 2 | 加热电流 | ×0.001 | A | |
| 213+ofs2 | 1 | 充电器是否插入 | — | 0/1 | |
| 222+ofs2 | 2 | 温度传感器 T5 (32S) | ×0.1 | °C | 注意T5在前 |
| 224+ofs2 | 2 | 温度传感器 T4 (32S) | ×0.1 | °C | |
| 226+ofs2 | 2 | 温度传感器 T3 (32S) | ×0.1 | °C | 注意T3在后 |
| 238+ofs2 | 4 | 进入休眠时间 | 1 | 秒 | |
| 242+ofs2 | 1 | PCL模块状态 | — | 0/1 | |

#### 2.16 32S 专用扩展字段

| 偏移 | 长度 | 含义 | 备注 |
|------|------|------|------|
| 246+ofs2 | 2 | 充电状态耗时 | 秒 |
| 248+ofs2 | 1 | 充电状态ID | 0x00=Bulk, 0x01=Absorption, 0x02=Float |
| 249+ofs2 | 1 | 干触点掩码 | bit1=DRY1 on, bit2=DRY2 on |

#### CRC

| 偏移 | 长度 | 含义 |
|------|------|------|
| 299 | 1 | CRC = sum(bytes[0..298]) & 0xFF |

---

## 2B. 实时数据帧 (Type 0x02) - JK04 协议

> JK04 是 JK-BMS 的旧版协议（如 JK-B2A16S v3 系列），帧长度同样为 300 字节，但**电压和电阻使用 IEEE 754 float32 格式**（4 字节），而非 JK02 系列的 uint16 × 0.001 格式。

### 帧总体结构

| 区域 | 偏移 | 长度 | 说明 |
|------|------|------|------|
| 帧头 | 0~3 | 4 | `55 AA EB 90` |
| 帧类型 | 4 | 1 | `0x02` |
| 帧计数 | 5 | 1 | 递增计数器 |
| 单体电压 | 6~101 | 96 | 24 cells × 4 bytes (float32) |
| 单体电阻 | 102~197 | 96 | 24 cells × 4 bytes (float32) |
| 统计与状态 | 198~298 | 101 | 见下表 |
| CRC | 299 | 1 | sum(bytes[0..298]) & 0xFF |

### 单体电压 (float32)

| 偏移 | 长度 | 含义 | 格式 | 单位 |
|------|------|------|------|------|
| 6 | 4 | Cell Voltage 1 | IEEE 754 float32 LE | V |
| 10 | 4 | Cell Voltage 2 | IEEE 754 float32 LE | V |
| ... | 4 | ... | ... | V |
| 98 | 4 | Cell Voltage 24 | IEEE 754 float32 LE | V |

> **与 JK02 的关键差异**: JK02 使用 `uint16 × 0.001` (2 字节/cell)，JK04 使用 `float32` (4 字节/cell)。因此 JK04 只支持最多 24 cell，而 JK02_32S 可支持 32 cell。
>
> IEEE 754 float32 解码示例: `0xC0 0x61 0x56 0x40` → 小端重组为 `0x405661C0` → float = **3.3497...** V

### 单体电阻 (float32)

| 偏移 | 长度 | 含义 | 格式 | 单位 |
|------|------|------|------|------|
| 102 | 4 | Cell Resistance 1 | IEEE 754 float32 LE | Ω |
| 106 | 4 | Cell Resistance 2 | IEEE 754 float32 LE | Ω |
| ... | 4 | ... | ... | Ω |
| 194 | 4 | Cell Resistance 24 | IEEE 754 float32 LE | Ω |
| 198 | 4 | Cell Resistance 25 (保留) | IEEE 754 float32 LE | Ω |

### 统计与状态字段

| 偏移 | 长度 | 含义 | 格式/系数 | 单位 | 备注 |
|------|------|------|-----------|------|------|
| 202 | 4 | Average Cell Voltage | float32 | V | 可用软件计算替代 |
| 206 | 4 | Delta Cell Voltage | float32 | V | max - min |
| 210 | 4 | Unknown210 | — | — | 始终 `0x00000000` |
| 214 | 4 | Enabled Cells Bitmask | — | — | `0xFFFF0000` = 24 cells? |
| 218 | 1 | Unknown218 | — | — | |
| 219 | 1 | Unknown219 | — | — | |
| 220 | 1 | Balancing Action | 0x00/0x01/0x02 | — | 0=Off, 1=充电均衡, 2=放电均衡 |
| 221 | 1 | Unknown221 | — | — | |
| 222 | 4 | Balance Current | float32 | A | |
| 226 | 7 | Unknown226 | — | — | 始终 `0x00...0x00` |
| 233 | 4 | Unknown233 | float32 | — | 含义待确认 |
| 237 | 4 | Unknown237 | — | — | 始终 `0x40 0x00 0x00 0x00` |
| 241 | 45 | Unknown241~285 | — | — | 大量零填充，含 `0x01 0x01` 等标志 |
| 286 | 4 | Total Runtime (Uptime) | uint32 LE | 秒 | |
| 290 | 4 | Unknown290 | — | — | 始终 `0x00000000` |
| 294 | 4 | Unknown294 | float32? | — | 含义待确认 |
| 298 | 1 | Unknown298 | — | — | |
| 299 | 1 | CRC | sum & 0xFF | — | |

### JK04 与 JK02 Cell Info 帧对比

| 特性 | JK04 | JK02_24S | JK02_32S |
|------|------|----------|----------|
| 电压格式 | float32 (4B) | uint16 × 0.001 (2B) | uint16 × 0.001 (2B) |
| 电阻格式 | float32 (4B) | uint16 × 0.001 (2B) | uint16 × 0.001 (2B) |
| 最大 cell 数 | 24 | 24 | 32 (offset+16) |
| 电压区域 | offset 6~101 | offset 6~53 | offset 6~69 |
| 电阻区域 | offset 102~197 | offset 64~111 | offset 80~143 |
| 总电压 | 软件求和 | offset 118+ofs | offset 118+ofs |
| 电流 | 无 ℹ️ | offset 126+ofs | offset 126+ofs |
| 温度 | 无 ℹ️ | offset 130+ofs | offset 130+ofs |
| SOC | 无 ℹ️ | offset 141+ofs | offset 141+ofs |
| MOS 开关 | 无 ℹ️ | offset 166+ofs | offset 166+ofs |
| Uptime | offset 286 | offset 162+ofs | offset 162+ofs |

> ℹ️ JK04 Cell Info 帧中**不包含**电流、温度、SOC、MOS 开关等字段（这些信息在 JK04 协议中可能通过其他机制获取，或仅在 Settings 帧中体现）。

---

## 3. 写入命令格式

```
偏移:  0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15 16 17 18 19
      AA 55 90 EB Cm Ln V0 V1 V2 V3 00 00 00 00 00 00 00 00 00 CRC

Cm: 命令码 (地址)
Ln: 值的字节长度
V0-V3: 值 (小端序)
CRC: bytes[0..18] 的字节求和
```

### 常用命令码

| 命令码 | 含义 | 值 | 触发响应 |
|--------|------|----|---------|
| `0x96` | 请求实时电芯数据 | 0x00000000 | 返回 Type 0x02 (cell info)，同时启动周期推送 |
| `0x97` | 请求设备信息 | 0x00000000 | 首先返回 Type 0x03 (device info)，随后设备开始周期推送 Type 0x01 (settings) 和 Type 0x02 (cell info) |

### 开关控制命令码

下表列出充放电等开关的写入寄存器地址（因协议版本不同而异）：

| 功能 | JK04 | JK02_24S | JK02_32S | 写入值 | 说明 |
|------|------|----------|----------|--------|------|
| **充电开关** (Charge) | `0x00`* | `0x1D` | `0x1D` | `0x00000001`=开, `0x00000000`=关 | 对应 `batChargeEn` |
| **放电开关** (Discharge) | `0x00`* | `0x1E` | `0x1E` | `0x00000001`=开, `0x00000000`=关 | 对应 `batDischargeEn` |
| **均衡开关** (Balancer) | `0x6C` | `0x1F` | `0x1F` | `0x00000001`=开, `0x00000000`=关 | 对应 `batEquEn` |
| **紧急断电** (Emergency) | — | — | `0x6B` | `0x00000001`=触发 | 仅 32S 支持 |
| **加热开关** (Heating) | — | — | `0x27` | `0x00000001`=开, `0x00000000`=关 | 仅 32S 支持 |
| **禁用温度传感器** (Disable Temp Sensors) | — | — | `0x28` | `0x00000001`=禁用, `0x00000000`=启用 | 仅 32S 支持 |
| **常亮显示** (Display Always On) | — | — | `0x2B` | `0x00000001`=开, `0x00000000`=关 | 仅 32S 支持 |
| **智能睡眠** (Smart Sleep) | — | — | `0x2D` | `0x00000001`=开, `0x00000000`=关 | 仅 32S 支持 |
| **禁用 PCL 模块** (Disable PCL Module) | — | — | `0x2E` | `0x00000001`=禁用, `0x00000000`=启用 | 仅 32S 支持 |
| **定时存储数据** (Timed Stored Data) | — | — | `0x2F` | `0x00000001`=开, `0x00000000`=关 | 仅 32S 支持 |
| **浮充模式** (Float Mode) | — | — | `0x30` | `0x00000001`=开, `0x00000000`=关 | 仅 32S 支持 |

> \* JK04 协议中充电/放电开关地址为 `0x00`，表示该协议版本可能不支持此功能或使用不同机制。

#### 放电开关写入示例

关闭放电 (JK02_24S/32S):
```
AA 55 90 EB 1E 04 00 00 00 00 00 00 00 00 00 00 00 00 00 [CRC]
             │  │  └─── 值: 0x00000000 = 关闭
             │  └────── 长度: 4 bytes
             └───────── 命令码: 0x1E (放电开关)
```

开启放电:
```
AA 55 90 EB 1E 04 01 00 00 00 00 00 00 00 00 00 00 00 00 [CRC]
                  └─── 值: 0x00000001 = 开启
```

#### App 调用链

```
QML: dischargeDelegate.onSwClicked
  → UtilityJs.controlSwitchToggled(root, delegate, d01.batDischargeEn, Transfer.enableDischarge)
    → C++ (Native): Transfer::enableDischarge(param_1, bool, ...)
      → setValueVariant(this, param_1, 4, value, 6000, ...)  // len=4, timeout=6000ms
        → sendValues() → 构造帧 AA 55 90 EB ...
          → checkAndSend() → 计算 CRC → JSuperChannel::writeData()
```

### 参数配置写入寄存器地址表

> 来源: esphome-jk-bms `number/__init__.py`
> 写入格式同上: `AA 55 90 EB [寄存器] [长度] [值 LE] [填充] [CRC]`
> ⚠️ 注意：24S 和 32S 有部分寄存器地址不同（标注 **差异**）

| 寄存器 (24S) | 寄存器 (32S) | 参数 | 写入系数 | 长度 | 单位 | 取值范围 |
|------|------|------|------|------|------|------|
| `0x01` | `0x01` | Smart Sleep 电压 | ×1000 | 1 | V | 0.003~3.650 |
| `0x02` | `0x02` | 单体欠压保护 (Cell UVP) | ×1000 | 4 | V | 1.2~4.35 |
| `0x03` | `0x03` | 单体欠压恢复 (Cell UVPR) | ×1000 | 4 | V | 1.2~4.35 |
| `0x04` | `0x04` | 单体过压保护 (Cell OVP) | ×1000 | 4 | V | 1.2~4.35 |
| `0x05` | `0x05` | 单体过压恢复 (Cell OVPR) | ×1000 | 4 | V | 1.2~4.35 |
| `0x06` | `0x06` | 均衡触发电压差 | ×1000 | 4 | V | 0.003~1.0 |
| `0x07` | `0x07` | SOC 100% 电压 | ×1000 | 4 | V | 0.003~3.650 |
| `0x08` | `0x08` | SOC 0% 电压 | ×1000 | 4 | V | 0.003~3.650 |
| `0x09` | `0x09` | 请求充电电压 (RCV) | ×1000 | 4 | V | 0.003~3.650 |
| `0x0A` | `0x0A` | 请求浮充电压 (RFV) | ×1000 | 4 | V | 0.003~3.650 |
| `0x0B` | `0x0B` | 关机电压 (Power Off) | ×1000 | 4 | V | 1.2~4.35 |
| `0x0C` | `0x0C` | 最大充电电流 | ×1000 | 4 | A | 1.0~600.1 |
| `0x0D` | `0x0D` | 充电过流保护延迟 | ×1 | 4 | s | 2~600 |
| `0x0E` | `0x0E` | 充电过流恢复时间 | ×1 | 4 | s | 2~600 |
| `0x0F` | `0x0F` | 最大放电电流 | ×1000 | 4 | A | 1.0~600.1 |
| `0x10` | `0x10` | 放电过流保护延迟 | ×1 | 4 | s | 2~600 |
| `0x11` | `0x11` | 放电过流恢复时间 | ×1 | 4 | s | 2~600 |
| `0x12` | `0x12` | 短路保护恢复时间 | ×1 | 4 | s | 2~600 |
| `0x13` | `0x13` | 最大均衡电流 | ×1000 | 4 | A | 0.3~10.0 |
| `0x14` | `0x14` | 充电过温保护 | ×10 | 4 | °C | 30~80 |
| `0x15` | `0x15` | 充电过温恢复 | ×10 | 4 | °C | 30~80 |
| `0x16` | `0x16` | 放电过温保护 | ×10 | 4 | °C | 30~80 |
| `0x17` | `0x17` | 放电过温恢复 | ×10 | 4 | °C | 30~80 |
| `0x18` | `0x18` | 充电低温保护 (int32) | ×10 | 4 | °C | -30~20 |
| `0x19` | `0x19` | 充电低温恢复 (int32) | ×10 | 4 | °C | -30~20 |
| `0x1A` | `0x1A` | MOS 过温保护 | ×10 | 4 | °C | 30~100 |
| `0x1B` | `0x1B` | MOS 过温恢复 | ×10 | 4 | °C | 30~100 |
| `0x1C` | `0x1C` | 电芯数量 | ×1 | 4 | — | 2~24 (24S) / 2~32 (32S) |
| `0x20` | `0x20` | 电池容量 | ×1000 | 4 | Ah | 5~2000 |
| **`0x21`** | **`0x64`** | **电压校准** ⚠️差异 | ×1000 | 4 | V | 1.0~200.0 |
| **`0x24`** | **`0x67`** | **电流校准** ⚠️差异 | ×1000 | 4 | A | 0.0~1000.0 |
| **`0x25`** | **`0x21`** | **短路保护延迟** ⚠️差异 | ×1 | 4 | μs | 0~10000000 |
| **`0x26`** | **`0x22`** | **均衡开始电压** ⚠️差异 | ×1000 | 4 | V | 1.2~4.25 |
| — | `0x25` | 放电预充时间 (32S专用) | ×1 | 4 | s | 0~255 |
| — | `0x37` | 加热启动温度 (32S专用) | ×1 | 1 | °C | -40~100 |
| — | `0x38` | 加热停止温度 (32S专用) | ×1 | 1 | °C | -40~100 |
| — | `0xB3` | RCV 时间 (32S专用) | ×10 | 1 | h | 0~25.5 |
| — | `0xB4` | RFV 时间 (32S专用) | ×10 | 1 | h | 0~25.5 |
| `0x9F` | `0x9F` | 用户自定义数据 | ASCII | 变长 | — | 文本字符串 |

> **写入系数说明**: 写入值 = 实际值 × 系数。例如写入 Cell OVP = 3.65V → 值为 `3650 = 0x0E42` → 帧中 `42 0E 00 00`。
> **温度负值**: 充电低温保护等可为负值，使用 int32 有符号整数，例如 -22°C → 值为 `-220 = 0xFFFFFF24`。

### 引线电阻校准写入命令

每个电芯的引线电阻校准值可通过以下寄存器写入：

| 寄存器范围 (24S) | 寄存器范围 (32S) | 含义 | 系数 | 单位 |
|------|------|------|------|------|
| `0x27`~`0x3E` (24个) | 在 Settings 帧偏移 142 起 | 电芯 1~24 引线电阻 | ×1000 | Ω |

写入示例 — 设置电芯 1 引线电阻为 0.5Ω (24S):
```
AA 55 90 EB 27 04 F4 01 00 00 00 00 00 00 00 00 00 00 00 [CRC]
             │  │  └─── 值: 0x000001F4 = 500 → 0.500Ω
             │  └────── 长度: 4 bytes
             └───────── 命令码: 0x27 (电芯1引线电阻)
```

#### 权限控制

在 App UI 层，充放电开关仅在以下条件之一满足时可操作：
- `window.settingsEnabled = true`（已通过设置密码验证）
- `window.isTIANYI = true`（天翼版本）
- `window.isPOWERLI = true`（POWERLI 版本）

但如第 8 章所述，**BMS 固件本身不验证写入权限**，任何 BLE 客户端均可直接发送上述命令。

---

## 4. QML字段与协议映射一览表

> 这是APK中 QML 数据绑定层定义的所有实时数据字段，对应 `JSearchObject objectName: '02'`（实时数据表）

| QML字段名 | 类型 | 中文含义 | 帧偏移(24S) | 数据格式 | 系数 | 单位 |
|-----------|------|---------|-------------|---------|------|------|
| `cellVol` | JArray | 单体电压数组 | 6~53 | uint16 LE × N | ×0.001 | V |
| `cellStatus` | JBit | 电芯启用掩码 | 54 | uint32 LE | — | — |
| `cellVolAve` | JNumeric | 平均单体电压 | 58 | uint16 LE | ×0.001 | V |
| `maxVoltDelta` | JNumeric | 最大压差 | 60 | uint16 LE | ×0.001 | V |
| `celMaxVol` | JNumeric | 最高电压电芯# | 62 | uint8 | +1 | — |
| `celMinVol` | JNumeric | 最低电压电芯# | 63 | uint8 | +1 | — |
| `cellWireRes` | JArray | 引线电阻数组 | 64~111 | uint16 LE × N | ×0.001 | Ω |
| `cellWireResStat` | JBit | 线电阻告警掩码 | 114 | uint32 LE | — | — |
| `batVol` | JNumeric | **电池总电压** | **118** | **uint32 LE** | **×0.001** | **V** |
| `batWatt` | JNumeric | **电池功率** | **122** | **uint32 LE** | **×0.001** | **W** |
| `batCurrent` | JNumeric | **电池电流** | **126** | **int32 LE** | **×0.001** | **A** |
| `batTemp[0]` | JArray | **温度T1** | **130** | **int16 LE** | **×0.1** | **°C** |
| `batTemp[1]` | JArray | **温度T2** | **132** | **int16 LE** | **×0.1** | **°C** |
| `sysMosTemp` | JNumeric | **MOS管温度** | **134** | **int16 LE** | **×0.1** | **°C** |
| `sysAlarm` | JBit | 系统报警标志 ⚠️唯一BE字段 `(data[136]<<8)|data[137]` | 136 | **uint16 BE** | — | — |
| `equCurrent` | JNumeric | 均衡电流 | 138 | int16 LE | ×0.001 | A |
| `equStatus` | JBit | 均衡状态 | 140 | uint8 | — | — |
| `socRelativeStateOfCharge` | JNumeric | **SOC(剩余电量%)** | **141** | **uint8** | **1** | **%** |
| `socCapabilityRemain` | JNumeric | **剩余容量** | **142** | **uint32 LE** | **×0.001** | **Ah** |
| `socFullChargeCapacity` | JNumeric | **满充容量** | **146** | **uint32 LE** | **×0.001** | **Ah** |
| `socCycleCount` | JNumeric | 循环次数 | 150 | uint32 LE | 1 | 次 |
| `socCycleCapacity` | JNumeric | 累计循环容量 | 154 | uint32 LE | ×0.001 | Ah |
| `chargerVol` | JNumeric | 充电器电压 ⚠️esphome未解析,偏移213仅有充电器插入布尔 | — | — | — | V |
| `sysMosStatus[0]` | JTable | 充电MOS开关 | 166 | uint8 | — | 0/1 |
| `sysMosStatus[1]` | JTable | 放电MOS开关 | 167 | uint8 | — | 0/1 |
| `tempSensorAbsent` | JBit | 传感器存在标志 | 182 | uint16 LE | — | — |
| `timeDcOCPR` | JNumeric | 放电过流保护解除时间 | 170 | uint16 LE | 1 | s |
| `timeDcSCPR` | JNumeric | 放电短路保护解除时间 | 172 | uint16 LE | 1 | s |
| `timeCOCPR` | JNumeric | 充电过流保护解除时间 | 174 | uint16 LE | 1 | s |
| `timeCSCPR` | JNumeric | 充电短路保护解除时间 | 176 | uint16 LE | 1 | s |
| `timeUVPR` | JNumeric | 欠压保护解除时间 | 178 | uint16 LE | 1 | s |
| `timeOVPR` | JNumeric | 过压保护解除时间 | 180 | uint16 LE | 1 | s |

---

## 5. 解析示例

### 示例帧 (24S, 16电芯)

```
55 AA EB 90 02 8C FF 0C 01 0D 01 0D FF 0C 01 0D 01 0D FF 0C 01 0D ...
│  Header  │Ty│Ct│ Cell1 │ Cell2 │ Cell3 │ Cell4 │ Cell5 │ Cell6 │...
```

解析：
- Cell 1: `FF 0C` = 0x0CFF = 3327 → **3.327V**
- Cell 2: `01 0D` = 0x0D01 = 3329 → **3.329V**
- Cell 3: `01 0D` = 0x0D01 = 3329 → **3.329V**
- Cell 4: `FF 0C` = 0x0CFF = 3327 → **3.327V**

### 后续字段继续解析：

```
偏移 118: 03 D0 00 00 → 0x0000D003 = 53251 → 总电压: 53.251V
偏移 126: 00 00 00 00 → 电流: 0.000A (空闲)
偏移 130: BE 00       → 0x00BE = 190 → T1温度: 19.0°C
偏移 132: BF 00       → 0x00BF = 191 → T2温度: 19.1°C
偏移 134: D2 00       → 0x00D2 = 210 → MOS温度: 21.0°C
偏移 141: 54          → SOC: 84%
偏移 142: 8E 0B 01 00 → 0x00010B8E = 68494 → 剩余容量: 68.494Ah
偏移 146: 68 3C 01 00 → 0x00013C68 = 81000 → 满充容量: 81.000Ah
偏移 150: 00 00 00 00 → 循环次数: 0
偏移 166: 01          → 充电MOS: 开
偏移 167: 01          → 放电MOS: 开
```

---

## 6. 配置/设置帧 (Type 0x01) - 完整字段映射

> 对应 `JSearchObject objectName: '01'`
> 来源: esphome-jk-bms `decode_jk02_settings_()` + APK QML 交叉验证

### 6.1 JK02_24S/32S Settings 帧字段

> 以下偏移适用于 JK02_24S。JK02_32S 在偏移 142 后有扩展字段（见 6.2 节）。

| 偏移 | 长度 | QML字段名 | 含义 | 系数 | 单位 | 数据类型 |
|------|------|-----------|------|------|------|----------|
| 0 | 4 | — | 帧头 `55 AA EB 90` | — | — | — |
| 4 | 1 | — | 帧类型 `0x01` | — | — | — |
| 5 | 1 | — | 帧计数器 | — | — | — |
| **6** | **4** | — | **Smart Sleep 电压** | **×0.001** | **V** | uint32 LE |
| **10** | **4** | — | **单体欠压保护 (Cell UVP)** | **×0.001** | **V** | uint32 LE |
| **14** | **4** | — | **单体欠压恢复 (Cell UVPR)** | **×0.001** | **V** | uint32 LE |
| **18** | **4** | — | **单体过压保护 (Cell OVP)** | **×0.001** | **V** | uint32 LE |
| **22** | **4** | — | **单体过压恢复 (Cell OVPR)** | **×0.001** | **V** | uint32 LE |
| **26** | **4** | — | **均衡触发电压差** | **×0.001** | **V** | uint32 LE |
| **30** | **4** | — | **SOC 100% 电压** | **×0.001** | **V** | uint32 LE |
| **34** | **4** | — | **SOC 0% 电压** | **×0.001** | **V** | uint32 LE |
| **38** | **4** | — | **请求充电电压 (RCV)** | **×0.001** | **V** | uint32 LE |
| **42** | **4** | — | **请求浮充电压 (RFV)** | **×0.001** | **V** | uint32 LE |
| **46** | **4** | — | **关机电压 (Power Off)** | **×0.001** | **V** | uint32 LE |
| **50** | **4** | — | **最大充电电流** | **×0.001** | **A** | uint32 LE |
| **54** | **4** | — | **充电过流保护延迟** | **1** | **s** | uint32 LE |
| **58** | **4** | — | **充电过流恢复时间** | **1** | **s** | uint32 LE |
| **62** | **4** | — | **最大放电电流** | **×0.001** | **A** | uint32 LE |
| **66** | **4** | — | **放电过流保护延迟** | **1** | **s** | uint32 LE |
| **70** | **4** | — | **放电过流恢复时间** | **1** | **s** | uint32 LE |
| **74** | **4** | — | **短路保护恢复时间** | **1** | **s** | uint32 LE |
| **78** | **4** | — | **最大均衡电流** | **×0.001** | **A** | uint32 LE |
| **82** | **4** | — | **充电过温保护 (Charge OTP)** | **×0.1** | **°C** | uint32 LE |
| **86** | **4** | — | **充电过温恢复 (Charge OTPR)** | **×0.1** | **°C** | uint32 LE |
| **90** | **4** | — | **放电过温保护 (Discharge OTP)** | **×0.1** | **°C** | uint32 LE |
| **94** | **4** | — | **放电过温恢复 (Discharge OTPR)** | **×0.1** | **°C** | uint32 LE |
| **98** | **4** | — | **充电低温保护 (Charge UTP)** | **×0.1** | **°C** | **int32 LE(有符号)** |
| **102** | **4** | — | **充电低温恢复 (Charge UTPR)** | **×0.1** | **°C** | **int32 LE(有符号)** |
| **106** | **4** | — | **MOS 过温保护** | **×0.1** | **°C** | int32 LE |
| **110** | **4** | — | **MOS 过温恢复** | **×0.1** | **°C** | int32 LE |
| **114** | **4** | `cellCount` | **电芯数量** | **1** | **—** | uint32 LE |
| **118** | **4** | — | **充电开关** | **—** | **0/1** | uint32 LE |
| **122** | **4** | — | **放电开关** | **—** | **0/1** | uint32 LE |
| **126** | **4** | `balanEn` | **均衡开关** | **—** | **0/1** | uint32 LE |
| **130** | **4** | `capBatCell` | **标称电池容量** | **×0.001** | **Ah** | uint32 LE |
| **134** | **4** | — | **短路保护延迟** | **1** | **μs** | uint32 LE |
| **138** | **4** | — | **均衡开始电压** | **×0.001** | **V** | uint32 LE |

#### 24S 专有字段 (偏移 142~253)

| 偏移 | 长度 | 含义 | 系数 | 单位 |
|------|------|------|------|------|
| 142~149 | 8 | 未知/保留 | — | — |
| 158~253 | 96 | 电芯 1~24 引线电阻配置 (每个 4 字节) | ×0.001 | Ω |

### 6.2 JK02_32S Settings 帧扩展字段 (偏移 142~299)

> 32S 协议在偏移 142 后有大量扩展，与 24S 布局完全不同。

| 偏移 | 长度 | 含义 | 系数 | 单位 |
|------|------|------|------|------|
| 142~269 | 128 | 电芯 1~32 引线电阻配置 (每个 4 字节) | ×0.001 | Ω |
| 270 | 1 | 设备地址 | 1 | — |
| 274 | 1 | 预充时间 | 1 | s |
| **282** | **2** | **新控制位掩码** (uint16 LE) ⭐ | — | — |
| 284 | 1 | 加热启动温度 | 1 | °C (int8 有符号) |
| 285 | 1 | 加热停止温度 | 1 | °C (int8 有符号) |
| 286 | 1 | Smart Sleep 时间 | 1 | h |
| 287 | 1 | 数据字段使能控制 | — | — |

#### 32S 新控制位掩码 (偏移 282~283) ⭐

此 2 字节掩码控制多个 32S 专有功能的开关状态：

| Bit | 偏移 | 含义 | 对应写入寄存器 |
|-----|------|------|----------|
| bit 0 | 282 | 加热开关 (Heating) | `0x27` |
| bit 1 | 282 | 禁用温度传感器 (Disable Temp Sensors) | `0x28` |
| bit 2 | 282 | GPS 心跳 (GPS Heartbeat) | — |
| bit 3 | 282 | 端口切换 (1=RS485, 0=CAN) | — |
| bit 4 | 282 | 常亮显示 (Display Always On) | `0x2B` |
| bit 5 | 282 | 特殊充电器模式 (Special Charger) | — |
| bit 6 | 282 | 智能睡眠 (Smart Sleep) | `0x2D` |
| bit 7 | 282 | 禁用 PCL 模块 (Disable PCL) | `0x2E` |
| bit 8 | 283 | 定时存储数据 (Timed Stored Data) | `0x2F` |
| bit 9 | 283 | 浮充模式 (Charging Float Mode) | `0x30` |
| bit 10~15 | 283 | 保留 | — |

### 6.3 JK04 Settings 帧字段

> JK04（旧版协议）的 Settings 帧结构与 JK02 系列差异显著。电压/电阻使用 IEEE 754 float32 格式。

| 偏移 | 长度 | 含义 | 数据格式 |
|------|------|------|----------|
| 6 | 4 | 未知 (float) | IEEE 754 float32 |
| 34 | 4 | 电芯数量 | uint32 LE |
| 38 | 4 | 关机电压 | IEEE 754 float32 (V) |
| 74 | 4 | 未知 (float) | IEEE 754 float32 |
| 98 | 4 | 均衡开始电压 | IEEE 754 float32 (V) |
| 102 | 4 | 未知 (float) | IEEE 754 float32 |
| 106 | 4 | 均衡触发电压差 | IEEE 754 float32 (V) |
| 110 | 4 | 最大均衡电流 | IEEE 754 float32 (A) |
| 114 | 4 | 均衡开关 | uint32 LE (0/1) |

---

## 7. BLE 设备发现与过滤

> 源码: `com.smartsoft.ble.Bluetooth.java`

APP 采用**两层过滤**机制识别 JK-BMS 设备：Android 系统级 ScanFilter + 应用层软件过滤。

### 7.1 系统级 ScanFilter

```java
// buildScanFilters() — 无任何条件，接收所有 BLE 广播
new ScanFilter.Builder().build();
```

扫描参数:
- `ScanMode = SCAN_MODE_LOW_LATENCY` (2) — 最高速率扫描
- `CallbackType = CALLBACK_TYPE_FIRST_MATCH` (1) — 发现即回调

**系统层不做任何过滤，所有过滤在应用回调中完成。**

### 7.2 应用层设备类型判定 `deviceType()`

对每条广播的原始 Scan Record 字节数组进行判定：

```java
public BleType deviceType(byte[] bArr) {
    if (bArr.length != 62)              return Unknown;   // 条件1: 长度必须 62
    if (bArr[5] != 0xE0)               return Unknown;   // 条件2: AD Type
    if (bArr[6] != 0xFF)               return Unknown;   // 条件3: Manufacturer Specific
    if (bArr[13] != devVid)             return Unknown;   // 条件4: 厂商ID == 0x88
    byte pid = bArr[14];                                  // 条件5: 产品ID 分类
    return (pid==0x5F || pid==0xB1 || pid==0xB2 || pid==0xC4 || pid==0xC5)
        ? JDY_Other : JDY;
}
```

| 条件 | Scan Record 偏移 | 要求值 | 含义 |
|------|-----------------|--------|------|
| 广播长度 | `length` | `== 62` | 固定长度广播包 |
| AD Type | `[5]` | `0xE0` | 自定义广播类型标识 |
| AD Type | `[6]` | `0xFF` | Manufacturer Specific Data |
| Vendor ID | `[13]` | `0x88` | JK 厂商标识（`devVid = -120`） |
| Product ID | `[14]` | 见下表 | 设备子类型 |

**Product ID 分类表:**

| `bArr[14]` (hex) | signed byte | 返回类型 | 推测设备 |
|-------------------|-------------|----------|---------|
| `0x5F` | -91 | `JDY_Other` | 非标准JK蓝牙模块 |
| `0xB1` | -79 | `JDY_Other` | — |
| `0xB2` | -78 | `JDY_Other` | — |
| `0xC4` | -60 | `JDY_Other` | — |
| `0xC5` | -59 | `JDY_Other` | — |
| 其他 | — | `JDY` | 标准 JK-BMS 设备 |

设备类型枚举:
```java
enum BleType { Unknown, JDY, JDY_Other }
```

### 7.3 Fallback — Manufacturer Data ID 匹配

若 `deviceType()` 返回 `Unknown`（长度≠62 或字段不匹配），回调函数会检查 **Manufacturer Specific Data** 的前 2 字节 hex 是否在已知设备 ID 列表中：

```java
SparseArray<byte[]> mfgData = scanRecord.getManufacturerSpecificData();
if (mfgData.size() != 0) {
    String hex = bytesToHex(mfgData.valueAt(0)).substring(0, 4);
    if (isValidDevice(hex))   // 匹配前4个hex字符（即前2字节）
        addDevice(..., JDY_Other, ...);
}
```

**已知设备 ID 列表 (`deviceIds`):**

| ID前缀 (2字节hex) | 完整注册值 | 推测含义 |
|-------------------|-----------|---------|
| `F000` | `F000`, `F00088A03CA54AE421E0` | 旧款 JK-BMS |
| `650B` | `650B`, `650B88A03CA539DB5BEE` | — |
| `88A0` | `88A03CA539DB5BEE` | JK 蓝牙模块 MAC 前缀 |
| `C1EA` | `C1EA`, `C1EA88A03CA55080C7CF` | — |
| `0B2D` | `0B2D`, `0B2D88A0191229110E19` | — |
| `4458` | `4458`, `44585A4E424C45` | ASCII "DX" + "ZNBLE" |
| `4A4B` | `4A4B`, `4A4B0001` | **ASCII "JK"** — 最常见标识 |

### 7.4 完整过滤流程

```
收到 BLE 广播
  │
  ├─ deviceName == null ?  (仅新版 ScanCallback)
  │    └─ YES → 丢弃 ❌
  │
  ├─ 长度==62 且 [5]==0xE0 且 [6]==0xFF 且 [13]==0x88 ?
  │    ├─ YES → [14] 判定产品类型 → JDY 或 JDY_Other ✅
  │    └─ NO  ↓
  │
  ├─ Manufacturer Data 前2字节 hex ∈ deviceIds ?
  │    ├─ YES → JDY_Other ✅
  │    └─ NO  → 丢弃 ❌
  │
  └─ addDevice() → 通知 C++ 层 (NativeClass.deviceAdded)
```

> **核心标识**: 广播 offset[13] 的厂商字节 `0x88` 以及 Manufacturer Specific Data 中的 `4A4B`（ASCII "JK"）前缀。

### 7.5 BLE 广播名称 (Local Name)

设备发现阶段 APP 列表中显示的名称是 BLE 广播中的 **Local Name** (AD Type `0x08`/`0x09`)。

名称获取优先级：
1. `JScanRecord.getDeviceName()` — 从 Scan Record AD 结构解析
2. `BluetoothDevice.getName()` — Android 系统缓存（fallback）

**新版 ScanCallback 中，`deviceName == null` 的广播会被直接丢弃**，即设备必须在广播中包含名称字段。

这个 BLE 广播名 = BMS 设备内部存储的 **Device Name**（可通过 APP 修改），默认出厂值与型号相同（如 `JK-B2A24S15P`）。用户可以在连接后通过 APP 改写此名称（如改为 "我的电池"），之后蓝牙发现显示的就是修改后的名字。

### 7.6 设备信息帧 (Type 0x03)

连接后发送命令 `0x97`，BMS 会先返回设备信息帧 (Type 0x03)，包含设备标识和**用户自定义数据**：

| 偏移 | 长度 | 字段名 | 含义 | 示例值 |
|------|------|--------|------|--------|
| 0 | 4 | — | 帧头 | `55 AA EB 90` |
| 4 | 1 | — | 帧类型 | `0x03` |
| 5 | 1 | — | 帧计数器 | — |
| 6 | 16 | Vendor ID | **硬件型号**（固定，不可修改） | `JK-B2A24S15P` |
| 22 | 8 | HW Version | 硬件版本 | `10.XW` |
| 30 | 8 | SW Version | 固件版本 | `10.07`, `14.20` |
| 38 | 4 | Uptime | 累计运行时长 (uint32 LE, 秒) | `36867600` s |
| 42 | 4 | Power On Count | 开机次数 (uint32 LE) | `19` |
| **46** | **16** | **Device Name** | **⭐ 用户自定义名称**（可读写） | `BMS`, `JK-B2A24S15P` |
| **62** | **16** | **Device Passcode** | **设备密码** | `1234` |
| 78 | 8 | Mfg Date | 生产日期 | `220407` (2022-04-07) |
| 86 | 11 | Serial Number | 序列号 | `2021602096` |
| 97 | 5 | Passcode | 密码（旧） | `0000` |
| **102** | **16** | **User Data** | **⭐ 用户自定义数据** | `Input Userdata` |
| **118** | **16** | **Setup Passcode** | **设置密码** | `123457` |

#### 32S 协议扩展字段 (offset 134~299)

> 仅 JK02_32S 协议版本包含以下扩展字段。JK04 和 JK02_24S 在 offset 134 之后全为零填充。

| 偏移 | 长度 | 字段名 | 含义 | 备注 |
|------|------|--------|------|------|
| 134 | 16 | User Data 2 | 第二用户数据区 | ASCII 字符串，如 `Input Userdata` |
| 150 | 4 | Unknown150 | 未知 | 示例: `0xFE 0xFF 0xFF 0xFF` |
| 154 | 8 | Unknown154 | 未知 | 示例: `0xAF 0xE9 0x01 0x02 ...` |
| 162 | 4 | Unknown162 | 未知 | 示例: `0x90 0x1F 0x00 0x00` |
| 166 | 2 | Unknown166 | 未知 | |
| 168 | 16 | Unknown168 | 未知 | 含 `0xC0 0xD8 0xE7 0xFE ...` |
| **184** | **1** | **UART1M Protocol** | **UART1 协议编号** | 用于 RS485 通信 |
| **185** | **1** | **CAN Protocol** | **CAN 协议编号** | 用于 CAN 总线通信 |
| 186 | 32 | Unknown186~217 | 未知/保留 | 含协议库相关数据 |
| **218** | **1** | **UART2M Protocol** | **UART2 协议编号** | 第二 UART 通道 |
| 219 | 15 | Unknown219~233 | UART2 协议使能及相关数据 | |
| **234** | **1** | **LCD Buzzer Trigger** | **蜂鸣器触发类型** | |
| **235** | **1** | **DRY1 Trigger** | **干触点 1 触发类型** | 值含义参见 esphome 源码 |
| **236** | **1** | **DRY2 Trigger** | **干触点 2 触发类型** | |
| **237** | **1** | **UART Protocol Lib Ver** | **UART 协议库版本** | |
| 238 | 4 | LCD Buzzer Trigger Value | 蜂鸣器触发值 | uint32 LE |
| 242 | 4 | LCD Buzzer Release Value | 蜂鸣器释放值 | uint32 LE |
| 246 | 4 | DRY1 Trigger Value | 干触点 1 触发值 | uint32 LE |
| 250 | 4 | DRY1 Release Value | 干触点 1 释放值 | uint32 LE |
| 254 | 4 | DRY2 Trigger Value | 干触点 2 触发值 | uint32 LE |
| 258 | 4 | DRY2 Release Value | 干触点 2 释放值 | uint32 LE |
| **262** | **4** | **Data Stored Period** | **数据存储周期** | uint32 LE，单位待确认 |
| **266** | **1** | **RCV Time** | **请求充电电压时间** | ×0.1 h |
| **267** | **1** | **RFV Time** | **请求浮充电压时间** | ×0.1 h |
| **268** | **1** | **CAN Protocol Lib Ver** | **CAN 协议库版本** | |
| 269 | 30 | Reserved | 保留/零填充 | |
| 299 | 1 | CRC | CRC 校验 | sum(bytes[0..298]) & 0xFF |

> **DRY 触点说明**: 32S 协议支持两个干触点（DRY1、DRY2），可配置不同的触发条件（如 SOC 阈值、电压阈值等）。Trigger 类型字段定义触发条件类别，Trigger/Release Value 定义具体阈值。
>
> **RCV/RFV 时间**: 用于充电管理。RCV (Request Charge Voltage) 和 RFV (Request Float Voltage) 时间控制不同充电阶段的持续时长，精度 0.1 小时。

#### Vendor ID vs Device Name 的区别

| 字段 | 偏移 | 性质 | 示例 |
|------|------|------|------|
| Vendor ID (offset 6) | 6 | **只读** — 硬件烧录的型号标识 | `JK-B2A16S` |
| Device Name (offset 46) | 46 | **可读写** — 用户自定义名称 | `BMS`、`我的电池` |

- 出厂时 Device Name 默认与 Vendor ID 相同
- 用户通过 APP 修改后，BLE 广播名和 Device Name 同步更新
- `loadProtoInfos()` 使用 **Vendor ID** (而非 Device Name) 查询设备型号数据库，因此改名不影响协议解析

#### 设备信息帧示例解码 (JK04)

```
55 AA EB 90 03 E7                      ← 帧头 + Type 0x03
4A 4B 2D 42 32 41 31 36 53 00 ...      ← Vendor ID: "JK-B2A16S"
33 2E 30 00 ...                        ← HW Version: "3.0"
33 2E 33 2E 30 00 ...                  ← SW Version: "3.3.0"
42 4D 53 00 ...                        ← Device Name: "BMS" (用户自定义!)
31 32 33 34 00 ...                     ← Passcode: "1234"
```

### 7.7 设备名称与协议族映射

设备被添加后，C++ 层 `TransferPrivate::loadProtoInfos()` 会根据 **Vendor ID**（而非 BLE 广播名或 Device Name）查询内置的 **设备型号数据库** (`devices.json`)，确定：
- 该设备属于哪个**协议族**（决定帧解析方式）
- 该设备的**电芯数量**（决定数据偏移量）

#### 设备型号数据库 (7 协议族, 174 个型号)

> 提取自 `libjkbms.so` Qt 编译资源

| 协议族 | 代表型号 | 电芯数范围 | 说明 |
|--------|---------|-----------|------|
| `JK-B1A24S` | JK-B1A24S, JK-B2A24S, JK-B5A24S, JK-B10A24S | 16~24S | 标准24S系列 |
| `JK-B1A24S-P` | JK-B1A24S-P, JK-BD6A20S10P, JK-BD6A24S15P | 8~24S | 带并联(P)的增强系列 |
| `JK-B1A32S-P` | JK-B2A25S60P, JK-B5A25S60P | 25S | 32S协议扩展系列 |
| `JK-DZ08-B1A24S` | JK-DZ08-B1A24S, JK-DZ11-B2A24S | 24S | DZ系列（带均衡器） |
| `JK-B1A24S-PLW` | JK-BD6A20S15P, JK-BD6A24S12P | 20~24S | 低功耗系列 |
| `JK-B1A24S-PSR` | JK-BD6A13SSR | 13S | 特殊系列 |
| `JK-BXAXS-XP` | JK_B1A8S20P, JK_B2A24S15P, JK_F8A32S等 | 4~32S | **通用32S系列** (111个型号) |

#### 常见 Vendor ID 命名模式

格式: `JK-B{电流}A{电芯}S` 或 `JK_B{电流}A{电芯}S{并联}P`

```
JK-B2A24S        → 2A 保护板, 24串, 标准系列
JK-B5A24S        → 5A 保护板, 24串
JK-BD6A20S10P    → 6A 保护板, 20串, 10并, P系列
JK_B2A24S15P     → 2A 保护板, 24串, 15并, 通用32S协议
JK-DZ11-B2A24S   → DZ11均衡器, 2A, 24串
```

#### OEM / 贴牌设备

非 `JK-` 前缀的设备也在数据库中注册（归入对应协议族）：

| OEM名称 | 协议族 | 电芯数 |
|---------|-------|--------|
| `PXZK-01`, `PXZK-02` | JK-B1A24S | 24S |
| `HW-B2A` | JK-B1A24S | 24S |
| `SQ-BD6A20S6P` ~ `SQ-B1A24S15P` | JK-B1A24S-P | 20~24S |

---

## 8. BLE 协议密码机制

JK-BMS BLE 协议中存在 **三种密码**，均以明文 ASCII 字符串存储在设备信息帧 (Type 0x03) 中，无任何加密保护。

### 8.1 密码字段在设备信息帧中的位置

| 字段 | 帧内偏移 | 长度 | QML绑定名 | 默认值 | 说明 |
|------|----------|------|-----------|--------|------|
| Device Passcode (蓝牙连接密码) | 62 | 16 bytes | `bluetoothPwd` | `1234` | BLE 连接后的登录密码 |
| Passcode (短密码) | 97 | 5 bytes | — | `0000` | 用途不明，可能为旧版兼容 |
| Setup Passcode (参数设置密码) | 118 | 16 bytes | `settingPassword` | `123456` | 修改 BMS 参数的密码 |

示例原始数据 (JK02_32S):
```
偏移 62: 31 32 33 34 00 00 ... → "1234"     (Device Passcode)
偏移 97: 30 30 30 30 00       → "0000"     (Passcode)
偏移 118: 31 32 33 34 35 37 00 ... → "123457" (Setup Passcode)
```

### 8.2 密码认证流程

#### 整体时序

```
App                          BMS设备
 |                              |
 |--- BLE Connect ------------->|
 |--- GATT Subscribe ---------->|  (通知 0xFFE1)
 |--- Write(0x97, 0x00) ------->|  请求设备信息
 |<-- Type 0x03 Response -------|  包含明文密码
 |                              |
 |  [App本地验证密码]            |
 |  ✓ → landed=true (进入主界面) |
 |  ✗ → 弹出登录对话框           |
 |                              |
 |--- Write(0x96, 0x00) ------->|  请求电芯数据 (无需密码)
 |<-- Type 0x02 Response -------|
```

**关键发现：BMS 固件本身不进行任何认证。** 密码验证完全在 App 端进行，BMS 设备对所有 BLE 连接的客户端无条件地返回包含明文密码的完整设备信息帧。

#### 蓝牙连接密码 (Device Passcode) 验证流程

```javascript
// 来自 resource_72_qml.qml — sendDevInfoRequest() 回调
function onDeviceInfoReceived(success) {
    // 1. 量产版(isLIANGCHAN)检测: 跳过密码验证
    if (window.isLIANGCHAN) {
        JMain.landed = true  // 直接进入
        return
    }

    // 2. Beta版特殊检查: 密码必须为出厂默认值
    if (JMain.betaVersion && window.isLIANGCHAN) {
        if (d03.bluetoothPwd.text !== '1234'
            || d03.settingPassword.text !== '123456') {
            // 断开连接: "Password is not matched!"
            return
        }
    }

    // 3. 需要登录的版本(isLoginNeeded):
    if (window.isLoginNeeded) {
        var savedPwd = JMain.bluetoothPwd  // 从本地存储读取上次密码
        if (savedPwd.length > 0 && savedPwd === d03.bluetoothPwd.text) {
            // 本地缓存的密码与设备密码匹配 → 自动登录
            JMain.landed = true
        } else {
            // 密码不匹配或首次连接 → 弹出登录对话框
            loginDialog.open()
        }
    }
}
```

**验证逻辑总结:**

| App 版本标志 | 密码行为 |
|-------------|---------|
| `isLIANGCHAN` (量产版) | 跳过密码验证，直接进入 |
| `betaVersion` + `isLIANGCHAN` | 检查密码是否为出厂默认值 (`1234` / `123456`) |
| `isLoginNeeded` (需登录版) | 比对本地缓存密码与设备密码，不匹配则弹出登录框 |
| 其他 | 直接进入，无需密码验证 |

#### 参数设置密码 (Setup Passcode) 验证流程

参数设置密码控制 Settings 页面中 BMS 参数的修改权限：

```
┌─────────────────┐         ┌──────────────────┐
│  Settings 页面   │         │                  │
│  settingsEnabled │──false──│ "Verify PWD."    │
│  = false (锁定)  │         │ verifySetDialog  │
│                  │         │ → 输入密码对比     │
│                  │         │   settingPassword │
│  settingsEnabled │──true───│ "Modify PWD."    │
│  = true  (解锁)  │         │ settingsPwdDialog │
│                  │         │ → 修改设备密码     │
└─────────────────┘         └──────────────────┘
```

- **锁定状态** (🔒): 用户点击 "Verify PWD."，弹出 `verifySetDialog`，输入密码与设备返回的 `settingPassword` 对比
- **解锁状态** (🔓): 参数可修改；点击 "Modify PWD." 可修改设备上的设置密码

### 8.3 写入命令无认证

写入命令帧（如修改参数、开关充放电等）不包含任何密码字段：

```
写入帧格式 (20 bytes):
AA 55 90 EB [addr] [len] [value LE 4B] [padding 9B] [CRC]

示例 - enableCharge:
AA 55 90 EB [reg] 04 [val 4B] [random 9B] [CRC]
```

帧内仅有：头部(4B) + 寄存器地址(1B) + 长度(1B) + 值(最多8B) + 填充(随机/零) + CRC(1B)。

**无密码字段、无认证令牌、无会话密钥。** 所有对 BMS 的写入操作（包括开关充放电 MOS、修改过压/欠压阈值、修改密码本身等）均可由任何已连接的 BLE 客户端直接执行。

### 8.4 密码修改

密码存储在 Type 0x03 帧对应的设备内部存储区，可通过写入命令直接修改：

| 操作 | 寄存器地址 | 写入内容 |
|------|-----------|---------|
| 修改蓝牙连接密码 | 对应 `bluetoothPwd` 的寄存器 | 新密码 ASCII 字符串 |
| 修改参数设置密码 | 对应 `settingPassword` 的寄存器 | 新密码 ASCII 字符串 |

App 中修改密码的 UI 按钮：
- Settings 页面 → 解锁后显示 🔓 "Modify PWD." → 打开 `settingsPwdDialog`
- 对话框输入新密码后，通过 `Transfer.sendCommandImm()` 写入 BMS

### 8.5 安全性分析

| 安全维度 | 现状 | 风险等级 |
|---------|------|---------|
| 密码传输 | 明文 ASCII，无加密 | ⚠️ 高 |
| 密码存储 | 设备端明文存储在 Type 0x03 帧 | ⚠️ 高 |
| 认证方式 | 仅 App 端本地验证，固件无认证 | 🔴 严重 |
| 写入授权 | 写入命令无需密码，任何客户端可执行 | 🔴 严重 |
| BLE 配对 | 无 BLE Pairing/Bonding (GATT AUTH_REQ_NONE) | ⚠️ 高 |
| 重放攻击 | 填充字段为随机值但 CRC 仅为简单字节和 | ⚠️ 高 |
| 密码复杂度 | 默认 `1234` / `123456`，用户极少修改 | ⚠️ 中 |

**结论：** JK-BMS BLE 协议的密码机制是一个 **纯客户端的 UI 门禁**，而非真正的通信层安全认证。任何能够建立 BLE 连接的设备（如 ESP32、nRF52、手机上的通用 BLE 调试工具等）都可以：

1. 读取设备信息帧获取所有明文密码
2. 直接发送写入命令修改任何参数
3. 开关充放电 MOS 管
4. 修改密码本身（锁定合法用户）

esphome-jk-bms 项目即为一个不需要任何密码即可完全控制 BMS 的开源实现。

### 8.6 经销商 ID 验证 (Agency ID)

除密码外，App 中还有一个 **经销商 ID** (`agencyId`) 验证机制（应用于通用协议 `JK-BXAXS-XP`）：

```javascript
// verifyAgencyId() — resource_72_qml.qml
function verifyAgencyId() {
    if (window.isPOWERMGR) return true  // 关机APP不验证
    if (JMain.betaVersion) return true  // 内测版不验证
    if (!window.jAgencyId) return true  // 数据无效，跳过
    if (window.deviceName !== 'JK-BXAXS-XP') return true  // 仅通用协议

    var agencyId = window.jAgencyId.orgData
    if (window.isPOWERLI) return true   // POWERLI版本跳过

    // 检查设备的 agencyId 是否等于 App 内的 JMain.agencyId
    if (agencyId === JMain.agencyId) return true

    // 匹配失败 → 断开连接: "Device is not supported! (Contact Agent)"
    return false
}
```

此机制用于限制特定经销商的 App 只能管理该经销商出售的 BMS 设备，但同样是纯 App 端检查，可通过使用通用版 App 或第三方工具绕过。

---

## 9. BLE连接信息

| 参数 | 值 |
|------|----|
| BLE Service UUID | `0xFFE0` |
| BLE Characteristic (写入) | `0xFFE1` (handle 0x03) |
| BLE Characteristic (通知) | `0xFFE1` (handle 0x05 旧模块 / 0x03 新模块) |
| MTU | 188 |
| 最大包大小 | 185 bytes |
| 包间延时 | 20ms |
| 帧总长度 | 300 bytes |
| CRC | 字节[0..298] 简单求和，取低 8 位 |
| 设备识别前缀 | Manufacturer Data: `4A4B` (JK), `F000`, `650B`, `C1EA`, `0B2D`, `4458` |

### 9.1 新旧 BLE 模块的 Handle 差异

> 来源: esphome-jk-bms `jk_bms_ble.cpp` — `ESP_GATTC_SEARCH_CMPL_EVT` 处理

JK-BMS 使用过至少两代 BLE 模块，其 GATT Characteristic handle 布局不同：

| BLE 模块 | MAC 前缀 | 写入 Handle | 通知 Handle | 说明 |
|---------|---------|---------|---------|------|
| **旧模块** | `C8:47:8C:XX` | `0x03` (FFE1, properties: 0x1c) | `0x05` (FFE1, properties: 0x12) | 两个不同的 FFE1 characteristic |
| **新模块** | `20:21:11:XX` | `0x03` (FFE1, properties: 0x0c) | `0x05` (FFE1, properties: 0x12, descriptor 0x2902 at 0x06) | 写入和通知分离 |

esphome 的处理逻辑：
```cpp
this->char_handle_ = chr->handle;  // 写入 handle
this->notify_handle_ = (chr->handle == 0x03) ? 0x05 : chr->handle;  // 通知 handle
```

**对于 iOS CoreBluetooth**: 不直接操作 handle，而是通过 `CBCharacteristic` 对象区分。需要注意同一 UUID `0xFFE1` 下可能存在**两个** characteristic 实例——一个支持 Write，一个支持 Notify。应使用 `characteristic.properties` 判断：
- 写入目标: 具有 `.write` 或 `.writeWithoutResponse` 属性的 characteristic
- 通知目标: 具有 `.notify` 属性的 characteristic

旧模块的完整 GATT 服务发现结果：
```
Service UUID: 0xFFE0 (start: 0x0E, end: 0x13)
  characteristic 0xFFE2, handle 0x10, properties 0x04 (Write Without Response)
  characteristic 0xFFE1, handle 0x12, properties 0x1c (Write | Notify | ...)
Service UUID: 0x180A (Device Information)
Service UUID: 0x180F (Battery)
Service UUID: F000FFC0-0451-4000-B000-000000000000 (TI OAD)
```

新模块的完整 GATT 服务发现结果：
```
Service UUID: 0xFFE0 (start: 0x01, end: 0xFFFF)
  characteristic 0xFFE1, handle 0x03, properties 0x0c (Write | Write Without Response)
  characteristic 0xFFE1, handle 0x05, properties 0x12 (Notify)
    descriptor 0x2902, handle 0x06 (CCCD)
```

### 9.2 BLE 通知分片组装机制 ⭐

> 来源: esphome-jk-bms `JkBmsBle::assemble()`

BMS 响应帧固定为 **300 字节**，但 BLE 单次通知最大只能传输 **MTU-3 字节**（通常 185 字节）。因此一个完整帧会被拆分为**多个 BLE notification 包**（通常 2 个：~185 + ~115 字节），客户端必须实现帧重组逻辑。

#### 分片组装算法

```
初始化: frame_buffer = []

收到 BLE Notification(data, length):
  1. 如果 data 以 [0x55, 0xAA, 0xEB, 0x90] 开头:
       清空 frame_buffer (新帧开始)
  2. 将 data 追加到 frame_buffer
  3. 如果 frame_buffer.size >= 300:
       计算 CRC = sum(frame_buffer[0..298]) & 0xFF
       如果 CRC == frame_buffer[299]:
         解析完整帧 → decode(frame_buffer)
       否则:
         丢弃帧 (CRC 校验失败)
       清空 frame_buffer
  4. 如果 frame_buffer.size > 384+16 (异常过大):
       丢弃 frame_buffer (防止内存溢出)
```

#### 关键实现要点

1. **帧边界识别**: 使用头部 `55 AA EB 90` 作为帧起始标识。每次收到以此开头的包时，清空缓冲区开始新帧
2. **CRC 固定在第 300 字节**: 即使帧数据区可能更长（32S 可达 320+ 字节），CRC 始终在 `frame_buffer[299]`，校验范围为 `[0..298]`
3. **丢包处理**: 如帧不完整（收到新帧头时上一帧未满 300 字节），旧数据被自动丢弃
4. **缓冲区溢出保护**: 如果缓冲区超过 400 字节仍未组装成功，直接丢弃

#### Swift 实现参考

```swift
class BMSFrameAssembler {
    private var frameBuffer = Data()
    private let frameHeader: [UInt8] = [0x55, 0xAA, 0xEB, 0x90]
    private let minFrameSize = 300
    private let maxBufferSize = 400
    
    func assemble(_ data: Data) -> Data? {
        // 检测帧头 → 开始新帧
        if data.count >= 4 && data[0] == 0x55 && data[1] == 0xAA 
           && data[2] == 0xEB && data[3] == 0x90 {
            frameBuffer.removeAll()
        }
        
        frameBuffer.append(data)
        
        // 防溢出
        if frameBuffer.count > maxBufferSize {
            frameBuffer.removeAll()
            return nil
        }
        
        // 检查是否已收到完整帧
        if frameBuffer.count >= minFrameSize {
            let computedCRC = frameBuffer[0..<299].reduce(0, &+)  // UInt8 溢出自动取低8位
            let remoteCRC = frameBuffer[299]
            if computedCRC == remoteCRC {
                let completeFrame = Data(frameBuffer[0..<minFrameSize])
                frameBuffer.removeAll()
                return completeFrame
            } else {
                frameBuffer.removeAll()
                return nil
            }
        }
        return nil
    }
}
```

---

## 10. 数据来源说明

本分析基于以下多重来源交叉验证：

1. **APK反编译** (`jadx`): Java BLE层分析 - `Bluetooth.java`, `BleService.java`, `NativeClass.java`
2. **Native库反编译** (`Ghidra`): `libjkbms_armeabi-v7a.so` 中的 `Transfer::parseData`, `Transfer::sendCommand`, `Transfer::checkAndSend` 函数
3. **Qt资源提取**: QML页面中的 `JSearchObject` 数据绑定定义，`utility.js` 中的字段映射机制
4. **开源社区**: [esphome-jk-bms](https://github.com/syssi/esphome-jk-bms) 项目的完整字节级协议解析

---

## 11. 编程指南 — 从 BLE 连接到持续接收电池数据

> 本章以**伪代码 + Swift 参考实现**的形式，描述一个完整的 JK-BMS BLE 客户端从扫描到持续接收并解析电池数据的全流程。适用于 iOS (CoreBluetooth) / macOS / Android (BLE GATT) 等平台。

### 11.1 总体流程时序图

```
┌──────────┐            ┌──────────┐            ┌──────────┐
│  App     │            │ BLE Stack│            │  JK-BMS  │
└────┬─────┘            └────┬─────┘            └────┬─────┘
     │  1. scanForPeripherals()                      │
     │─────────────────────►│                        │
     │                      │   BLE Advertising      │
     │  2. didDiscover      │◄───────────────────────│
     │  (name含"JK")        │                        │
     │◄─────────────────────│                        │
     │                                               │
     │  3. connect(peripheral)                       │
     │─────────────────────►│                        │
     │                      │   Connection Established│
     │  4. didConnect        │◄───────────────────────│
     │◄─────────────────────│                        │
     │                                               │
     │  5. discoverServices([0xFFE0])                │
     │─────────────────────►│                        │
     │  6. didDiscoverServices                       │
     │◄─────────────────────│                        │
     │                                               │
     │  7. discoverCharacteristics([0xFFE1])         │
     │─────────────────────►│                        │
     │  8. didDiscoverCharacteristics                │
     │◄─────────────────────│                        │
     │                                               │
     │  9. setNotifyValue(true, for: 0xFFE1)         │
     │─────────────────────►│   Subscribe Notify     │
     │                      │───────────────────────►│
     │                                               │
     │  10. writeValue(cmd_0x97, for: writeChar)     │
     │─────────────────────►│   AA 55 90 EB 97 00.. │
     │                      │───────────────────────►│
     │                                               │
     │                      │   Notification: 帧片段1 │
     │  11. didUpdateValue   │◄───────────────────────│
     │  (20 bytes)          │   Notification: 帧片段2 │
     │◄─────────────────────│◄───────────────────────│
     │  ... 重复直到 300 bytes  │   ...                 │
     │                      │                        │
     │  12. 组装完整帧 → 解析   │                        │
     │  (Type 0x03 设备信息)   │                        │
     │                                               │
     │                      │   Type 0x01 Settings   │
     │  13. 自动周期推送       │◄───────────────────────│
     │◄─────────────────────│   Type 0x02 Cell Info  │
     │                      │◄───────────────────────│
     │  14. 每帧组装+解析      │   (每1~2秒一帧)         │
     └──────────────────────┘───────────────────────►│
```

### 11.2 Step-by-Step 伪代码

#### Step 1: BLE 扫描与过滤

```pseudocode
// 扫描 JK-BMS 设备
scanner.scanForPeripherals(withServices: [UUID(0xFFE0)])

// 过滤条件 (满足任一即可):
//   1. 广播服务包含 UUID 0xFFE0
//   2. 设备名以 "JK-" 或 "JK_" 开头
//   3. Manufacturer Data ID 为 0x0001 (JK专用)

ON didDiscover(peripheral, advertisementData, rssi):
    name = advertisementData.localName
    if name.hasPrefix("JK-") or name.hasPrefix("JK_"):
        // 确认是 JK-BMS 设备
        foundDevices.add(peripheral)
        // 可选: 从 Manufacturer Data 读取设备型号
```

#### Step 2: 建立连接 + 服务发现

```pseudocode
centralManager.connect(peripheral)

ON didConnect(peripheral):
    // 只需发现 0xFFE0 服务
    peripheral.discoverServices([UUID(0xFFE0)])

ON didDiscoverServices(peripheral):
    service = peripheral.services.find(uuid == 0xFFE0)
    // 发现该服务下的所有特征值
    peripheral.discoverCharacteristics([UUID(0xFFE1)], for: service)

ON didDiscoverCharacteristics(service):
    for char in service.characteristics:
        if char.uuid == UUID(0xFFE1):
            if char.properties.contains(.notify):
                notifyChar = char
            if char.properties.contains(.write) or char.properties.contains(.writeWithoutResponse):
                writeChar = char

    // ⚠️ 关键: 新旧 BLE 模块的 handle 不同!
    // 旧模块 (C8:47:8C:xx): notifyHandle=0x12, writeHandle=0x10 (两个不同的 0xFFE1/0xFFE2)
    // 新模块 (20:21:11:xx): notifyHandle=0x05, writeHandle=0x03 (两个相同 UUID 的 0xFFE1)
    //
    // esphome 的处理方式:
    //   notify_handle = (char.handle == 0x03) ? 0x05 : char.handle
    //
    // iOS CoreBluetooth 的处理方式:
    //   遍历所有 characteristics, 对含 .notify 属性的那个订阅, 用含 .write 属性的那个写入
```

#### Step 3: 订阅通知 + 发送触发命令

```pseudocode
// 订阅 BLE 通知
peripheral.setNotifyValue(true, for: notifyChar)

ON didUpdateNotificationState(char, error):
    if error == nil:
        // 订阅成功, 发送设备信息请求命令
        cmd = buildCommand(0x97, value: 0x00000000, length: 0x00)
        peripheral.writeValue(cmd, for: writeChar, type: .withoutResponse)

// 构造20字节写入命令帧
FUNCTION buildCommand(address: UInt8, value: UInt32, length: UInt8) -> Data:
    frame = [0xAA, 0x55, 0x90, 0xEB,   // 帧头 (注意与接收帧 55 AA EB 90 不同!)
             address,                    // 命令码 (0x96=请求电芯数据, 0x97=请求设备信息)
             length,                     // 值的字节长度
             value & 0xFF,               // V0
             (value >> 8) & 0xFF,        // V1
             (value >> 16) & 0xFF,       // V2
             (value >> 24) & 0xFF,       // V3
             0x00, 0x00, 0x00, 0x00,     // 保留
             0x00, 0x00, 0x00, 0x00,     // 保留
             0x00,                       // 保留
             0x00]                       // CRC 占位
    frame[19] = sum(frame[0..18]) & 0xFF  // CRC
    return Data(frame)
```

> **注意**: 写入帧头是 `AA 55 90 EB`，而接收帧头是 `55 AA EB 90`——**字节顺序相反**！

#### Step 4: 接收通知 + 帧组装

```pseudocode
// BLE 每次通知最大约 20 bytes (MTU=23, 减去3字节ATT头)
// 一帧 300 bytes 需要 15~16 个通知片段组装

frameBuffer = ByteArray()
MAX_FRAME_SIZE = 400   // 容错上限 (384+16)
EXPECTED_SIZE = 300    // 标准帧大小

ON didUpdateValue(char, error):
    data = char.value
    
    // 检测帧头 → 新帧开始, 丢弃之前的残余数据
    if data.length >= 4 AND data[0..3] == [0x55, 0xAA, 0xEB, 0x90]:
        frameBuffer.clear()
    
    // 追加数据到缓冲区
    frameBuffer.append(data)
    
    // 防止异常累积
    if frameBuffer.length > MAX_FRAME_SIZE:
        frameBuffer.clear()
        return
    
    // 检查是否达到最小帧长度
    if frameBuffer.length >= EXPECTED_SIZE:
        // CRC 校验 (CRC 始终在 offset 299, 即使帧尾有额外数据)
        computedCRC = sum(frameBuffer[0..298]) & 0xFF
        remoteCRC = frameBuffer[299]
        
        if computedCRC != remoteCRC:
            LOG("CRC mismatch: computed=0x%02X, remote=0x%02X", computedCRC, remoteCRC)
            frameBuffer.clear()
            return
        
        // ✅ 完整帧, 进入解析
        parseFrame(frameBuffer[0..299])
        frameBuffer.clear()
```

#### Step 5: 帧分发与协议版本识别

```pseudocode
// 协议版本需在首次收到 Type 0x03 (设备信息) 时确定
protocolVersion = UNKNOWN  // JK04 / JK02_24S / JK02_32S

FUNCTION parseFrame(data: [UInt8]):
    frameType = data[4]
    
    switch frameType:
        case 0x03:  // 设备信息帧 (首次连接后第一个帧)
            parseDeviceInfo(data)
            // 从 Vendor ID 确定协议版本
            vendorID = String(data[6..21])  // 如 "JK-B2A24S15P" 或 "JK_B2A24S15P"
            protocolVersion = detectProtocol(vendorID)
            
        case 0x01:  // Settings 帧
            if protocolVersion == JK04:
                parseJK04Settings(data)
            else:
                parseJK02Settings(data)
                
        case 0x02:  // 实时电芯数据帧 ⭐ (主要数据源)
            if protocolVersion == JK04:
                parseJK04CellInfo(data)
            else:
                parseJK02CellInfo(data)

FUNCTION detectProtocol(vendorID: String) -> ProtocolVersion:
    // 下划线命名 (JK_xxxx) → 32S 系列
    if vendorID.hasPrefix("JK_"):
        return JK02_32S
    // 旧版 JK-B{x}A{y}S (不含P后缀, v3.x固件) → JK04
    if vendorID matches "JK-B\\dA\\d+S$" AND firmwareVersion < "10.0":
        return JK04
    // 其他 → JK02_24S
    return JK02_24S
```

#### Step 6: 解析 Type 0x02 实时数据帧 (JK02)

```pseudocode
FUNCTION parseJK02CellInfo(data: [UInt8]):
    // 32S 协议有 16 字节偏移 (32 cells × 2B vs 24 cells × 2B)
    offset = 0
    if protocolVersion == JK02_32S:
        offset = 16
    cellCount = 24 + (offset / 2)  // 24 or 32
    
    // ═══════════════════════════════════════════
    // ⭐ 单体电压 (最核心的数据)
    // ═══════════════════════════════════════════
    cellVoltages = []
    for i in 0..<cellCount:
        raw = uint16_le(data, i * 2 + 6)    // 小端序 2 字节
        voltage = raw * 0.001               // 单位: V
        cellVoltages.append(voltage)
    
    // ⭐ 单体电阻
    cellResistances = []
    for i in 0..<cellCount:
        raw = uint16_le(data, i * 2 + 64 + offset)
        resistance = raw * 0.001            // 单位: Ω
        cellResistances.append(resistance)
    
    ofs2 = offset * 2   // 电阻区域之后偏移翻倍
    
    // ═══════════════════════════════════════════
    // ⭐ 电池总体参数
    // ═══════════════════════════════════════════
    totalVoltage  = uint32_le(data, 118 + ofs2) * 0.001   // V
    current       = int32_le(data, 126 + ofs2) * 0.001    // A (有符号! 正=充电, 负=放电)
    power         = totalVoltage * current                 // W
    
    // ⭐ 温度
    temp1 = int16_le(data, 130 + ofs2) * 0.1   // °C (温度传感器 1)
    temp2 = int16_le(data, 132 + ofs2) * 0.1   // °C (温度传感器 2)
    mosfetTemp = int16_le(data, 134 + ofs2) * 0.1  // °C (仅24S; 32S此处为报警位)
    
    // 32S 特殊处理: offset 134 是报警位而非MOS温度
    if protocolVersion == JK02_32S:
        errorsBitmask = (data[134 + ofs2] << 8) | data[135 + ofs2]
        // MOS 温度在 32S 中位于 offset 112+ofs2
        mosfetTemp = int16_le(data, 112 + ofs2) * 0.1
    else:
        errorsBitmask = (data[136 + ofs2] << 8) | data[137 + ofs2]
    
    // ⭐ 报警解码 (16 bit bitmask)
    alarms = decodeAlarms(errorsBitmask)
    // bit0:  充电过温         bit1:  充电低温
    // bit2:  协处理器通信错    bit3:  单体欠压
    // bit4:  组包欠压         bit5:  放电过流
    // bit6:  放电短路         bit7:  放电过温
    // bit8:  线阻异常         bit9:  MOS过温
    // bit10: 电芯数不匹配     bit11: 电流传感器异常
    // bit12: 单体过压         bit13: 组包过压
    // bit14: 充电过流         bit15: 充电短路
    
    // ⭐ SOC 与容量
    balanceCurrent = int16_le(data, 138 + ofs2) * 0.001     // A
    soc            = data[141 + ofs2]                        // %  (0~100)
    capacityRemain = uint32_le(data, 142 + ofs2) * 0.001    // Ah
    nominalCapacity= uint32_le(data, 146 + ofs2) * 0.001    // Ah
    cycleCount     = uint32_le(data, 150 + ofs2)             // 次
    
    // ⭐ MOS 开关状态
    chargingEnabled    = bool(data[166 + ofs2])
    dischargingEnabled = bool(data[167 + ofs2])
    
    // ⭐ 运行时间
    totalRuntime = uint32_le(data, 162 + ofs2)  // 秒
    
    // 32S 特有: 干触点 & 充电状态
    if protocolVersion == JK02_32S:
        dry1On = (data[249 + offset] & 0x02) != 0
        dry2On = (data[249 + offset] & 0x04) != 0
        chargeStatusID = data[248 + offset]  // 0=Bulk, 1=Absorption, 2=Float
    
    // 更新 UI
    updateBatteryDisplay(cellVoltages, totalVoltage, current, soc, temp1, temp2, alarms, ...)
```

#### Step 7: 解析 Type 0x02 实时数据帧 (JK04)

```pseudocode
FUNCTION parseJK04CellInfo(data: [UInt8]):
    // JK04 使用 IEEE 754 float32, 每个 cell 4 字节
    cellVoltages = []
    totalVoltage = 0.0
    for i in 0..<24:
        raw = uint32_le(data, i * 4 + 6)
        voltage = ieee754_to_float(raw)     // float32 解码
        cellVoltages.append(voltage)
        totalVoltage += voltage  // JK04 的总电压需要软件求和
    
    cellResistances = []
    for i in 0..<24:
        raw = uint32_le(data, i * 4 + 102)
        resistance = ieee754_to_float(raw)
        cellResistances.append(resistance)
    
    balancing       = data[220] != 0x00      // 0=Off, 1=充电均衡, 2=放电均衡
    balanceCurrent  = ieee754_to_float(uint32_le(data, 222))  // A
    uptime          = uint32_le(data, 286)   // 秒
    
    // ⚠️ JK04 Cell Info 帧中不含电流、温度、SOC 等字段
    updateBatteryDisplay(cellVoltages, totalVoltage, balanceCurrent, ...)
```

#### Step 8: 周期性保活 (可选)

```pseudocode
// BMS 收到 0x97 命令后会自动开始推送 Type 0x01 和 Type 0x02
// 但如果长时间未收到数据, 可以重新发送触发命令

ON timer(every: 15 seconds):
    if not receivedDataRecently:
        cmd = buildCommand(0x96, value: 0x00000000, length: 0x00)
        peripheral.writeValue(cmd, for: writeChar, type: .withoutResponse)
```

### 11.3 可直接使用的 Swift 实现骨架

> 以下是一个可直接编译运行的 iOS/macOS Swift 实现骨架，覆盖上述全部流程。

```swift
import CoreBluetooth
import Foundation

// MARK: - 常量定义
let JK_BMS_SERVICE_UUID = CBUUID(string: "FFE0")
let JK_BMS_CHAR_UUID    = CBUUID(string: "FFE1")

let CMD_CELL_INFO: UInt8   = 0x96
let CMD_DEVICE_INFO: UInt8 = 0x97

enum ProtocolVersion { case unknown, jk04, jk02_24s, jk02_32s }

// MARK: - 电池数据模型
struct BMSCellInfo {
    var cellVoltages: [Float] = []
    var cellResistances: [Float] = []
    var totalVoltage: Float = 0
    var current: Float = 0
    var power: Float = 0
    var soc: UInt8 = 0
    var temp1: Float = 0
    var temp2: Float = 0
    var mosfetTemp: Float = 0
    var chargingEnabled: Bool = false
    var dischargingEnabled: Bool = false
    var errorsBitmask: UInt16 = 0
    var cycleCount: UInt32 = 0
    var capacityRemaining: Float = 0
    var totalRuntime: UInt32 = 0
}

// MARK: - BMS Manager
class JKBMSManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    
    private var frameBuffer = Data()
    private var protocolVersion: ProtocolVersion = .unknown
    
    // 回调 — 调用方通过设置这些闭包获取数据
    var onCellInfoUpdate: ((BMSCellInfo) -> Void)?
    var onDeviceInfoReceived: ((String, String, String) -> Void)?  // vendorID, hwVer, swVer
    var onError: ((String) -> Void)?
    
    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .global(qos: .userInteractive))
    }
    
    // ═══════════════════════════════════════════
    // MARK: Step 1 — 扫描
    // ═══════════════════════════════════════════
    
    func startScan() {
        central.scanForPeripherals(withServices: [JK_BMS_SERVICE_UUID], options: nil)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { startScan() }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        guard name.hasPrefix("JK-") || name.hasPrefix("JK_") else { return }
        
        // 找到 JK-BMS，停止扫描并连接
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }
    
    // ═══════════════════════════════════════════
    // MARK: Step 2 — 连接 + 服务发现
    // ═══════════════════════════════════════════
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([JK_BMS_SERVICE_UUID])
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == JK_BMS_SERVICE_UUID }) else { return }
        peripheral.discoverCharacteristics([JK_BMS_CHAR_UUID], for: service)
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        
        for char in chars where char.uuid == JK_BMS_CHAR_UUID {
            if char.properties.contains(.notify) || char.properties.contains(.indicate) {
                notifyChar = char
            }
            if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                writeChar = char
            }
        }
        
        // ═══════════════════════════════════════════
        // MARK: Step 3 — 订阅通知
        // ═══════════════════════════════════════════
        if let nc = notifyChar {
            peripheral.setNotifyValue(true, for: nc)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else { onError?("Notification subscribe failed: \(error!)"); return }
        
        // 订阅成功 → 发送设备信息请求，触发 BMS 开始推送
        sendCommand(CMD_DEVICE_INFO, value: 0x00000000, length: 0x00)
    }
    
    // ═══════════════════════════════════════════
    // MARK: 命令构造与发送
    // ═══════════════════════════════════════════
    
    private func sendCommand(_ address: UInt8, value: UInt32, length: UInt8) {
        guard let wc = writeChar else { return }
        
        var frame: [UInt8] = [
            0xAA, 0x55, 0x90, 0xEB,                             // 帧头 (反序!)
            address, length,
            UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF),
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00,
            0x00, 0x00                                           // CRC 占位
        ]
        let crc = frame[0..<19].reduce(0, &+)                   // UInt8 溢出自动截断
        frame[19] = crc
        
        let type: CBCharacteristicWriteType = wc.properties.contains(.writeWithoutResponse)
            ? .withoutResponse : .withResponse
        peripheral?.writeValue(Data(frame), for: wc, type: type)
    }
    
    // ═══════════════════════════════════════════
    // MARK: Step 4 — 接收通知 + 帧组装
    // ═══════════════════════════════════════════
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, error == nil else { return }
        
        // 检测帧头 → 新帧开始
        if data.count >= 4 && data[0] == 0x55 && data[1] == 0xAA && data[2] == 0xEB && data[3] == 0x90 {
            frameBuffer = Data()
        }
        
        frameBuffer.append(data)
        
        // 防止异常累积
        if frameBuffer.count > 400 {
            frameBuffer = Data()
            return
        }
        
        // 帧组装完成?
        if frameBuffer.count >= 300 {
            let crc = frameBuffer[0..<299].reduce(0, &+)        // UInt8 溢出截断 = & 0xFF
            guard crc == frameBuffer[299] else {
                onError?("CRC mismatch")
                frameBuffer = Data()
                return
            }
            
            // ✅ CRC 通过，分发处理
            let completeFrame = [UInt8](frameBuffer[0..<300])
            frameBuffer = Data()
            parseFrame(completeFrame)
        }
    }
    
    // ═══════════════════════════════════════════
    // MARK: Step 5 — 帧分发
    // ═══════════════════════════════════════════
    
    private func parseFrame(_ data: [UInt8]) {
        let frameType = data[4]
        switch frameType {
        case 0x03:
            parseDeviceInfo(data)
        case 0x01:
            // Settings 帧 — 按需解析配置参数
            break
        case 0x02:
            switch protocolVersion {
            case .jk04:     parseJK04CellInfo(data)
            case .jk02_24s: parseJK02CellInfo(data, is32S: false)
            case .jk02_32s: parseJK02CellInfo(data, is32S: true)
            case .unknown:  parseJK02CellInfo(data, is32S: false) // fallback
            }
        default:
            break
        }
    }
    
    // ═══════════════════════════════════════════
    // MARK: 设备信息解析 + 协议版本检测
    // ═══════════════════════════════════════════
    
    private func parseDeviceInfo(_ data: [UInt8]) {
        let vendorID = String(bytes: data[6..<22], encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
        let hwVersion = String(bytes: data[22..<30], encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
        let swVersion = String(bytes: data[30..<38], encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
        
        // 协议版本检测
        if vendorID.hasPrefix("JK_") {
            protocolVersion = .jk02_32s
        } else if vendorID.hasPrefix("JK-") {
            // 简化判断: 新固件 (10.x+) → JK02_24S, 旧固件 (3.x) → JK04
            let major = Int(swVersion.prefix(while: { $0 != "." })) ?? 10
            protocolVersion = major < 10 ? .jk04 : .jk02_24s
        }
        
        onDeviceInfoReceived?(vendorID, hwVersion, swVersion)
    }
    
    // ═══════════════════════════════════════════
    // MARK: Step 6 — JK02 Cell Info 解析
    // ═══════════════════════════════════════════
    
    private func parseJK02CellInfo(_ data: [UInt8], is32S: Bool) {
        let offset: Int = is32S ? 16 : 0
        let cellCount = is32S ? 32 : 24
        var info = BMSCellInfo()
        
        // 单体电压
        for i in 0..<cellCount {
            let v = Float(uint16LE(data, i * 2 + 6)) * 0.001
            info.cellVoltages.append(v)
        }
        
        // 单体电阻
        for i in 0..<cellCount {
            let r = Float(uint16LE(data, i * 2 + 64 + offset)) * 0.001
            info.cellResistances.append(r)
        }
        
        let ofs2 = offset * 2
        
        info.totalVoltage       = Float(uint32LE(data, 118 + ofs2)) * 0.001
        info.current            = Float(Int32(bitPattern: uint32LE(data, 126 + ofs2))) * 0.001
        info.power              = info.totalVoltage * info.current
        info.temp1              = Float(Int16(bitPattern: uint16LE(data, 130 + ofs2))) * 0.1
        info.temp2              = Float(Int16(bitPattern: uint16LE(data, 132 + ofs2))) * 0.1
        info.soc                = data[141 + ofs2]
        info.capacityRemaining  = Float(uint32LE(data, 142 + ofs2)) * 0.001
        info.cycleCount         = uint32LE(data, 150 + ofs2)
        info.chargingEnabled    = data[166 + ofs2] != 0
        info.dischargingEnabled = data[167 + ofs2] != 0
        info.totalRuntime       = uint32LE(data, 162 + ofs2)
        
        if is32S {
            info.mosfetTemp     = Float(Int16(bitPattern: uint16LE(data, 112 + ofs2))) * 0.1
            info.errorsBitmask  = (UInt16(data[134 + ofs2]) << 8) | UInt16(data[135 + ofs2])
        } else {
            info.mosfetTemp     = Float(Int16(bitPattern: uint16LE(data, 134 + ofs2))) * 0.1
            info.errorsBitmask  = (UInt16(data[136 + ofs2]) << 8) | UInt16(data[137 + ofs2])
        }
        
        onCellInfoUpdate?(info)
    }
    
    // ═══════════════════════════════════════════
    // MARK: Step 7 — JK04 Cell Info 解析
    // ═══════════════════════════════════════════
    
    private func parseJK04CellInfo(_ data: [UInt8]) {
        var info = BMSCellInfo()
        
        for i in 0..<24 {
            let v = ieeeFloat(uint32LE(data, i * 4 + 6))
            info.cellVoltages.append(v)
            info.totalVoltage += v  // JK04 需要软件求和
        }
        
        for i in 0..<24 {
            let r = ieeeFloat(uint32LE(data, i * 4 + 102))
            info.cellResistances.append(r)
        }
        
        info.totalRuntime = uint32LE(data, 286)
        
        onCellInfoUpdate?(info)
    }
    
    // ═══════════════════════════════════════════
    // MARK: 字节读取辅助函数
    // ═══════════════════════════════════════════
    
    private func uint16LE(_ data: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }
    
    private func uint32LE(_ data: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(data[offset]) | (UInt32(data[offset+1]) << 8) |
        (UInt32(data[offset+2]) << 16) | (UInt32(data[offset+3]) << 24)
    }
    
    private func ieeeFloat(_ raw: UInt32) -> Float {
        Float(bitPattern: raw)
    }
}
```

### 11.4 使用示例

```swift
let bms = JKBMSManager()

bms.onDeviceInfoReceived = { vendorID, hw, sw in
    print("连接到 BMS: \(vendorID), 固件: \(sw)")
}

bms.onCellInfoUpdate = { info in
    print("总电压: \(info.totalVoltage)V, 电流: \(info.current)A, SOC: \(info.soc)%")
    for (i, v) in info.cellVoltages.enumerated() where v > 0 {
        print("  Cell \(i+1): \(String(format: "%.3f", v))V")
    }
}

bms.onError = { msg in
    print("⚠️ 错误: \(msg)")
}

bms.startScan()  // 开始扫描并自动连接
// 之后 onCellInfoUpdate 会每 1~2 秒被调用一次
```

### 11.5 关键注意事项

| 项目 | 说明 |
|------|------|
| **写入帧头** | `AA 55 90 EB` — 与接收帧头 `55 AA EB 90` 字节序相反 |
| **MTU 限制** | 默认 MTU=23 (净载荷 20 bytes)，300 字节帧需要 15+ 次通知，必须做帧组装 |
| **CRC 位置** | 始终在 offset 299，无论帧尾是否有额外数据 |
| **有符号字段** | 电流 (`int32`)、温度 (`int16`) 是有符号的，需要正确转换 |
| **32S 偏移** | 32S 多了 8 个 cell (额外 16 bytes 电压)，导致后续所有字段偏移 +16，到电阻区后偏移变为 +32 |
| **JK04 float32** | JK04 的电压/电阻用 IEEE 754 float32，不是 uint16 × 0.001 |
| **协议检测** | 必须先解析 Type 0x03 的 Vendor ID 才能确定协议版本 |
| **首次触发** | 发送 `0x97` 后 BMS 会先回 Type 0x03，然后自动开始推送 0x01 和 0x02 |
| **错误位掩码** | 32S 的报警在 offset 134+ofs2 (大端序!)，24S 在 offset 136+ofs2 |
| **BLE 断连重连** | 断连后需要清空 frameBuffer，重新订阅通知并发送 0x97 |

---

## 附录 A. 逆向工程方法论 — 给后续 AI 的工作手册

> **目标读者**：接手本项目的 AI agent 或人类逆向工程师。本章系统记录了整个分析过程中的方法论、工具链、关键路径和经验教训，使后续工作者无需重新摸索即可继承并扩展本文档。

### A.1 整体架构认知 — 先画地图再深入

极空BMS App (`com.jktech.bms`) 是一个 **三层混合架构**，每层有不同的分析工具和方法：

```
┌─────────────────────────────────────────────────────────────┐
│  QML/JS 层 (UI + 业务逻辑)                                   │
│  ├─ 嵌入在 libjkbms.so 的 Qt 资源段中                        │
│  ├─ 定义数据绑定 → 字段名 → 帧偏移映射                        │
│  └─ 工具: Qt 资源提取脚本                                     │
├─────────────────────────────────────────────────────────────┤
│  Java 层 (Android BLE 通信)                                   │
│  ├─ com.smartsoft.ble.* 包                                    │
│  ├─ 扫描/过滤/连接/GATT 读写                                  │
│  └─ 工具: jadx                                                │
├─────────────────────────────────────────────────────────────┤
│  Native C++ 层 (协议解析 + 帧构造)                             │
│  ├─ libjkbms_armeabi-v7a.so (~7.2MB, ELF 32-bit ARM)         │
│  ├─ Transfer::parseData, sendCommand, sendValues              │
│  └─ 工具: Ghidra                                              │
└─────────────────────────────────────────────────────────────┘
```

**关键认知**：真正的协议逻辑不在 Java 层，Java 只是 BLE 通信管道。核心解析/构造在 Native C++ 中，而字段含义的"字典"藏在 QML/JS 资源里。三层必须交叉分析。

### A.2 工具链与环境

| 工具 | 版本 | 用途 | 安装路径 | 注意事项 |
|------|------|------|---------|---------|
| jadx | 1.5.1 | Java/XML 反编译 | `/tmp/jadx/bin/jadx` | `jadx -d <output> <apk>` |
| Ghidra | 11.3 | Native ARM .so 反编译 | `/tmp/ghidra_install/ghidra_11.3_PUBLIC` | 需修补 `launch.sh` JDK 检测 (见下) |
| Java | 21 (OpenJDK) | Ghidra 运行依赖 | `/usr/lib/jvm/java-21-openjdk-amd64` | Ghidra 11.x 需要 JDK 17+ |
| Python 3 | 系统自带 | Qt 资源提取、JSON 解析 | — | 用于解析嵌入在 .so 中的 Qt 资源 |

#### Ghidra JDK 检测修补

Ghidra 的 `support/launch.sh` 在某些环境下无法找到 JDK。修补方法：

```bash
# launch.sh 第 148 行和第 161 行附近
# 将 JDK 版本检测的正则放宽，或直接设置 JAVA_HOME
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
```

#### Ghidra 无头批量反编译命令

```bash
$GHIDRA_HOME/support/analyzeHeadless /tmp/ghidra_project proj_name \
  -import libjkbms_armeabi-v7a.so \
  -postScript ExportDecompiled.java /tmp/output.c \
  -scriptPath /tmp
```

### A.3 核心方法 — "QML 关键字驱动"逆向

这是本项目最高效的方法论。**从 QML UI 层的人类可读字段名出发，反向追踪到字节偏移。**

#### 步骤 1: 提取 QML/JS 资源

Qt 应用将 QML/JS/JSON 资源编译嵌入 `.so` 文件的 `.rodata` 段。提取方法：

```python
# 扫描 .so 文件中的 Qt 资源，识别 QML/JS/JSON 文本块
# 查找特征：以 "import QtQuick" / "function " / "{" 开头的连续 UTF-8 文本
# 资源边界由 0x00 字节分隔
```

提取后得到：
- `resource_*_qml.qml` — QML 页面定义
- `resource_*_utility.js` — 每个页面的配套逻辑
- `resource_*_settings.qml` — 设置页面
- `resource_*_icd.json` — 实际上是 JS 函数文件（ICD 校验逻辑）
- `resource_*_devices.json` — 设备型号数据库

#### 步骤 2: 在 QML 中定位字段名

QML 使用 `JSearchObject` 绑定数据表中的字段：

```qml
JSearchObject {
    id: d02
    objectName: '02'  // ← 对应 Type 0x02 实时数据帧
    property JNumeric batVol: null      // 总电压
    property JNumeric batCurrent: null  // 电流
    property JArray cellVol: null       // 单体电压数组
    property JArray batTemp: null       // 温度传感器
    property JNumeric sysAlarm: null    // 系统报警
}

JSearchObject {
    id: d03
    objectName: '03'  // ← 对应 Type 0x03 设备信息帧
    property JArray bluetoothPwd: null      // 蓝牙密码
    property JArray settingPassword: null   // 设置密码
}
```

这些 **QML 属性名就是协议字段的"人类可读索引"**。

#### 步骤 3: 用 QML 字段名搜索 Native 代码

```bash
# 在 Ghidra 反编译输出中搜索 QML 字段名
grep -n "batVol\|batCurrent\|cellVol\|sysAlarm" /tmp/jkbms_decompiled.c

# 在 esphome 开源实现中交叉验证
grep -n "battery_voltage\|current\|cell.*voltage" /tmp/jk_bms_ble.cpp
```

Native 代码中的 `Transfer::parseData()` 函数按字节偏移从帧中提取数据，并通过 `updateRecvBind()` 更新 QML 绑定。字节偏移 → QML 字段名的映射就此建立。

#### 步骤 4: 写入命令的反向追踪

从 QML UI 按钮出发，反向追踪写入命令：

```
QML 按钮 onClicked
  → grep "enableDischarge\|enableCharge" resource_*.js
    → 找到: UtilityJs.controlSwitchToggled(... Transfer.enableDischarge)
      → grep "enableDischarge" jkbms_decompiled.c
        → Transfer::enableDischarge() → setValueVariant(this, param_1, 4, ...)
          → sendValues() → 构造 AA 55 90 EB [addr] [len] [val] ... [CRC]
```

**关键参数解读** (从 `setValueVariant` 的调用参数推断)：
- 第 3 个参数 `4` = 值的字节长度
- 第 5 个参数 `6000` = 超时时间 (ms)

#### 实战示例: 发现放电开关命令码

```
1. QML 中发现: onSwClicked → Transfer.enableDischarge
2. Native 中: Transfer::enableDischarge → setValueVariant(this, param_1, 4, value, 6000, ...)
3. param_1 是从 QML 传入的寄存器地址 → 需要找到 QML 中的绑定
4. QML 中: d01.batDischargeEn → JSearchObject objectName: '01' (Settings 帧)
5. esphome 交叉验证: Settings 帧 offset 122 = Discharge switch
6. esphome switch/__init__.py: CONF_DISCHARGING = [0x00, 0x1E, 0x1E]
   → JK02_24S/32S 写入地址为 0x1E
```

### A.4 开源社区交叉验证法

[esphome-jk-bms](https://github.com/syssi/esphome-jk-bms) 是最重要的外部参考。它提供了完整的字节级解析，可用于：

| 文件 | 用途 | 关键内容 |
|------|------|---------|
| `components/jk_bms_ble/jk_bms_ble.cpp` | 帧解析 | `decode_jk02_cell_info_()` — 每个字节偏移的含义和系数 |
| `components/jk_bms_ble/jk_bms_ble.h` | 常量定义 | COMMAND_CELL_INFO=0x96, COMMAND_DEVICE_INFO=0x97 |
| `components/jk_bms_ble/switch/__init__.py` | 开关命令 | 充电/放电/均衡等的寄存器地址，按协议版本分列 |
| `components/jk_bms_ble/number/__init__.py` | 参数设置 | 阈值参数的寄存器地址和取值范围 |

**获取方式**：
```bash
curl -sL "https://raw.githubusercontent.com/syssi/esphome-jk-bms/main/components/jk_bms_ble/jk_bms_ble.cpp" > /tmp/jk_bms_ble.cpp
curl -sL "https://raw.githubusercontent.com/syssi/esphome-jk-bms/main/components/jk_bms_ble/switch/__init__.py" > /tmp/switch_init.py
```

**验证策略**: 对于每个字段，用 APK 反编译结果和 esphome 结果互相校验。当两者偏移一致时，可信度高；不一致时需进一步分析是协议版本差异还是错误。

### A.5 文件清单与位置

当前分析产出的所有中间文件：

| 文件 | 路径 | 说明 |
|------|------|------|
| APK 原文件 | `/scratch/lamarr/work/极空BMS_5.12.0.apk` | 极空BMS v5.12.0 (versionCode 233) |
| Java 反编译 | `/scratch/lamarr/work/极空BMS_decompiled/` | jadx 完整输出 |
| Native 反编译 | `/tmp/jkbms_decompiled.c` | Ghidra 输出，44 个函数，3893 行 |
| esphome 参考 | `/tmp/jk_bms_ble.cpp` | 1678 行，社区协议实现 |
| QML 资源 | `/tmp/resource_*.qml`, `/tmp/resource_*.js` | 从 .so 提取的 Qt 资源 |
| 设备数据库 | `/tmp/resource_4_devices.json` | 174 个设备型号，7 个协议族 |
| 协议 JSON | `/tmp/resource_2_protocol_en.json` | UART 协议列表 |
| 本文档 | `/scratch/lamarr/work/JK_BMS_BLE_Protocol_Analysis.md` | 主要交付物 |

### A.6 关键 Java 类速查

| 类名 | 路径 | 行数 | 核心职责 |
|------|------|------|---------|
| `Bluetooth.java` | `com/smartsoft/ble/` | 615 | BLE 扫描/过滤/连接状态管理 |
| `BleService.java` | `com/smartsoft/ble/` | 321 | GATT 操作（读写特征值、通知订阅） |
| `NativeClass.java` | `com/smartsoft/ble/` | 22 | JNI 桥接（Java ↔ C++） |
| `BluetoothInfo.java` | `com/smartsoft/ble/` | — | 设备信息封装 (device, name, rssi, scanRecord) |
| `JScanRecord.java` | `com/smartsoft/ble/` | 137 | 扫描广播包解析 |
| `DeviceState.java` | `com/smartsoft/ble/` | — | BLE 适配器状态枚举 |
| `BleType.java` | `com/smartsoft/ble/` | — | 蓝牙模块类型 (Unknown, JDY, JDY_Other) |

### A.7 关键 Native 函数速查

| 函数名 | 地址 | 反编译行号 | 职责 |
|--------|------|-----------|------|
| `BitStream_readU32` | 0x0039a9c0 | ~50 | 位流读取 (用于解析压缩数据) |
| `loadProtoInfos` | 0x0039b9dc | ~400 | 加载协议定义 (根据 Vendor ID 查设备数据库) |
| `updateRecvBind` | 0x0039bdf4 | ~520 | 解析后数据→QML 绑定更新 |
| `sendCommandImm` | 0x0039ce70 | 1789 | 立即发送命令(包装 sendCommand) |
| `sendCommand` | 0x0039d0fc | 1833 | 构造命令帧 (QML 调用入口) |
| `sendCommand` (重载) | 0x003a395c | 2061 | 构造命令帧 (内部，含帧头 AA 55 90 EB) |
| `enableCharge` | 0x0039d1b8 | 1871 | 充电开关命令 |
| `enableDischarge` | 0x0039d274 | 1908 | 放电开关命令 |
| `switchStatus` | 0x0039e348 | 1945 | 通用开关命令 |
| `parseData` | — | 2554 | **核心**：接收帧解析 (按偏移提取字段) |
| `sendValues` | — | 2957 | **核心**：多值写入帧构造 |
| `checkAndSend` | 0x003a5372 | 3458 | 计算 CRC + BLE 发送 |
| `parseSysLog` | — | — | 系统日志帧解析 |

### A.8 尚未完成的工作 (待后续继续)

以下领域已有线索但尚未深入分析，后续 AI 可优先在此方向展开：

#### 1. Settings 帧 (Type 0x01) 完整字段映射
- 当前第 6 章仅列出部分关键字段
- `resource_109_utility.js` 中有完整的 Settings 页面字段定义（约 100 个参数）
- esphome 的 `number/__init__.py` 有每个参数的寄存器地址和取值范围
- **方法**：用 `d01.volCellOV`, `d01.timBatCOC` 等 QML 属性名在 esphome 中交叉查找偏移

#### 2. 32S 协议扩展字段
- JK02_32S 在 Type 0x02 和 Type 0x03 帧的后半段有大量扩展字段
- esphome 中 `decode_jk02_32s_cell_info_()` 是独立函数，处理 32S 特有的字段
- `resource_135_utility.js` 是 32S 专用的控制页面，包含 DRY1/DRY2 干节点、GPS 等

#### 3. UART/RS485 协议
- `resource_2_protocol_en.json` 包含 30+ 种 UART 协议定义
- APK 同时支持 BLE 和 UART 两种通信方式
- UART 协议与 BLE 的帧格式不同，需独立分析

#### 4. OTA 固件升级协议
- 未发现明显的 OTA 逻辑在当前反编译中
- 可能在 Qt C++ 层有专门的升级模块

#### 5. 日志帧解析
- Native 中有 `parseSysLog` 函数，对应设备内部故障日志
- QML 中 `d02.detailLogsCount` 记录日志条数
- 日志帧的结构尚未文档化

### A.9 给后续 AI 的建议

1. **始终从 QML 出发**。当你需要搞清楚某个功能的协议细节时，先在 `resource_*.js` 和 `resource_*.qml` 中搜索相关 UI 文本或字段名，这比直接啃 Native 反编译代码高效 10 倍。

2. **善用 esphome 做 ground truth**。esphome 项目有大量社区验证，每个字段的偏移和系数都经过实际硬件测试。当 APK 反编译结果不确定时，以 esphome 为准。

3. **注意协议版本差异**。JK04、JK02_24S、JK02_32S 三个版本的帧结构差异显著（尤其是温度传感器数量导致的偏移变化 `ofs2`）。分析时必须明确当前讨论的是哪个版本。

4. **QML 属性名 ≠ 协议字段名**。例如 QML 的 `batVol` 对应 esphome 的 `total_voltage`，`sysAlarm` 对应 `errors_bitmask`。建立一个 QML↔esphome 的名称映射表会很有帮助。

5. **Java 层几乎不含协议逻辑**。不要花时间在 Java 层寻找数据解析或命令构造——它只是 BLE 管道。唯一有价值的 Java 分析是 `Bluetooth.java` 中的扫描过滤逻辑。

6. **`setValueVariant()` 是核心写入入口**。所有写入命令最终都通过 `setValueVariant(this, registerAddr, valueLength, value, timeout, ...)` → `sendValues()` → `checkAndSend()` 链路发出。参数位置固定：
   - 参数 2: 寄存器地址
   - 参数 3: 值长度 (通常为 4)
   - 参数 5: 超时 (enableCharge/Discharge 使用 6000ms)

7. **Qt 资源提取可能需要重做**。`/tmp` 下的提取文件可能被清理。重新提取的方法是扫描 `libjkbms_armeabi-v7a.so` 的 `.rodata` 段，查找 UTF-8 文本块边界。APK 中 .so 文件路径为 `lib/armeabi-v7a/libjkbms.so`。

8. **搜索策略的优先级**：
   ```
   QML/JS 文本搜索 (最快，最直观)
     ↓ 找到字段名
   esphome 交叉验证 (确认偏移和系数)
     ↓ 确认冲突时
   Native 反编译深入 (最慢，但最权威)
   ```

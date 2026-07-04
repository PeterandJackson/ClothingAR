# ClothingAR — iOS 3D 服装实时穿戴 AR 应用

## 项目概述

基于 iOS 原生框架开发的 3D 服装实时穿戴应用，适配 **iPhone X + iOS 16.7.16**。
使用 Vision 框架进行人体姿态检测，SceneKit 渲染 3D 服装模型，通过骨骼蒙皮驱动实现服装跟随人体动作实时变形。

## 系统要求

| 项 | 要求 |
|---|------|
| 设备 | iPhone X (A11 Bionic) |
| 系统 | iOS 16.7.16 |
| Xcode | 14.0+ |
| Swift | 5.7+ |
| 网络 | 不需要（完全离线运行） |

## 技术栈

- **相机**: AVFoundation
- **人体姿态**: Vision (VNDetectHumanBodyPoseRequest)
- **人体分割**: Vision (VNGeneratePersonSegmentationRequest)
- **3D 渲染**: SceneKit
- **视频录制**: AVAssetWriter (H.264 + AAC)
- **相册保存**: Photos 框架
- **零第三方依赖**

---

## 快速开始

### 1. 创建 Xcode 项目

1. 打开 Xcode → **File → New → Project**
2. 选择 **iOS → App**
3. Interface: **Storyboard** (因为我们用纯代码 UI，Storyboard 为空即可)
4. Language: **Swift**
5. 项目名: `ClothingAR`
6. 保存到任意位置

### 2. 导入源文件

将所有 `.swift` 文件拖入 Xcode 项目：
- `AppDelegate.swift`, `SceneDelegate.swift` → 项目根
- `Core/` 目录下 7 个文件
- `Recording/` 目录下 2 个文件
- `UI/` 目录下 3 个文件
- `Performance/` 目录下 2 个文件

勾选 **"Copy items if needed"** 和 **"Create groups"**。

### 3. 配置 Info.plist

确保 `Info.plist` 包含以下权限描述：
```
NSCameraUsageDescription    → "ClothingAR 需要使用相机..."
NSMicrophoneUsageDescription → "ClothingAR 需要使用麦克风..."
NSPhotoLibraryAddUsageDescription → "ClothingAR 需要将视频保存到相册"
```

### 4. 转换并导入模型

#### 4.1 FBX → DAE 转换

用 **Blender**（免费）执行一次性转换：

1. 打开 Blender → File → Import → FBX
2. 选择 `FBX/THIN WELD.fbx`
3. 确认：模型有骨架（Armature）、网格绑定正常
4. File → Export → Collada (Default) (.dae)
5. 导出设置：
   - ✅ Selection Only
   - ✅ Include Armatures
   - ✅ Include Shape Keys
   - ✅ Include Children

#### 4.2 放入项目

将转换后的 `THIN WELD.dae` 和 `Textures/` 目录放入：
```
ClothingAR/Resources/Models/
```

在 Xcode 中将 `THIN WELD.dae` 拖入项目，确保文件被添加到 Target。

### 5. 编译运行

1. 用 USB 连接 iPhone X
2. Xcode 中选择 iPhone X 作为目标设备
3. **Product → Build** (⌘B) 编译
4. **Product → Run** (⌘R) 运行

---

## 项目结构

```
ClothingAR/
├── AppDelegate.swift              # 应用入口 + 临时文件清理
├── SceneDelegate.swift            # Window 创建
├── Info.plist                     # 权限配置
├── Assets.xcassets/               # 应用图标
├── Core/
│   ├── CameraManager.swift        # 相机+麦克风采集管线
│   ├── BodyTracker.swift          # Vision 人体姿态检测 (EMA平滑)
│   ├── SkeletonMapper.swift       # 2D→3D 骨骼映射 + 深度估算
│   ├── PersonSegmentation.swift   # 人体分割遮罩
│   ├── SceneRenderer.swift        # SceneKit 3D渲染 + 遮挡
│   ├── ModelLoader.swift          # DAE/SCN加载 + 骨骼匹配
│   └── ModelCalibration.swift     # 模型校准参数
├── Recording/
│   ├── VideoRecorder.swift        # AVAssetWriter 视频+音频
│   └── PhotoAlbumSaver.swift      # Photos 相册保存
├── UI/
│   ├── ARViewController.swift     # 主控制器（协调所有模块）
│   ├── RecordButton.swift         # 录制按钮（红点闪烁+长按重置）
│   └── StatusIndicator.swift      # 跟踪状态/FPS显示
├── Performance/
│   ├── PerformanceMonitor.swift   # CADisplayLink FPS 监控
│   └── QualityManager.swift       # 自动降级质量管理
├── Resources/Models/
│   ├── FBX/THIN WELD.fbx          # 原始FBX（用于转换）
│   ├── Textures/                  # PBR贴图
│   └── THIN WELD.dae             # 转换后的DAE（iOS加载这个）
└── README.md
```

---

## 参数调优

### 模型校准

编辑 `Core/ModelCalibration.swift` 中的 `CalibrationConfig`：

```swift
CalibrationConfig.modelScale    = 1.0    // 衣服整体缩放
CalibrationConfig.modelOffsetY  = 0.0    // 上下微调（+Y=向上）
CalibrationConfig.modelOffsetX  = 0.0    // 左右微调（+X=向右）
CalibrationConfig.modelOffsetZ  = 0.0    // 前后微调（+Z=朝镜头）
CalibrationConfig.bodyHeight    = 1.7    // 你的身高（米）
CalibrationConfig.occlusionPlaneDistance = 0.8 // 遮挡平面距离
```

### 性能降级阈值

编辑 `Performance/QualityManager.swift`：

```swift
degradeThreshold  = 25    // FPS < 25 触发降级
restoreThreshold  = 28    // FPS > 28 持续3秒恢复
criticalThreshold = 20    // FPS < 20 严重降级
```

### 骨骼映射

如果模型骨骼名未自动匹配，打印到 Xcode 控制台后，编辑 `Core/ModelLoader.swift` 中 `BoneNameLookup.lookupTable` 添加你的骨骼名。

---

## 骨骼命名自动匹配

内置 4 种常见命名体系：
- **Mixamo**: `mixamorig:LeftShoulder`
- **3ds Max Biped**: `Bip01_L_Clavicle`
- **Blender Rigify**: `shoulder.L`
- **Maya HumanIK**: `LeftShoulder`

启动时 Xcode 控制台会打印所有未匹配的骨骼名，按需手动添加映射。

---

## 使用说明

1. **启动应用** → 自动开启前置摄像头
2. **站在手机前** → 识别到人体后衣服自动吸附
3. **做动作** → 抬手、转身、弯腰等，衣服跟随变形
4. **点击录制按钮** → 开始录屏（红点闪烁）
5. **再次点击** → 停止录制，自动保存到系统相册
6. **长按录制按钮 3 秒** → 重置模型校准参数

---

## 常见问题

### 启动没画面？
- 检查相机权限是否允许（设置 > 隐私 > 相机）
- 确保 Mac 签名配置正确

### 衣服不动？
- 看 Xcode 控制台输出的骨骼匹配结果
- 可能是骨骼名未匹配，需手动添加映射

### 衣服位置不对？
- 调整 `ModelCalibration.swift` 中的偏移参数
- 或长按录制按钮 3 秒重置

### 很卡 / 掉帧？
- 正常现象，iPhone X 性能有限
- QualityManager 会自动降级效果
- 如果持续卡顿，尝试用更小的模型

### 录制没声音？
- 检查麦克风权限（设置 > 隐私 > 麦克风）

---

## 签名与部署

使用免费 Apple ID 即可部署到 iPhone X：
1. Xcode → Preferences → Accounts → 添加 Apple ID
2. 项目 Target → Signing & Capabilities → Team 选你的账号
3. 自动签名（Automatically manage signing）
4. 免费账号每 7 天需重新签名一次

---

## 已知限制

1. 侧身/手臂前伸时深度估算可能不准（2D 限制）
2. 遮挡是平面近似方案，精细区域可能不完美
3. 灯光方向不匹配，材质可能降级
4. 下摆/裙摆不飘（仅骨骼蒙皮，无布料模拟）
5. 30fps 在复杂场景下可能不稳

---

## License

个人自用项目，不对外发布。

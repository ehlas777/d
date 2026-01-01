# Whisper 本地集成使用说明

本应用已集成本地 Whisper 语音识别功能，可以在不依赖外部 API 的情况下进行视频转录。

## 功能特点

- ✅ 完全本地运行，无需网络连接（首次使用需联网下载模型）
- ✅ 支持多种 Whisper 模型（tiny、base、small、medium）
- ✅ 自动从视频中提取音频
- ✅ 支持多语言识别（中文、英文、哈萨克语、俄语等）
- ✅ **模型自动下载** - 首次使用时自动下载所需模型

## 已安装的依赖

1. **whisper_flutter_new** (v1.0.1) - Whisper.cpp 的 Flutter 封装
2. **ffmpeg_kit_flutter_full** (v6.0.3) - 用于音频提取
3. **path_provider** - 用于文件路径管理

## 模型自动下载 🎉

**好消息：无需手动下载模型！**

whisper_flutter_new 插件会在首次使用时自动下载所需的模型文件到应用的库目录。

### 首次使用流程

1. 启动应用（会自动初始化 Whisper）
2. 如果模型不存在，插件会自动从 Hugging Face 下载
3. 下载完成后即可使用

### 模型下载要求

- 需要网络连接（仅首次下载时）
- 推荐使用 WiFi（模型文件较大）
- 下载后永久保存，后续无需联网

## 模型信息

### 可用模型及特点

| 模型名称 | 文件大小 | 识别质量 | 速度 | 推荐用途 | 自动下载 |
|---------|---------|---------|------|---------|---------|
| tiny    | ~75 MB  | 较低    | 最快 | 快速测试 | ✅ |
| base    | ~140 MB | 中等    | 快   | 日常使用 ⭐推荐 | ✅ |
| small   | ~460 MB | 良好    | 中等 | 高质量需求 | ✅ |
| medium  | ~1.5 GB | 优秀    | 较慢 | 专业用途 | ✅ |

### 模型存储位置

模型会自动下载到：
- **macOS**: `~/Library/Application Support/[AppName]/`
- **iOS**: App 的 Library 目录
- **Android**: App 的 Support 目录

### 切换模型

修改 [home_screen.dart](lib/screens/home_screen.dart) 中的初始化代码：

```dart
// 初始化时指定模型
await service.initialize(modelName: 'base'); // 可选：'tiny', 'base', 'small', 'medium'
```

## 使用方法

### 1. 初始化服务

```dart
final service = TranscriptionService();

// 初始化并加载模型（在应用启动时或首次使用前）
await service.initialize(modelName: 'base'); // 可选：'tiny', 'base', 'small', 'medium'
```

### 2. 转录视频

```dart
// 准备转录选项
final options = TranscriptionOptions(
  language: 'zh',        // 语言代码：'zh'(中文), 'en'(英文), 'ru'(俄语), 'kk'(哈萨克语), null(自动)
  timestamps: true,      // 是否生成时间戳
  model: 'whisper-local', // 使用本地模型
);

// 执行转录
final result = await service.transcribe(
  videoFile: File('/path/to/video.mp4'),
  options: options,
  onProgress: (progress) {
    print('进度: ${(progress * 100).toStringAsFixed(1)}%');
  },
);

// 获取结果
print('转录文本: ${result.fullText}');
print('识别语言: ${result.detectedLanguage}');
print('处理时长: ${result.duration}秒');
```

### 3. 清理资源

```dart
// 使用完毕后释放资源
service.dispose();
```

## 在应用中集成

### 修改 main.dart

在应用启动时初始化 Whisper：

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Whisper（可选：在后台线程中初始化）
  final service = TranscriptionService();
  try {
    await service.initialize(modelName: 'base');
    print('Whisper 初始化成功');
  } catch (e) {
    print('Whisper 初始化失败: $e');
    // 提示用户下载模型
  }

  runApp(MyApp());
}
```

### 在 UI 中使用

参考原有的 `home_screen.dart`，将原来的 API 调用替换为本地转录：

```dart
// 原代码：
// final jobId = await _transcriptionService.uploadAndTranscribe(...);

// 新代码：
final result = await _transcriptionService.transcribe(
  videoFile: _selectedFile!,
  options: _options,
  onProgress: (progress) {
    setState(() {
      _processingProgress = progress;
    });
  },
);

setState(() {
  _transcriptionResult = result;
});
```

## 性能优化建议

1. **首次启动优化**
   - 在应用启动时异步加载模型
   - 显示加载进度给用户

2. **模型选择建议**
   - 移动设备：使用 tiny 或 base 模型
   - 桌面应用：可以使用 small 或 medium 模型
   - 对实时性要求高：使用 tiny 模型
   - 对准确性要求高：使用 medium 模型

3. **音频处理**
   - 视频时长 < 5分钟：所有模型都适用
   - 视频时长 5-30分钟：推荐 base 或 small
   - 视频时长 > 30分钟：推荐使用分段处理

## 已知问题

1. **模型文件较大**
   - base 模型：140 MB
   - 建议在 WiFi 环境下下载
   - 或者在应用首次启动时提供下载选项

2. **内存占用**
   - 运行时需要额外的内存加载模型
   - medium 模型在低端设备上可能较慢

3. **时间戳精度**
   - 当前版本提供基础的时间戳支持
   - 详细的逐字时间戳需要进一步解析

## macOS 权限配置

确保 `macos/Runner/DebugProfile.entitlements` 和 `Release.entitlements` 包含：

```xml
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.temporary-exception.files.absolute-path.read-write</key>
<array>
    <string>/</string>
</array>
```

## 故障排除

### 问题：模型下载失败

```
错误：Failed to download model
```

**解决方案：**
1. 检查网络连接
2. 确认可以访问 Hugging Face（可能需要代理）
3. 尝试使用 VPN
4. 或者手动下载模型并放入应用的库目录

### 问题：FFmpeg 提取音频失败

```
错误：FFmpeg extraction failed
```

**解决方案：**
1. 检查视频文件是否完整
2. 确认视频格式受支持（MP4、MOV、AVI 等）
3. 检查磁盘空间是否充足

### 问题：转录速度太慢

**解决方案：**
1. 切换到更小的模型（tiny 或 base）
2. 调整线程数（在 WhisperRequest 中修改 nThreads）
3. 考虑对长视频进行分段处理

## 已完成功能 ✅

1. ✅ 本地 Whisper 集成
2. ✅ 自动模型下载
3. ✅ FFmpeg 音频提取
4. ✅ 多语言支持
5. ✅ 转录进度显示
6. ✅ 时间戳和分段支持

## 下一步改进

1. [ ] 添加模型管理界面（查看已下载的模型）
2. [ ] 支持模型切换而无需重启应用
3. [ ] 显示模型下载进度
4. [ ] 支持批量视频处理
5. [ ] 优化大文件的内存管理
6. [ ] 添加更多输出格式（SRT、VTT 字幕）

## 参考资源

- Whisper.cpp 仓库：https://github.com/ggerganov/whisper.cpp
- Hugging Face 模型：https://huggingface.co/ggerganov/whisper.cpp
- whisper_flutter_new 插件：https://pub.dev/packages/whisper_flutter_new
- FFmpeg Kit Flutter：https://pub.dev/packages/ffmpeg_kit_flutter_full

# 快速开始指南 🚀

## ✅ 已完成的集成

你的应用现在已经完全集成了**本地 Whisper 语音识别**功能！

- ✅ 无需外部 API
- ✅ 模型自动下载
- ✅ 支持多种语言
- ✅ 完全离线运行（首次使用后）

## 🏃 运行应用

### 1. 构建应用

```bash
# 清理项目（如果需要）
flutter clean

# 获取依赖
flutter pub get

# 构建 macOS 应用
flutter build macos --release
```

或者直接运行：

```bash
flutter run -d macos
```

### 2. 首次使用

首次启动时：
1. 应用会自动初始化 Whisper
2. 如果 base 模型不存在，会自动下载（~140 MB）
3. 需要网络连接，推荐使用 WiFi
4. 下载完成后即可使用

### 3. 使用流程

1. **选择视频**
   - 拖拽视频文件到窗口
   - 或点击选择文件

2. **配置选项**
   - 选择语言（中文/英文/俄语/哈萨克语/自动）
   - 启用时间戳
   - 其他选项

3. **开始转录**
   - 点击"发送转录"按钮
   - 应用会：
     - 提取音频（使用 FFmpeg）
     - 本地转录（使用 Whisper）
     - 生成结果

4. **查看结果**
   - 查看转录文本
   - 查看分段信息
   - 导出 JSON 文件

## 📊 模型说明

### 当前使用的模型
**base 模型**（推荐，已在代码中配置）
- 大小：~140 MB
- 速度：快
- 质量：良好
- 适合：日常使用

### 切换模型

如果需要切换模型，编辑 [lib/screens/home_screen.dart](lib/screens/home_screen.dart#L51)：

```dart
// 第 51 行
await _transcriptionService.initialize(modelName: 'base');

// 可选模型：
// 'tiny'   - 75 MB，最快，质量较低
// 'base'   - 140 MB，推荐 ⭐
// 'small'  - 460 MB，高质量
// 'medium' - 1.5 GB，最高质量
```

## 🌍 支持的语言

在转录设置中选择语言：

- **自动检测** (推荐)
- 中文 (zh)
- 英文 (en)
- 俄语 (ru)
- 哈萨克语 (kk)
- 以及其他 90+ 种语言

## ⚡ 性能参考

| 视频长度 | 模型 | 预估时间 |
|---------|------|---------|
| 1 分钟 | tiny | ~5-10 秒 |
| 1 分钟 | base | ~10-30 秒 |
| 5 分钟 | base | ~1-2 分钟 |
| 10 分钟 | base | ~2-5 分钟 |

*实际时间取决于 CPU 性能

## 📁 文件位置

### 模型存储
```
~/Library/Application Support/[你的应用名]/
├── ggml-base.bin (自动下载)
└── (其他模型文件)
```

### 转录结果
```
/tmp/transcription_[时间戳].json
```

## 🔧 故障排除

### 问题 1：应用启动失败

**错误**: "Whisper not initialized"

**解决**:
```bash
# 重新构建
flutter clean
flutter pub get
flutter build macos --release
```

### 问题 2：模型下载失败

**错误**: "Failed to download model"

**解决**:
1. 检查网络连接
2. 确认可访问 Hugging Face
3. 如需要，使用 VPN
4. 等待一段时间后重试

### 问题 3：音频提取失败

**错误**: "FFmpeg extraction failed"

**解决**:
1. 确认视频文件完整且未损坏
2. 支持的格式：MP4, MOV, AVI, MKV 等
3. 检查磁盘空间

### 问题 4：转录速度慢

**解决**:
1. 切换到 tiny 模型（更快但质量稍低）
2. 关闭其他应用释放 CPU
3. 对长视频考虑分段处理

## 🎯 使用建议

### 最佳实践

1. **首次使用**
   - 使用短视频（1-2分钟）测试
   - 确认模型下载成功
   - 验证转录质量

2. **日常使用**
   - 视频时长 < 10分钟：直接转录
   - 视频时长 > 10分钟：考虑分段
   - 清晰的音频效果最好

3. **语言选择**
   - 单一语言视频：指定语言
   - 多语言或不确定：选择自动

4. **质量优化**
   - 需要高质量：使用 small 或 medium 模型
   - 需要快速处理：使用 tiny 或 base 模型

## 📚 更多文档

- [详细使用说明](WHISPER_LOCAL_SETUP.md)
- [集成总结](INTEGRATION_SUMMARY.md)
- [README](README.md)

## 🆘 获取帮助

如遇到问题：

1. 查看 [WHISPER_LOCAL_SETUP.md](WHISPER_LOCAL_SETUP.md) 的故障排除部分
2. 检查控制台日志
3. 确认 macOS 版本 >= 10.15

---

## 🎉 开始使用

一切就绪！运行应用开始转录你的第一个视频：

```bash
flutter run -d macos
```

享受本地、私密、快速的视频转录体验！

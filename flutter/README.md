# 同声

Android 面对面实时翻译应用，使用 Flutter 和 Dart 开发。语音翻译接入阿里云百炼 `qwen3.8-livetranslate-flash-realtime` WebSocket API。

## 本地配置

应用可在语言选择页右上角的“翻译服务设置”中输入 API Key，并选择北京专属节点、北京公共节点或自定义实时 WebSocket 地址。配置会加密保存在当前 Android 设备。

开发时也可以使用编译期默认配置：

1. 复制 `config.example.json` 为 `config.local.json`。
2. 填入 API Key 和业务空间 ID。
3. 通过 USB 真机运行：

```bash
flutter run \
  -d RWTWYP6PNZSWKZUC \
  --dart-define-from-file=config.local.json
```

页面中保存的设备配置优先于 `dart-define` 默认值。

## 语音流程

- 长按麦克风后建立 WebSocket 会话。
- 以 16kHz、单声道、16-bit PCM 流式上传真机麦克风音频。
- 界面实时显示原文识别和译文。
- 松开后发送 `session.finish`，收到最终结果后播放 24kHz PCM 译文语音。

## 安全提示

`config.local.json` 已被 Git 忽略，但 `dart-define` 值仍会编译进 APK。页面输入的 API Key 使用 Android 安全存储，但客户端仍可能被逆向或在已破解设备上被读取。生产环境应通过自有服务端代理请求或签发短期凭证，不得在 APK 中携带长期 API Key。

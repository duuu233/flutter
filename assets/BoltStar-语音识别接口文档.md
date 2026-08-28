# BoltStar 语音转文字接口文档

> 版本：2026-08-29 | 仅 Android 端使用

小程序使用微信同声传译插件（WechatSI），iOS 使用系统语音识别（NSSpeechRecognition），**均不走此接口**。本接口仅供 Android 端（含无法使用系统语音识别的机型）调用。

---

## 一、接口信息

```
POST https://boltstagent-web-jncfttrxvt.ap-southeast-1.fcapp.run/speech/recognize
```

### 请求头

```
Content-Type: application/json
Authentication: Bearer <JWT_TOKEN>
```

### 请求体

| 参数 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `audio` | string | ✅ | 音频文件的 **base64 编码**内容 |
| `format` | string | ❌ | 音频格式：`wav` / `mp3` / `ogg`，默认 `wav` |

```json
{
  "audio": "UklGRiQAAABXQVZFZm10IBAAAAABAAEA...（base64）",
  "format": "wav"
}
```

---

## 二、响应格式

### 成功响应（code=10000）

```json
{
  "success": true,
  "code": 10000,
  "data": {
    "text": "识别出来的文字内容"
  }
}
```

### 错误响应

```json
{
  "success": false,
  "code": 20002,
  "message": "音频时长超过60秒"
}
```

### 错误码对照表

| code | 含义 | 说明 |
|---|---|---|
| 20001 | 缺少 audio 参数 | audio 为空 |
| 20002 | 参数无效 / 时长超限 | 音频超过 60 秒（仅 WAV 精确校验） |
| 30001 | ASR 调用失败 | 豆包语音识别服务异常 |

---

## 三、curl 示例

```bash
curl -X POST 'https://boltstagent-web-jncfttrxvt.ap-southeast-1.fcapp.run/speech/recognize' \
  -H 'Content-Type: application/json' \
  -H 'Authentication: Bearer <JWT_TOKEN>' \
  -d '{
    "audio": "（base64音频内容）",
    "format": "wav"
  }'
```

---

## 四、注意事项

1. **录音格式**：Android 端需将录音转成 `wav` / `mp3` / `ogg` 再 base64 上传。`MediaRecorder` 默认输出的 `m4a` / `aac` / `amr` 不被支持，建议录音时直接指定输出格式为上述三种之一。

2. **时长限制**：
   - 前端限制最长 1 分钟；
   - 后端对 WAV 做兜底校验（超过 60 秒返回 20002）；
   - mp3 / ogg 后端暂不校验时长，依赖前端限制。

3. **鉴权**：与其他接口一致，需带 `Authentication: Bearer <JWT>`。

4. **底层服务**：豆包语音识别极速版（Doubao ASR），一次请求即返回结果，无需轮询。

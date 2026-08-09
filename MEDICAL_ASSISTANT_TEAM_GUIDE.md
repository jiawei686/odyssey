# Odyssey 医学教育助手：团队说明

这份文档说明本次提交新增的医学教育 Agent 做了什么、能做什么，以及队友拉取代码后的运行方法。

## 1. 本次完成内容

- 在 Vision Pro 端增加独立的 `Medical Education Assistant` 窗口，应用启动后自动请求显示在用户附近。
- 默认 Provider 是 Apple Intelligence，通过 visionOS 26+ 的 Foundation Models 在设备端生成回答。
- 保留 `GPT-5.4 Cloud` 作为显式可选 Provider，使用 OpenAI-compatible Chat Completions 接口。
- 增加 Patient / Clinician 两种回答受众，回答会根据选择调整语言难度和术语密度。
- 增加有限上下文记忆、清空会话、取消请求、失败重试和可选的本地会话持久化。
- 增加本地医学知识检索和引用白名单，当前包含通用解剖资料及 SGH AHPedia 摘要条目。
- 增加医学安全策略：拒绝身份信息和病历信息，紧急症状先给本地急救提示，不生成诊断、处方或患者特异性治疗建议。
- 助手只接收解剖区域、左右侧、当前选中的骨骼名称、会话文本和本地检索摘要，不接收患者图像、DICOM、手部坐标、世界坐标或渲染控制权。
- 增加契约检查和完整构建校验，确保 Companion target 不会链接医学助手代码。

## 2. 代码位置

| 路径 | 职责 |
| --- | --- |
| `UpperLimbPOC/MedicalAssistant/MedicalAssistantView.swift` | 助手窗口、消息气泡、状态、设置和输入框 |
| `UpperLimbPOC/MedicalAssistant/MedicalAssistantStore.swift` | 主线程状态、会话上下文、Provider 路由和记忆 |
| `UpperLimbPOC/MedicalAssistant/AppleFoundationModelClient.swift` | Apple Intelligence / Foundation Models 设备端调用 |
| `UpperLimbPOC/MedicalAssistant/OpenAICompatibleClient.swift` | GPT-5.4 Cloud HTTP 调用 |
| `UpperLimbPOC/MedicalAssistant/MedicalSafetyPolicy.swift` | 角色提示词、隐私拦截、急救提示和引用限制 |
| `UpperLimbPOC/MedicalAssistant/MedicalKnowledgeRepository.swift` | 本地 JSON 知识检索 |
| `UpperLimbPOC/MedicalAssistant/Resources/MedicalAssistantKnowledge.json` | 版本化的本地知识条目 |
| `UpperLimbPOC/MedicalAssistant/MedicalAssistantConfiguration.swift` | 云端 endpoint、模型名和 Keychain 凭据存储 |
| `Tools/MedicalAssistantContractCheck.swift` | 医学助手安全和接口契约检查 |
| `MEDICAL_ASSISTANT.md` | 英文架构与安全说明 |

## 3. 队友拉取和打开项目

```bash
git clone https://github.com/jiawei686/odyssey.git
cd odyssey
git pull origin main
open RadiographicAnatomyPOC.xcodeproj
```

不要使用本机生成的 `project.xcworkspace/xcuserdata` 作为协作内容；它只包含个人 Xcode 窗口状态，未提交到仓库。

Xcode 中选择正确的 Scheme：

- `UpperLimbPOC`：Vision Pro 应用和医学助手。
- `UpperLimbCompanion`：iPhone/iPad 伴侣应用，不包含医学助手网络或 Foundation Models 代码。

## 4. 在模拟器中运行

模拟器可以验证界面和工程编译，但 **不能生成 Apple Intelligence 回答**，因为 Vision Pro Simulator 不包含本地生成模型资产。应用会显示 `Requires a physical Vision Pro`，这是预期行为。

如果要在模拟器中测试完整聊天流程：

1. 启动 `UpperLimbPOC`。
2. 打开助手右上角齿轮按钮。
3. 在 Provider 中明确选择 `GPT-5.4 Cloud`。
4. 在安全输入框中输入测试 API Key，保存到当前模拟器 Keychain。
5. 返回助手后发送通用解剖问题。

云端配置为：

```text
Endpoint: https://api.xcode.best/v1/
Model:    gpt-5.4
Route:    POST /chat/completions
```

API Key 不能写入 Swift、Info.plist、共享 Scheme 或 Git。发布版本需要由团队后端代理云端请求。

## 5. 在实体 Vision Pro 上运行 Apple Intelligence

1. 设备需要 visionOS 26 或更高版本。
2. 在系统设置中打开 Apple Intelligence。
3. 等待本地模型下载完成，建议连接电源和 Wi-Fi。
4. 用数据线或网络连接实体 Vision Pro，在 Xcode Destination 中选择设备名称，不要选择 `Apple Vision Pro (Simulator)`。
5. 运行 `UpperLimbPOC`，助手状态应变为 `Available on this device`。
6. 发送英文或中文的通用解剖教育问题，测试追问、取消、离线能力和上下文记忆。

Apple Intelligence 失败时不会自动切换到云端；需要用户在设置中明确选择另一个 Provider。

## 6. 助手可以做什么

- 用患者易懂的语言解释 Radius、Ulna、前臂和手部相关基础解剖。
- 用临床受众模式提供更紧凑的教育性术语说明。
- 根据当前界面选中的区域和骨骼补充上下文，但不会声称看到了用户身体或扫描结果。
- 对本地知识条目生成 `[S1]` 形式的来源标记，并在界面展示来源标题、发布方和审核状态。
- 记住当前会话中的有限对话，允许用户清空或选择本地持久化。

它不能诊断疾病、判读患者影像、开药、计算剂量、指导手术，也不能移动骨骼、修改 overlay 或访问手部/世界追踪坐标。

## 7. 验证命令

在仓库根目录执行：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./Tools/validate.sh
```

校验包含医学助手契约、知识检索、隐私和引用限制、Vision Pro 模拟器/设备构建、Companion 模拟器/设备构建以及静态分析。

Debug 模拟器可用以下参数验证设备端 Provider 会被正确拦截，且不会发网络请求：

```text
--assistant-on-device-smoke
```

这不是 Apple Intelligence 真机生成验收；真机验收仍需实体 Vision Pro。

## 8. 协作注意事项

- 不要提交 API Key、Token、病历、患者图像、DICOM 或任何真实个人信息。
- 修改 Provider、系统提示词或知识条目后，必须重新运行 `Tools/validate.sh`。
- AHPedia 摘要和本地知识条目当前仍需具名临床审核，不能在演示中称为已审核医疗建议。
- 后续增加 3D 助手、聊天气泡或语音时，应继续让文本助手保持无渲染控制权，并复用现有安全边界。

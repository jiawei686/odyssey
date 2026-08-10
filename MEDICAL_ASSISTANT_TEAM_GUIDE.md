# Odyssey 医学教育助手：团队说明

这份文档说明本次提交新增的医学教育 Agent 做了什么、能做什么，以及队友拉取代码后的运行方法。

## 1. 本次完成内容

- 启动 Vision Pro 端时，USDZ 助手模型会自动出现在解剖库左侧，不会自动弹出聊天面板。右上角按钮保留为隐藏或恢复整个助手的备用控件。
- 凝视模型并 pinch 可打开 `Medical Education Assistant` 面板；再次凝视并 pinch 同一模型只关闭面板，模型始终保持可见。
- 助手有 7 秒一个往复周期的待机动作，相对正面最多左右旋转 14 度，不会背对用户；开启系统“减少动态效果”后动画停用。
- 新增 Voice / Text 输入切换，默认为 Voice。语音识别的中间结果实时显示，静默 1.3 秒后自动发送。
- Apple Intelligence 和 GPT-5.4 Cloud 都使用流式回答，文字会在面板中逐步出现；回答完成后系统语音会朗读并恢复监听。
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
| `UpperLimbPOC/MedicalAssistant/AssistantAvatarView.swift` | USDZ 模型加载、缩放、有限角度待机旋转、可交互碰撞体和 pinch 切换面板 |
| `UpperLimbPOC/MedicalAssistant/AssistantVoiceController.swift` | 本地语音识别、实时转录、静默提交和回答朗读 |
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

1. 启动 `UpperLimbPOC`，确认模型自动出现且聊天面板不会自动打开。
2. 在模拟器中点击模型（真机上为凝视 + pinch）打开面板，再点一次确认只关闭面板。
3. 打开助手右上角齿轮按钮。
4. 在 Provider 中明确选择 `GPT-5.4 Cloud`。
5. 在安全输入框中输入测试 API Key，保存到当前模拟器 Keychain。
6. 返回助手，使用 Voice 或 Text 发送通用解剖问题。

模拟器可检查模型和流式聊天界面，但真实凝视 + pinch、麦克风、本地语音识别和朗读体验必须在实体 Vision Pro 上验收。

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
5. 运行 `UpperLimbPOC`，确认模型自动出现，再凝视 + pinch 打开面板，助手状态应变为 `Available on this device`。
6. 授予 Microphone 和 Speech Recognition 权限。
7. 说出英文或中文的通用解剖教育问题，检查实时转录、流式回答、朗读、追问、取消、离线能力和上下文记忆。

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
- 后续为 3D 助手增加更多状态动画或空间聊天气泡时，应继续让模型只消费 ready / thinking / speaking / warning 等展示状态，不获得渲染控制权或医学决策权。

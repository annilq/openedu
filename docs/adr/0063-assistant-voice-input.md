# ADR-0063：助手语音输入——平台原生 STT、能力门禁与三端契约

状态：草案（Proposed），待实施排期。

AI 学习助手目前只有键盘一条输入路径（`assistant_chat_page.dart:478` 的 `_InputBar`）。儿童在平板上打中文最痛苦（手写慢、拼音要选字），家长出题又常是长句（「帮我出五道三年级分数加减法的应用题」），两端都有明确的语音输入诉求。本 ADR 确立「平台原生 STT + 能力门禁 + 落草稿」的方案，**并明确 Web 与 Linux 不做**。

## 背景：三处约束与一个反直觉事实

1. **语音不是 AI 能力，是输入法**：`ModelConfig`（`backend/app/db/models/model_config.py:6`）只有 `provider/base_url/model_name`，**没有能力字段**；ADR-0039 立法「无内置模型目录、家长手动录入、无离线 mock 兜底」。若语音依赖模型配置，则零配置时功能残废，与 ADR-0039 目的直接冲突。
2. **音频进后端就要回答留存期、归属、删除权**：录音里是**儿童声音**。一旦新增音频上传端点，就得配套 retention 策略、`parent_id` 归属与删除通道——这是一条我们目前完全没有的合规面。
3. **三端底层可用性根本不一致**（反直觉事实，是本 ADR 的主要驱动力）：

| 平台 | `speech_to_text` 7.4.0 | 转写在哪跑 | 国内可用性 |
|---|---|---|---|
| iOS / Android | ✅ | iOS 端侧；安卓随 ROM | ✅ |
| macOS | ✅（7.0.0 起） | 系统 | ✅ |
| Windows | ✅（7.3.0 起，**仍标 beta**，官方称未达生产可用） | 系统 | ✅ |
| Web | ✅*（仅部分浏览器） | Chrome/Edge → **Google 云端**；Safari 14.1+ 端侧 | ❌ Chrome 基本不可达 |
| Linux | ❌ **完全不支持** | — | — |

补充事实：Firefox 至 142（2025-08）才有 Web 页内识别且**默认关闭**；iOS Safari 的 `continuous=true` 存在已知缺陷——麦克风持续开启但永不返回 final text；`getUserMedia` 需安全上下文（https 或 localhost）。

## 决策

### 1. 定性：语音输入是输入法，不是 AI 能力

- **不挂 `ModelConfig`**、不新增云端 ASR 凭据、**不新增音频上传端点**——音频不出设备。
- 因此**零模型配置时语音仍可用**，与 ADR-0039 的「模型未配置」提示互不干扰（那是问答能力缺失，不是输入能力缺失）。
- 转写产物是**普通文本**，经 `_ctrl` 进入输入框后与手打文本完全同权：后续走的仍是 `assistantNotifierProvider` → `POST /api/v1/assistant/chat` 唯一链路（ADR-0036），**协议零改动**。

### 2. 能力门禁：不可用时不渲染，而不是渲染一个禁用按钮

启动时探测一次（`SpeechToText.initialize()`），结果收敛为：

```dart
enum VoiceAvailability { ready, denied, unsupported }
```

- `ready` → 麦按钮常驻输入框。
- `denied` → 麦按钮出现，点击后**引导去系统设置**（权限可恢复，按钮不该消失）。
- `unsupported` → **麦按钮根本不出现**，且不占位、不留空隙。

为什么是「不出现」而不是「禁用 + 提示」：禁用的麦克风图标会让人反复点它，把「这个平台没有语音」变成「这个 App 坏了」。这与 ADR-0039「不给一个点了才失败的入口」是同一条纪律，也与 ADR-0051「空态必须回答为什么空 + 下一步做什么」互补。

### 3. Web 与 Linux 明确不做（本 ADR 最容易被推翻、也最该被守住的一条）

| 端 | 结论 | 证据 |
|---|---|---|
| Linux | 不做 | `speech_to_text` 未实现该平台，`initialize()` 恒返 false |
| Web | **不做** | Chrome/Edge 将音频送 Google 服务器转写，本项目目标用户在中国大陆，**可达性不成立**；Safari 虽端侧可用但份额不足以支撑一条独立实现；iOS Safari `continuous` 缺陷还需额外分支 |

⚠️ 记录一条被推翻的中间判断：初稿认为「Web 还需 https，自部署走 localhost 可豁免，故 https 不是阻断项」——**这仍成立**（家庭自用场景浏览器开 `127.0.0.1` 属安全上下文豁免），但它不改变结论：Web 的唯一阻断项是「Chrome 走 Google 云端」。

**代价与退路**：用户在 Chrome 上打开 Web 版将看不到任何语音入口。若日后要覆盖 Web，正路是**后端自部署 ASR**（faster-whisper / sherpa-onnx，音频只到自家主机、不出家庭），届时另开 ADR——**不要**用「检测到 API 存在就放行」来糊，那会得到一个点了才失败的按钮。

### 4. 统一契约：三端共用同一条状态链

```
麦按钮 → 实时转写（interim 文本直接流入输入框）→ 停止 → 落草稿 → 用户发送
```

- **落草稿，绝不自动发送**。中文数学术语 ASR 错得离谱（「三分之二」/ 方程 / π），自动发送会白烧一次 LLM 往返且答非所问——对「AI 老师」的信任是一次性损耗。
- interim 文本**写进输入框本身**，不用浮层气泡：浮层会与气泡列表抢视觉焦点，且停止后还要再做一次「搬到输入框」的动作。
- 停止后焦点回输入框、光标置于末尾，可直接回车发送。
- 转写结果为空 → **不动输入框**，给一句提示，不允许静默失败。
- 录音态复用既有「激活」语义（`surfaceActive` / accent），**不新造一套颜色**。

### 5. 触发方式按端分叉——这是唯一该分叉的地方

| 端 | 触发 | 结束 | 理由 |
|---|---|---|---|
| iOS / Android | **长按说话** | 松手即停 + 上滑取消 | 微信肌肉记忆；儿童问句是短句（15–30 字），松手即停最省事 |
| macOS / Windows | **点按切换** | 再点 / 静音超时 / 错误 | 鼠标长按在触控板上别扭，且 hold 手势在桌面端没有触觉反馈，用户不知道「松早了没」 |
| Linux / Web | 不渲染 | — | 见 §3 |

### 6. 儿童静音阈值必须单独放宽

成人说「三分之二加五分之一等于多少」一气呵成；儿童会说「那个…三分之二…加…五分之一…等于多少?」。平台默认静音检测（约 1–1.5s）会在句中掐断，**语音输入对最需要它的人群反而最难用**。

- 儿童端静音阈值 **≥ 3s**；家长端沿用平台默认。
- 该值按角色（`isParent`）注入，不写死在组件里。

### 7. 孩子的纠错方式是「重说」，不是「改字」

一二年级儿童识字量有限，看到转错的「三分之二」**改不出来**——「落草稿可改」对低龄用户是伪能力。

- 停止后主行动是**「重说」**（清空草稿重新录制），输入框编辑仍在但不做主行动。
- 两端都给「重说」：成人同样受益（整句重说常常快于定位改字）。
- **不按年级分叉**：系统里没有可靠的年级判定喂给这个组件，多一条分支就要多维护一套文案。

### 8. 组件归属：`shared` 放平台能力，assistant 只做粘合

平台 STT 不属于 assistant 领域（ADR-0037 单向依赖 `main/ → features/* → shared/*`）：

- `shared/domain/voice_input.dart` — `VoiceAvailability`、`VoiceTranscript`、端口接口（纯 Dart，不 import 插件）。
- `shared/data/local/platform_speech_gateway.dart` — **唯一引入 `speech_to_text` 的文件**。
- `shared/widgets/app_voice_button.dart` — 麦按钮与录音态 UI，不知道 assistant 存在。
- assistant 侧只负责把转写结果写进 `_ctrl`。

R4 棘轮（presentation 不得 import `*/data/`）不受影响：`presentation/` 只见 domain 端口。

**入口范围收敛为助手输入框**，不铺到题库搜索 / 筛选：每多一处都要处理「门禁不可用时布局不跳」，收益不抵成本。

### 9. 文件规模：必须新开文件，不得长进 `assistant_chat_page.dart`

`assistant_chat_page.dart` 现 **557 行**，已登记在 `test/file_size_guard_test.dart` 的 `_baseline` 里（ADR-0058 棘轮，**只许下调**）。语音状态管理直接塞进去会推高该行——**违反棘轮**。

- 先把 `_InputBar` 抽出为 `features/assistant/presentation/widgets/assistant_input_bar.dart`（约 100 行，新文件远低于 400 上限）。
- 抽出后同步**下调** `_baseline` 中 `assistant_chat_page.dart` 的登记值，让棘轮停在更低的高度。
- 顺带把语音状态放进新文件，主页面不新增一个字段。

### 10. 权限声明：打补丁脚本（不把平台目录纳入版本控制）

所需声明：iOS/macOS 的 `NSMicrophoneUsageDescription` + `NSSpeechRecognitionUsageDescription`、
macOS entitlements 的 `com.apple.security.device.audio-input`、Android 的 `RECORD_AUDIO`。

⚠️ **macOS 的 `audio-input` 是硬需求不是可选优化**：本项目 `com.apple.security.app-sandbox`
为 `true`，沙盒下缺这一项麦克风在系统层直接被拒，**且不抛任何错误**。

难点在 `frontend/.gitignore` 第 20–25 行忽略 `android/ ios/ macos/ web/ windows/ linux/`
——平台目录全是本机生成物，本机加的 Info.plist 条目换机器 `flutter create` 即回退，
CI 也构建不出来。

**决策：打补丁脚本**（而非把平台目录纳入版本控制——那会把大量 Flutter 生成的样板
文件拖进仓库，每次升级 SDK 都是一片噪声 diff）。落地为
`frontend/scripts/patch_voice_permissions.py`：

- **幂等**，可反复运行；缺才补、值不同才改。
- 平台目录不存在时 `[skip]` 而不是报错（只做 Android 的机器上没有 `macos/`）。
- **`--check` 模式**：只检查不写入，缺项时退出码 1。这是给 CI / 构建前自检用的——
  原生权限缺失的失效方式是静默的（门禁判 `unsupported` → 麦按钮不渲染 → 界面零异常），
  `--check` 把它变成一条会失败的检查。
- 使用说明已写入 `CONTRIBUTING.md` §平台目录补丁，并从 `AGENTS.md` 的已知风险段指向那里。

实测（2026-10-06，本机）：`--check` 识别出 7 项缺失并退 1；补齐后二次运行 7 项全部
`[ok]`、`--check` 退 0；Android manifest 经 `ElementTree` 校验，`uses-permission` 位于
`<manifest>` 直接子元素、`<application>` 之外。

## 不做的事

- ❌ TTS（语音朗读回答）——本 ADR 只覆盖输入侧。
- ❌ 云端 ASR / 音频上传端点 / `ModelConfig` 能力字段。
- ❌ 声纹识别、说话人区分（判断「这是孩子还是家长在说话」）。
- ❌ 语音指令（「帮我出五道题」以外的控制语义）走独立通道——语音产物一律是文本，指令解析仍由后端路由（ADR-0054）负责。

## 影响

- **新增依赖**：`speech_to_text: ^7.4.0`（唯一新增运行时依赖）。ADR-0044 曾因 `flutter_animate` 只经 shadcn_ui 传递引入而显式声明，本条同理：插件必须在 `pubspec.yaml` 显式声明。
- **后端**：零改动。
- **协议**：零改动（`POST /api/v1/assistant/chat` 不变，无新 kind、无新 action target）。
- **测试**：`shared/data/local/platform_speech_gateway.dart` 用端口 fake 覆盖门禁三态；`assistant_input_bar` 覆盖「落草稿不自动发送」「重说清空」「转写为空不动输入框」三条契约。

## 待定

- Windows 是否纳入（插件官方标注 beta）。§10 的平台目录问题已由补丁脚本解决，Windows 只剩「插件 beta」这一个顾虑，可独立决定。
- 儿童静音阈值 3s 需真机实测校准，可能随年级再分档。

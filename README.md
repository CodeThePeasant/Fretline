# Fretline — Guitar Solo → TAB for macOS

原生 macOS 应用：导入干净的吉他 Solo / Guitar Stem，在本机识别音高与时间，再为整句旋律优化六线谱指法。SwiftUI 界面 + 独立 Python / pYIN 分析引擎，不调用 LLM，不上传音频。

## 直接使用

自行构建后的应用位于 `dist/Fretline.app`。双击打开；也可以将它复制到“应用程序”。完整包包含 Python 运行时、音频分析依赖和 FFmpeg，使用时无需另外安装 Python。Git 仓库仅包含源码与原创合成示例，不包含安装包、用户歌曲或本地评估结果。

运行打包脚本后生成磁盘镜像：`dist/Fretline-0.1.0-arm64.dmg`。打开后将 Fretline 拖到 Applications 即可。

- 系统要求：macOS 14 或更高。
- 本次构建目标：Apple Silicon / arm64；Intel 版本需在 Intel Mac 上重新构建并验证。
- 本地开发签名，不是 Developer ID 公证发布版本，尚未提交 App Store。
- 点“体验示例”会对附带的原创合成拨弦 WAV **真正运行识别**，并非展示预设 TAB。
- 第一次识别需要初始化 numba / pYIN，可能较慢；后续使用本机缓存。

## 已实现

1. 通过系统文件选择器导入 WAV、AIFF、MP3、FLAC，最长 180 秒、250 MB。
2. FFmpeg 解码为 44.1 kHz 单声道 WAV，内部使用 Float32；归一化后在 22.05 kHz 进行音高分析。
3. pYIN 基频与置信度、起音检测、短时音高平滑、重复拨弦切分、短片段过滤。
4. 标准 EADGBE、24 品指板候选枚举。
5. 基于 `(弦, 品, 手部把位)` 的 Viterbi / 动态规划全局路径，包含换把、换弦、品位移动和把位偏好代价；支持均衡、易弹、固定把位模式。
6. 波形拖动定位、音频播放、六线谱高亮跟随与自动滚动、0.5× / 0.75× / 1× / 1.25× 速度、整段循环。
7. 点选音符，切换并锁定弦 / 品，半音修正、起始时间和时值修正、删除、撤销。重新优化保留锁定指法。
8. `.guitartab` 项目包保存 / 打开（包含独立音频副本）、TXT 六线谱及 JSON 数据导出。
9. 低置信度提示、静音 / 无效音频 / 过长音频报错、可取消分析、未保存更改提示。

## 本地开发

需要 Xcode Command Line Tools、Python 3.11 和 [uv](https://docs.astral.sh/uv/getting-started/installation/)。首次安装依赖需要网络，识别阶段不需要网络。

```bash
git clone https://github.com/CodeThePeasant/Fretline.git
cd Fretline
./scripts/setup.sh
swift run GuitarTab
```

在 Xcode 中直接打开 `Package.swift` 也可以运行。开发态会寻找项目里的 `engine/.venv/bin/python`，可以使用 `GUITARTAB_ENGINE_HOME` 指向其他引擎目录。

### 构建完整 App

```bash
./scripts/build-app.sh
open dist/Fretline.app
# 可选：生成包含 Applications 快捷方式的安装镜像
./scripts/package-dmg.sh
```

脚本先编译 Swift release，再通过 PyInstaller 将 Python、librosa、numba、SciPy 和 FFmpeg 打包到 App Resources，最后进行本地 ad-hoc 签名。构建依赖固定在 `engine/uv.lock`。

### 验证

```bash
# 如果默认 xcode-select 指向 CommandLineTools，测试时指定完整 Xcode：
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
cd engine
uv run --frozen pytest -q

# CLI 端到端：stdout 为 JSON Lines，stderr 为诊断信息
uv run --frozen python cli.py ../examples/demo-solo.wav --output /tmp/fretline-playback.wav
```

Swift 测试检查完整音域映射、锁定约束、非法输入、动态规划与穷举最优解的一致性、项目读写覆盖和六线谱导出。Python 测试检查重复音起音、抖动合并、静音拒绝，以及谐波拨弦音频的音高 / 时间识别。合成音频测试不代表真实 Solo 的识别准确率；尚未用人工标注真实吉他数据集评估。

## 架构

```text
SwiftUI / AppModel
  ├─ 文件导入 → EngineRunner → 本地子进程 cli.py
  │                            └─ FFmpeg → pYIN → onset / note tracking
  ├─ AnalysisResult → FingeringEngine → GuitarNote[]
  ├─ AVAudioPlayer → 时间轴 / 波形 / TAB 同步
  └─ ProjectStore / TabExporter → .guitartab / JSON / TXT
```

```text
Sources/GuitarTab/
  GuitarTabApp.swift         应用入口、菜单与快捷键
  AppModel.swift             分析 / 编辑 / 播放状态
  Core/
    Models.swift             结构化音符与项目模型
    FingeringEngine.swift    指板映射与全局指法优化
    EngineRunner.swift       子进程 JSON Lines 通信、取消与错误
    ProjectStore.swift       带音频的项目包，原子替换保存
    TabExporter.swift        ASCII TAB 与精确时间列表
  Views/                     SwiftUI 工作台、波形、TAB、音符检查器
engine/
  guitartab/transcribe.py    预处理、pYIN 和音符追踪
  cli.py                    命令行入口
  tests/                    音频与追踪测试
Tests/GuitarTabTests/        指板、优化器、项目存储测试
examples/                   原创合成示例音频与 ground truth
scripts/                    安装、构建、图标与示例生成
```

项目包内为 `project.json` 与 `audio.wav`。JSON 使用 MIDI 音高、秒数起始 / 时值、1–6 弦编号（1 弦为高音 e）、0–24 品、置信度、幅度和锁定标记。单独导出的 JSON 不包含音频；需要完整可恢复项目时选择“保存项目”。

**原需求音高示例修正**：标准调弦 E4 / MIDI 64 对应 `1/0, 2/5, 3/9, 4/14, 5/19, 6/24`；`1/12` 是 E5 / MIDI 76。

## 当前边界

- 面向干净单音音轨；不提供混音分离、复音和弦识别、自动调弦 / Capo、自动演奏技巧识别。
- pYIN 是概率音高跟踪算法，不是训练完成的吉他专用神经转录模型。失真、泛音、推弦、滑音和快速连奏可能造成八度错误、漏音或错误切分。
- 六线谱按音符事件排列，显示每个起音的秒数；波形和播放器使用真实时间。TXT 附精确时间列表，不宣称已完成节拍 / 拍号 / 符尾排版。
- 没有 MusicXML、Guitar Pro、MIDI 或五线谱导出；这些属于后续阶段。
- “固定把位”是软偏好；优化器可以在必要时移位。四品手型窗口是近似模型，不能保证还原演奏者的原始指法。
- 已完成的工程不是商店发布版本。分发给其他电脑前仍需目标机器验证、Developer ID 签名与公证。
- 导入的原始文件不会被更改；未保存的播放副本和诊断日志位于系统临时目录，JIT 缓存位于 `~/Library/Caches/GuitarTab/numba`。

## 参考

- [Apple AVAudioPlayer](https://developer.apple.com/documentation/avfaudio/avaudioplayer)：原生音频播放。
- [Apple SwiftUI Canvas](https://developer.apple.com/documentation/swiftui/canvas)：波形绘制。
- [librosa 源码与文档](https://github.com/librosa/librosa)：pYIN、音频与起音分析。
- [PyInstaller](https://pyinstaller.org/en/stable/)：本地分析引擎打包。

第三方组件保留其各自许可证；FFmpeg 二进制由 imageio-ffmpeg 提供，分发前应审阅其构建配置和对应许可证。

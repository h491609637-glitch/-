# LingoLearn

基于 `SwiftUI + SwiftData + Swift Charts` 的 iOS 背单词应用。

## 技术栈
- Swift 5.9
- SwiftUI
- SwiftData
- Swift Charts
- AVFoundation (系统 TTS)

## 已实现功能
- 首页：今日环形进度、连续打卡、待复习角标、快捷入口（开始学习/快速复习/随机测试）
- 单词学习：
  - 卡片正反面（英文+音标 / 中文+例句+中文例句翻译）
  - 点击 3D 翻转
  - 左滑不认识、右滑认识、上滑收藏
  - 拖拽倾斜与颜色反馈
  - 喇叭播放发音（系统 TTS）
  - 每轮统计弹窗
  - SM-2 自动复习调度
- 练习测试：
  - 选择题 / 填空题 / 听力题
  - 词书图片卡片选择（CET4 / CET6 / TOEFL Core / TOEFL Full）
  - 倒计时进度条（可在设置中配置每题时间）
  - 每轮题数可调整（5-60）
  - 答对对勾动画、答错抖动动画
  - 结束页展示正确率、用时、错题回顾
- 学习进度：
  - 近 7/30 天折线图
  - GitHub 风格热力图
  - 词汇掌握度饼图
  - 成就徽章墙 + 解锁提示动画
- 设置：
  - 每日目标（10-100）
  - 当前词书切换（图片卡片：CET4 / CET6 / TOEFL Core / TOEFL Full）
  - 学习提醒开关 + 时间
  - 音效、震动、自动发音开关
  - 外观（系统/浅色/深色）
  - 重置学习进度（二次确认）

## 预置词库
- 文件：`LingoLearn/Resources/SeedWords.json`
- 唯一词条数：`6346`
- 词书覆盖：
  - `CET4`：1500
  - `CET6`：1500
  - `TOEFL Core`：2300
  - `TOEFL Full`：5600

> 词库来自 `kajweb/dict` 的 CET4 / CET6 / TOEFL 词书数据并做统一清洗，保留中文释义、音标和例句。  
> `TOEFL Core` 为高频核心词，`TOEFL Full` 为完整词库（含 Core）。

## 运行说明
1. 使用 Xcode 打开：`LingoLearn.xcodeproj`
2. 选择 iOS 模拟器（iOS 17+）或真机
3. `Cmd + R` 运行
4. 首次启动会自动导入预置词库并初始化设置

## 托福词库一键构建
在仓库根目录运行（Mac/Linux）：

```bash
bash scripts/run_toefl_build.sh
```

说明：
- 脚本会自动创建 `.venv` 并安装 `pandas`、`requests`
- 默认执行 `--download` 并输出到 `./output`
- 如只用本地 `./data` 重新构建，可加 `--no-download`

## 目录结构
```
LingoLearn/
├── LingoLearn.xcodeproj
├── LingoLearn/
│   ├── LingoLearnApp.swift
│   ├── Assets.xcassets
│   └── Resources/
│       └── SeedWords.json
└── README.md
```

## 说明
- 主色：`#0EA5E9`
- 辅助色：`#14B8A6`
- 支持 Light / Dark Mode
- 关键交互已接入触觉反馈

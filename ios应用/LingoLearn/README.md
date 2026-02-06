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
  - 卡片正反面（英文+音标 / 中文+例句）
  - 点击 3D 翻转
  - 左滑不认识、右滑认识、上滑收藏
  - 拖拽倾斜与颜色反馈
  - 喇叭播放发音（系统 TTS）
  - 每轮统计弹窗
  - SM-2 自动复习调度
- 练习测试：
  - 选择题 / 填空题 / 听力题
  - 倒计时进度条（可在设置中配置每题时间）
  - 答对对勾动画、答错抖动动画
  - 结束页展示正确率、用时、错题回顾
- 学习进度：
  - 近 7/30 天折线图
  - GitHub 风格热力图
  - 词汇掌握度饼图
  - 成就徽章墙 + 解锁提示动画
- 设置：
  - 每日目标（10-100）
  - 学习提醒开关 + 时间
  - 音效、震动、自动发音开关
  - 外观（系统/浅色/深色）
  - 重置学习进度（二次确认）

## 预置词库
- 文件：`LingoLearn/Resources/SeedWords.json`
- 条目数：`520`
- 分类：`CET4` + `CET6`

> 词库来自公开英文高频词表并进行本地转换，已包含分类字段与示例句结构，可继续替换为更权威的 CET 词表。

## 运行说明
1. 使用 Xcode 打开：`LingoLearn.xcodeproj`
2. 选择 iOS 模拟器（iOS 17+）或真机
3. `Cmd + R` 运行
4. 首次启动会自动导入预置词库并初始化设置

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

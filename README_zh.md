# Save Rewinder

[English](README.md) | 简体中文

**撤销失误，自由探索，永不丢失进度。**

Save Rewinder 在你游玩小丑牌时自动创建存档点，让你可以一键回溯到任意最近时刻。

## 为什么使用这个 Mod？

- 🎯 **撤销失误** — 不小心弃错牌了？回退重来
- 🧪 **自由尝试** — 测试各种策略，无需担心后果
- 📸 **自动快照** — 每当游戏保存时自动创建存档（选盲注、出牌/弃牌、商店等）
- ⚡ **即时恢复** — 按 `S` 键回退一步，无需繁琐手动SL
- 🔄 **反悔回退** — 回退太多了？被回退的存档会一直保留在列表中，直到你进行新的操作
- 🎮 **完整手柄支持** — 支持回退、打开存档列表

## 截图

| 存档按钮 | 存档列表（盲注图标） |
|:---:|:---:|
| ![存档按钮](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/存档列表游戏内菜单按钮.jpeg) | ![盲注图标](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/存档列表（显示盲注图标）.jpeg) |
| **存档列表（回合数）** | **Mod设置** |
| ![回合数](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/存档列表（显示回合数）.jpeg) | ![设置](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/Mod设置选项.jpeg) |

## 快速开始

### 安装

1. 为 Balatro 安装 [Steamodded](https://github.com/Steamopollys/Steamodded)
2. 从 [Releases](../../releases) 页面下载最新版本 (`SaveRewinder-[版本号].zip`)
3. 解压后将 `SaveRewinder` 文件夹（不是 SaveRewinder-[版本号]）放入游戏的 `Mods` 文件夹
4. 启动 Balatro — 可以在 Mod 列表中看到 **Save Rewinder**

### 操作方式

| 操作 | 键盘 | 手柄 |
|------|------|------|
| 回退一个存档 | `S` | 按下左摇杆 |
| 打开存档列表 | `Ctrl+S` | 按下右摇杆 |
| 翻页 | — | `LB` / `RB` |
| 跳转到当前存档 | — | `Y` |

### 游戏内菜单

打开**选项**菜单并点击**橙色"存档列表"按钮**，或按 `Ctrl+S`（或按下右摇杆）：
- 点击任意存档进行恢复
- 橙色高亮显示当前存档
- 使用"当前存档"按钮回到当前存档

## 配置选项

在 Steamodded 的 Save Rewinder 配置菜单中：

**自动存档触发：**
- **切换存档点** — 选择在哪些时刻创建存档：
  - 选择盲注
  - 选牌（出牌/弃牌后）
  - 回合结束
  - 商店中

**显示选项：**
- **显示盲注图标** — 在存档列表中显示盲注图标（小/大/Boss）而不是回合数字
- **盲注图标效果** — 启用悬停动画和音效（默认关闭）

**高级设置：**
- **限制存档数量** — 只保留最近几个底注的存档（1、2、4、6、8、16 或全部；默认：4）
- **调试：详细日志** — 显示详细的存档操作日志
- **删除全部** — 清除当前游戏的所有存档

## 存档位置

存档保存在以下存档文件夹中：
```
[Balatro 路径]/[存档]/SaveRewinder/
```

- **`.jkr` 文件** — 实际的存档数据，命名格式为 `<ante>-<round>-<时间戳>.jkr`
- **`.meta` 文件** — 用于加速加载的元数据缓存

> ⚠️ **注意**：存档仅保留**当前游戏**。即使中途退出游戏，存档也会保留 — 重新打开游戏并继续运行时，所有存档仍然可用。开始**新游戏**会删除所有之前的存档。

## 语言支持

- English
- 简体中文

---

> 🤖 **开发者**：使用 LLM/AI 进行开发？请查看 [`docs/AGENT.md`](docs/AGENT.md) 了解架构和设计细节。


# Save Rewinder

[English](README.md) | 简体中文

**撤销失误，自由探索，永不丢失进度。**

Save Rewinder 在你游玩小丑牌时自动创建存档点，让你可以一键回溯到任意最近时刻。

-  **自动快照** — 自动记录每个关键时刻（选盲注、出牌、商店）。
- ⚡ **即时撤销** — 按 `S`（键盘）或 `L3`（手柄）立即回退。
- 🔁 **快速读档** — 按 `L`（键盘）或 `R3`（手柄）立即重载。
- 🧪 **自由实验** — 放心尝试策略，所有历史存档都会安全保留。
- 🎮 **完整手柄支持** — 专属导航和独立键位绑定。

## 截图

| 存档按钮 | 存档列表（盲注图标） |
|:---:|:---:|
| ![存档按钮](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/存档列表游戏内菜单按钮.jpeg) | ![盲注图标](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/存档列表（显示盲注图标）.jpeg) |
| **存档列表（回合数）** | **Mod设置** |
| ![回合数](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/存档列表（显示回合数）.jpeg) | ![设置](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/Mod设置选项.jpeg) |

## 安装

1. 为 Balatro 安装 [Steamodded](https://github.com/Steamopollys/Steamodded)
2. 下载并解压[最新版本](https://github.com/Liafonx/Balatro-SaveRewinder/releases) — 其中包含一个 `SaveRewinder` 文件夹
3. 将 `SaveRewinder` 文件夹复制到游戏的 `Mods` 文件夹中
4. 启动 Balatro — 可以在 Mod 列表中看到 **Save Rewinder**

> ⚠️ **重要**：确保 `Mods/SaveRewinder/` 中直接包含模组文件（如 `main.lua`），而不是另一个嵌套的 `SaveRewinder` 文件夹。

> 📦 **Thunderstore 用户**：文件位于 zip 根目录。创建 `Mods/SaveRewinder/` 并将所有文件解压到其中。最终结构：`Mods/SaveRewinder/main.lua`。

## 快速开始

### 操作方式

| 操作 | 键盘（默认） | 手柄（默认） |
|------|------|------|
| 回退一个存档（可更改） | `S` | 按下左摇杆（L3） |
| 快速读档（可更改） | `L` | 按下右摇杆（R3） |
| 打开存档列表（可更改） | `Ctrl+S` | `X`（仅限暂停菜单） |

> **提示**：打开**选项**菜单点击**橙色"存档列表"按钮**（或按 `Ctrl+S` / `X`）即可浏览并恢复任意存档。

## 配置选项

在 Steamodded 的 Save Rewinder 模组菜单中可设置：

- 选择保存时机（盲注、出牌、回合结束、商店）。
- 切换盲注图标显示与动画效果。
- 设置保留的底注数量（默认：4）。
- 分别自定义键盘和手柄的按键。

## 存档位置

存档存储在 `[Profile]/SaveRewinder/`。

> ⚠️ **注意**：存档仅保留**当前游戏**，开始**新游戏**会清空旧存档。中途退出并继续游戏时历史记录会保留。

## 语言支持

- English
- 简体中文

---

> 🤖 **开发者**：使用 LLM/AI 进行开发？请查看 [`docs/AGENT.md`](docs/AGENT.md) 了解架构和设计细节。

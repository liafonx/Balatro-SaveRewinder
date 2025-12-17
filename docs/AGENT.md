# FastSaveLoader 项目说明文档

> 基于工程笔记（A.md）与 Agent 设计文档（AGENT.md）整理的综合说明。

---

## 1. 项目目标与整体功能

**FastSaveLoader** 是一款面向 *Balatro* 的存档/回溯 Mod，核心目标是：

- 在游戏过程中自动生成多份存档（按 Ante 轮次时间线排序）；
- 允许玩家从任意存档点恢复当前 run，相当于提供「撤销 / 步进回退」功能；
- 提供存档列表 UI、快捷键等交互能力；
- 在性能与稳定性上尽量无感运行，并与其他主流 Mod（如 `Steamodded`, `debugplus` 等）兼容。

---

## 2. 项目结构与目录说明

### 2.1 核心脚本文件（逻辑层）

> 以下均为 Mod 的 Lua 脚本，负责备份逻辑、输入、UI 等。文件已按功能模块组织到不同文件夹中。

#### Core/ - 核心功能模块

- **`Core/Init.lua`**  
  - Mod 的入口点，负责加载核心模块并设置全局 `LOADER` 命名空间。  
  - 加载 `StateSignature` 和 `SaveManager` 模块。  
  - 将模块功能导出到 `LOADER` 命名空间，供其他脚本使用。  
  - 提供统一的 `debug_log` 函数，支持标签分类和配置开关。  
  - 在游戏启动时**同步**预加载存档列表与元数据（包含 `action_type` 检测），保证打开存档 UI 时不会再触发额外的 `.meta` 读取或 `.jkr` 解包。  
  - 提供 `show_save_debug` 函数，用于显示存档通知的 UI 提示框。  

- **`Core/StateSignature.lua`**  
  - 状态签名模块，用于分析和比较游戏状态。  
  - 核心函数：
    - `get_signature(run_data)`：根据 **Ante, Round, State, is_opening_pack, action_type, Money, discards_used, hands_played** 生成状态指纹。  
    - `encode_signature(sig)`：将签名编码为紧凑字符串（格式：`"ante:round:state:action_type:money"`）用于快速比较。  
    - `signatures_equal(a, b)`：先比较编码字符串，再回退到详细比较。  
    - `describe_signature(sig)`：生成人类可读的状态描述。  
    - `get_label_from_state(state, action_type, is_opening_pack)`：根据状态、动作类型和是否开包生成标签（如 "opening pack", "selecting hand (play)", "start of round"）。  
    - `is_shop_signature(sig)`：判断是否为商店状态。  

- **`Core/SaveManager.lua`**  
  - 存档管理的核心模块，负责存档的创建、加载、列表、修剪等所有操作。  
  - 维护内部状态：
    - `current_index`、`pending_index`：当前存档索引  
    - `pending_future_prune`：待清理的「未来」存档列表  
    - `skip_next_save`：是否跳过下一次存档  
    - `_last_loaded_file`：最后加载的存档文件（用于 UI 高亮）  
    - `save_cache`：内存中的存档列表缓存（数组结构，使用索引常量访问）  
    - `save_cache_by_file` / `save_index_by_file`：文件名到 entry/索引的映射（在 reload / prune / retention 后重建，用于快速查找）。  
  - 核心函数：
    - `create_save(run_data)`：创建存档文件（序列化、压缩、写入文件系统）。  
      - 支持配置过滤（`save_on_blind`, `save_on_selecting_hand`, `save_on_round_end`, `save_on_shop`）。  
      - 通过 `ActionDetector` 模块检测动作类型（play/discard）。  
    - `load_and_start_from_file(file)`：加载存档并重启游戏 run（使用 `FileIO.copy_save_to_main` 直接复制到 `save.jkr` 优化性能）。  
    - `revert_to_previous_save()`：时间线向后退一步。  
    - `load_save_at_index(index)`：按索引加载存档。  
    - `get_save_files(force_reload)`：获取存档列表（带缓存，支持强制重新加载）。  
    - `get_save_meta(entry)`：获取存档元数据（从 `.meta` 文件快速读取，或解包 `.jkr` 文件）。  
    - `preload_all_metadata(force_reload)`：同步加载所有 entry 的元数据，并执行 `ActionDetector.detect_action_types_for_entries`。  
    - `get_entry_by_file(file)` / `get_index_by_file(file)`：基于内存映射快速定位 entry/索引。  
    - `mark_loaded_state(run_data, opts)`：记录刚加载的存档状态。  
    - `consume_skip_on_save(save_table)`：在写存档前判断是否执行本次存档（包括 Shop/Pack Open 特例逻辑）。  
    - `clear_all_saves()`：删除所有存档。  
  - 文件命名格式：`<ante>-<round>-<unique_timestamp>.jkr`  

- **`Core/GamePatches.lua`**  
  - 提供游戏函数的覆盖和补丁。  
  - `Game:start_run` 覆盖：
    - 标记加载状态（调用 `mark_loaded_state`）。  
    - 加载 Shop 存档时：将尚未实例化的 `shop_*` CardArea 预先写入 `G.load_shop_*` 并从 `cardAreas` 移除，避免原版打印 `ERROR LOADING GAME: Card area ... not instantiated before load` 噪音日志；后续由原版 `Game:update_shop` 加载。  
    - 重置新 run 的状态，清理旧存档（新 run 时）。  
  - `LOADER.defer_save_creation()`：
    - 使用 `Utils.deepcopy` 对 `G.culled_table` 进行深拷贝。  
    - 使用 `G.E_MANAGER` 将 `SaveManager.create_save` 调度到**下一帧**执行。  

#### Utils/ - 工具模块

- **`Utils/Utils.lua`**  
  - 共享工具函数。  
  - `deepcopy(orig)`：深拷贝表结构，用于安全传递存档数据。  

- **`Utils/EntryConstants.lua`**  
  - 定义缓存条目数组索引常量。  
  - 缓存条目使用数组结构而非键值表，减少内存占用。  
  - 常量：`ENTRY_FILE`, `ENTRY_ANTE`, `ENTRY_ROUND`, `ENTRY_INDEX`, `ENTRY_MODTIME`, `ENTRY_STATE`, `ENTRY_ACTION_TYPE`, `ENTRY_IS_OPENING_PACK`, `ENTRY_MONEY`, `ENTRY_SIGNATURE`, `ENTRY_DISCARDS_USED`, `ENTRY_HANDS_PLAYED`, `ENTRY_IS_CURRENT`。  

- **`Utils/MetaFile.lua`**  
  - 处理 `.meta` 文件的读写操作。  
  - `read_meta_file(meta_path)`：从 `.meta` 文件快速读取元数据（避免解包 `.jkr` 文件）。  
  - `write_meta_file(meta_path, entry_meta)`：将元数据写入 `.meta` 文件。  
  - `.meta` 文件格式：简单的 `key=value` 键值对，每行一个。  

- **`Utils/FileIO.lua`**  
  - 文件 I/O 操作。  
  - `get_profile()`：获取当前游戏配置档案。  
  - `get_save_dir(saves_path)`：获取存档目录路径。  
  - `copy_save_to_main(file, save_dir)`：直接将存档文件复制到 `save.jkr`（快速路径，无需解码）。  
  - `load_save_file(file, save_dir)`：加载并解包存档文件。  
  - `sync_to_main_save(run_data)`：将存档数据同步到主 `save.jkr` 文件。  

- **`Utils/ActionDetector.lua`**  
  - 动作类型检测逻辑。  
  - `detect_action_type(entry, sig, save_cache, get_save_meta_func, entry_constants)`：检测单个条目的动作类型（play/discard）。  
  - `detect_action_types_for_entries(entries, save_cache, get_save_meta_func, entry_constants)`：批量检测所有 `SELECTING_HAND` 条目的动作类型。  
  - 通过比较 `discards_used` 和 `hands_played` 值的变化来判断动作类型。  

- **`Utils/CacheManager.lua`**  
  - 缓存条目标志管理和当前文件追踪。  
  - `set_cache_current_file(save_cache, file, entry_constants, last_loaded_file_ref)`：更新指定文件的当前标志（高效路径）。  
  - `update_cache_current_flags(save_cache, last_loaded_file_ref, entry_constants)`：更新所有缓存条目的 `is_current` 标志。  
  - 优先级：`_last_loaded_file` > `G.SAVED_GAME._file` > `save.jkr`。  

- **`Utils/Pruning.lua`**  
  - 存档修剪逻辑。  
  - `apply_retention_policy(save_dir, all_entries, entry_constants)`：根据配置的 `keep_antes` 应用保留策略，删除旧 Ante 的存档。  
  - `prune_future_saves(save_dir, pending_future_prune, save_cache, entry_constants)`：删除「未来」时间线的存档（分支清理）。  

- **`Utils/DuplicateDetector.lua`**  
  - 重复存档检测逻辑。  
  - `should_skip_duplicate(sig, last_save_sig, last_save_time, current_time, StateSignature)`：检查是否应跳过重复存档。  
  - 处理相同签名的快速重复保存（< 0.5 秒）和「结束回合」状态的重复保存（< 1 秒）。  

#### UI/ - 用户界面

- **`UI/LoaderUI.lua`**  
  - 构建并渲染存档列表 overlay。  
  - `G.UIDEF.fast_loader_saves()`：主 UI 定义函数。  
  - `build_save_node()`：构建单个存档项的 UI 节点（带高亮当前存档）。  
    - 根据奇偶轮次为分隔符点着色（提高可读性）。  
    - 显示动作类型（如 "Selecting Hand (Play)" 或 "Selecting Hand (Discard)"）。  
    - 对于有动作的 "selecting hand" 状态，显示 `discards_used` 或 `hands_played` 作为尾随数字。  
    - "start of round" 和 "end of round" 不显示序号后缀。  
  - `get_saves_page()`：分页逻辑，支持每页显示 8 个存档。  
  - `get_round_color(round)`：根据轮次奇偶性返回颜色（用于分隔符点）。  
  - 注入「Saves」按钮到游戏内 Options 菜单。  

- **`UI/ButtonCallbacks.lua`**  
  - 绑定 UI 中按钮操作：
    - `loader_save_restore`：加载选中的存档。  
    - `loader_save_update_page`：切换分页（更新存储的 `cycle_config` 引用）。  
    - `loader_save_jump_to_current`：跳转到当前存档所在页（使用存储的 `cycle_config` 引用）。  
    - `loader_save_delete_all`：删除所有存档。  
    - `loader_save_reload`：强制刷新存档列表。  
  - 打开存档列表时将手柄焦点吸附到当前存档项，保证初始高亮与导航稳定。  

#### 根目录文件

- **`Keybinds.lua`**  
  - 重载 `love.keypressed`，注册快捷键：
    - `S`：时间线向后退一步（调用 `revert_to_previous_save`）。  
    - `Ctrl+S`：在游戏中打开/关闭存档列表 UI 覆盖层。  
  - 手柄支持：
    - `L3`：等同 `S`（回退一步）。  
    - `R3`：等同 `Ctrl+S`（打开/关闭存档列表）。  
    - 覆盖 `Controller:navigate_focus`，为存档列表 overlay 设置明确的方向边界与循环规则（含存档条目左右翻页）。  
  - 仅在 `G.STAGE == G.STAGES.RUN` 时响应，避免在菜单中触发。  

- **`main.lua`**  
  - Mod 的配置 UI 入口（与 Steamodded 配置界面集成）。  
  - 提供配置选项：
    - `save_on_blind`, `save_on_selecting_hand`, `save_on_round_end`, `save_on_shop`：控制何时创建存档（默认 `nil` 表示启用，`false` 表示禁用）。  
    - `keep_antes`：保留多少个 Ante 的存档（1/2/4/6/8/16/All）。  
    - `debug_saves`：是否显示存档通知。  

- **`config.lua`**  
  - 默认配置值，例如：
    - 各状态下的保存开关（默认 `nil`，表示全部开启）。  
    - `keep_antes = 7`（对应 "All"）。  
    - `debug_saves = false`。  

- **`lovely.toml`**  
  - Lovely Loader 的补丁配置文件。  
  - 使用 **正则 patch** 在游戏原版 `functions/misc_functions.lua` 中，定位 `G.ARGS.save_run = G.culled_table` 的位置，并在其后插入：  
    ```lua
    if LOADER and LOADER.defer_save_creation then
       LOADER.defer_save_creation()
    end
    ```  
  - 使用 **pattern patch** 在 `card.lua` 的 `Card:open()` 函数中设置 `skipping_pack_open` 标记。  
  - 通过静态注入代替运行时 monkey-patch，减小与其他 Mod 的冲突。  
  - 注册所有模块（`Core/` 和 `Utils/` 下的模块）为 Lovely 模块，确保正确的加载顺序。  

### 2.1.5 依赖关系速览

- `Core/GamePatches.lua`：依赖 `SaveManager`（创建/加载存档）、`Utils.deepcopy`、`G.E_MANAGER`/`Event`；由 `lovely.toml` 注入触发，接管 `start_run` 与延迟保存。
- `Core/SaveManager.lua`：依赖 `StateSignature`、`EntryConstants`、`MetaFile`、`FileIO`、`ActionDetector`、`CacheManager`、`Pruning`、`DuplicateDetector`；被 `GamePatches.defer_save_creation`、UI (`LoaderUI`/`ButtonCallbacks`) 与 `Keybinds` 调用。
- `Utils/FileIO.lua`：封装 pack/压缩/写入与读取；被 `SaveManager` 复用；依赖 `love.filesystem`/`love.data`。
- `Utils/MetaFile.lua`：`.meta` 读写；被 `SaveManager` 复用。
- `Utils/ActionDetector.lua`：动作类型推断；被 `SaveManager` 复用；依赖 `EntryConstants` 和 `G.STATES`。
- `Utils/Pruning.lua`：保留/修剪策略；被 `SaveManager` 复用；依赖 `love.filesystem`。
- `Utils/DuplicateDetector.lua`：重复存档过滤；被 `SaveManager` 复用；依赖 `StateSignature`。

### 2.2 文档目录

- **`docs/`**  
  - 项目文档：
    - `AGENT.md`：本文档，项目架构和设计说明。  
    - `CACHE_ENTRY_EXAMPLE.md`：缓存条目结构示例文档。  
    - `CLICK_LOAD_FLOW.md`：点击加载流程说明文档。  

### 2.3 外部 / 参考目录

来自工程笔记中的目录说明：  

- **`lovely/`**  
  - 本地 Lovely Loader 相关文件（包括自身日志目录 `lovely/log/`）。  
  - 可用于调试补丁是否正确应用、查看崩溃信息。  

- **`Steamodded/`**  
  - Steamodded Loader 的脚本和配置，作为参考或与本 Mod 的联动环境。  

- **`balatro_src/`**  
  - 解包后的原版 Balatro 源文件，用于：
    - 查看原始函数实现（如 `save_run`, `start_run`, `functions/misc_functions.lua`）。  
    - 编写 `lovely.toml` 正则时的文本依据。  

- **`Balatro-History/`**  
  - 另一个 Mod（或版本历史）作为参考：  
    - 可查看之前如何处理备份、时间线等逻辑，方便对照演进。  

---

## 3. 核心流程与功能说明

### 3.1 存档写入流程

1. 游戏在关键节点执行原版 `save_run`：  
   - 在 `functions/misc_functions.lua` 中构造 `G.culled_table`。  
2. 通过 `lovely.toml` 静态注入的代码调用：  
   - `LOADER.defer_save_creation()`（在 `G.ARGS.save_run = G.culled_table` 之后）。  
3. `GamePatches.lua` 中的 `defer_save_creation` 函数：  
   - 对 `G.culled_table` 进行深拷贝（因为原数据是临时的）。  
   - 使用 `G.E_MANAGER` 将存档任务延后到**下一帧**执行，打断与其他 Mod 钩子共享的同步调用栈，避免递归崩溃。  
4. `SaveManager.create_save` 在下一帧被调用：  
   - 首先调用 `consume_skip_on_save` 检查是否应跳过本次存档。  
   - 检查配置过滤（`save_on_blind`, `save_on_selecting_hand`, `save_on_round_end`, `save_on_shop`）。  
   - 使用 `DuplicateDetector.should_skip_duplicate` 检查重复存档（相同签名且创建时间间隔 < 0.5 秒，或「结束回合」状态的重复保存）。  
   - 使用 `Pruning.prune_future_saves` 执行时间线修剪（删除 `pending_future_prune` 中的「未来」存档）。  
   - 使用 `ActionDetector.detect_action_type` 对于 `SELECTING_HAND` 状态检测动作类型（play/discard）。  
   - 生成唯一文件名：`<ante>-<round>-<unique_timestamp>.jkr`。  
   - 序列化、压缩并写入文件系统：`PROFILE/FastSaveLoader/<filename>.jkr`。  
   - 使用 `MetaFile.write_meta_file` 写入 `.meta` 文件以加速后续元数据读取。  
   - 更新内存缓存（`save_cache`，数组结构）并使用 `CacheManager.set_cache_current_file` 标记当前存档。  
   - 使用 `Pruning.apply_retention_policy` 应用保留策略（根据配置的 `keep_antes` 删除旧 Ante 的存档）。  

### 3.2 恢复与时间线（Timeline）管理

- **加载存档**  
  - UI 或快捷键调用 `SaveManager.load_and_start_from_file` / `load_save_at_index`：  
    1. 使用 `FileIO.copy_save_to_main` 直接将存档文件复制到 `save.jkr`（性能优化，避免重复解包）。  
    2. 调用 `FileIO.load_save_file` 解包 `save.jkr` 供 `start_run` 使用。  
    3. 设置 `run_data._file` 为存档文件名，用于后续追踪。  
    4. 计算并记录 `pending_future_prune`（所有比当前存档更新的存档文件）。  
    5. 使用 `CacheManager.set_cache_current_file` 更新缓存标志。  
    6. 调用 `G.FUNCS.start_run` 重启游戏 run。  
    7. 在 `GamePatches.lua` 的 `Game:start_run` 中标记加载状态并处理商店区域延迟加载。

- **时间线分支与修剪**  
  - 当从较旧存档加载时，`start_from_run_data` 会计算所有比当前存档更新的存档索引。  
  - 这些「未来线」存档被记录到 `pending_future_prune` 列表。  
  - **延迟修剪策略**：下次真实保存时（`create_save`），这些「未来」存档才会被删除。  
  - 这样设计允许用户在误操作后仍能「前进」到被删除前的状态（如果重新加载游戏）。  
  - 修剪时会同时更新内存缓存 `save_cache`，保持一致性。

- **`S` 快捷键：时间线步进**  
  - `revert_to_previous_save` 实现逻辑：  
    - 通过 `G.SAVED_GAME._file` 或 `_last_loaded_file` 推断当前存档索引。  
    - 若当前状态不在存档列表中（新 run 或未知状态）：加载最新存档（索引 1）。  
    - 若当前是存档：加载下一个更旧的存档（索引 +1）。  
    - 使用 `skip_restore_identical = true` 标记为「步进」而非「恢复」，影响日志输出。  
    - **延迟修剪策略**：与从列表加载相同，不会立即删除「未来」存档，而是记录到 `pending_future_prune` 列表，等到下次创建新存档时才删除。  
    - 这样设计使回退操作非破坏性，允许用户在误操作后仍能「前进」到被删除前的状态（如果重新加载游戏）。  
  - 实现「一键回退一步」体验，无需打开 UI。

### 3.3 Shop / Booster 包逻辑与跳过首次保存

**核心问题**：恢复后第一次自动保存往往是「重复存档」，需要智能跳过。  

- **状态签名 `StateSignature.get_signature`**  
  - 依赖字段：`Ante`, `Round`, `State`, `is_opening_pack`, `action_type`, `Money`, `discards_used`, `hands_played`。  
  - Money 的获取优先级：`current_round.dollars` > `game.dollars` > `game.money`。  
  - `is_opening_pack` 从 `run_data.ACTION` 直接读取（在保存前捕获，不依赖文件解码），用于标识商店状态是否有 ACTION。  
  - `action_type` 仅用于 `SELECTING_HAND` 状态，值为 "play" 或 "discard"，通过 `ActionDetector` 模块检测。  
  - `discards_used` 和 `hands_played` 从 `run_data` 中读取，用于检测动作类型。  
  - 签名编码为字符串格式：`"ante:round:state:action_type:money"`，用于快速比较。  
  - 不再使用卡牌指纹 / 数量（避免开销与易碎逻辑）。  

- **ACTION 检测**  
  - `StateSignature.get_signature` 检查 `run_data.ACTION` 是否存在且非空，设置 `is_opening_pack` 标志。  
  - ACTION 表示有 pending 操作（如打开 booster 包），会影响恢复后的行为。  
  - 对于 Shop 状态，有 ACTION 时（`is_opening_pack = true`）标签为 "opening pack"，否则为 "shop"。  

- **动作类型检测**  
  - 由 `ActionDetector` 模块处理，对于 `SELECTING_HAND` 状态，通过比较当前和上一个存档的 `discards_used` 和 `hands_played` 值检测动作类型：  
    - 如果 `discards_used` 增加 → `action_type = "discard"`。  
    - 如果 `hands_played` 增加 → `action_type = "play"`。  
  - 动作类型存储在缓存条目中（`ENTRY_ACTION_TYPE` 索引），用于 UI 显示（如 "Selecting Hand (Play)"）。  
  - 如果没有动作类型，`SELECTING_HAND` 状态显示为 "Start of round"。  

- **正常恢复后的第一次保存**  
  1. 恢复存档时，`Game:start_run` 调用 `mark_loaded_state`：  
     - 记录当前签名到 `_loaded_meta`（包含 `is_opening_pack` 和 `action_type`）。  
     - **特殊情况**：若恢复的是 Shop 状态且**没有 ACTION**（`is_opening_pack = false`），则**不跳过**下一次保存（因为游戏不会立即自动保存，下次保存是用户操作触发的，应被记录）。  
     - 否则设置 `skip_next_save = true`。  
  2. 下一次保存前，`consume_skip_on_save` 被调用：  
     - 使用 `StateSignature.signatures_equal` 比较当前签名与 `_loaded_meta`：若相同 → **跳过本次存档**。  
     - 若签名不同（一般 Money 变了）→ 继续检查 Pack Open 逻辑。  

- **Shop & Booster 特殊处理**  
  - **Pack Open 检测**：  
    - 在 `card.lua` 的 `Card:open()` 函数中通过 patch 设置 `skipping_pack_open = true` 标记。  
    - 在 `consume_skip_on_save` 中：若处于 Shop 状态、有 ACTION、且（`skipping_pack_open` 为 true 或 `cardAreas.pack_cards` 存在），则强制跳过本次存档。  
    - 这解决了「打开 Booster 包会改变 Money，但从玩家视角这是恢复流程的一部分」的问题。  
  - **商店区域延迟加载**：  
    - 恢复时，`Game:start_run` 会把商店相关的 `cardAreas`（`shop_jokers`, `shop_booster`, `shop_vouchers`, `pack_cards`）从 `savetext.cardAreas` 中剥离。  
    - 存储到 `self.load_*` 临时变量，延迟到 run 启动后再重建 `CardArea` 并加载。  
    - 这使商店恢复更加稳定，避免在恢复过程中触发游戏内部状态冲突。  
  - **Pack Opening 状态的商店区域处理**（当前存在问题）：  
    - 当恢复「opening pack」状态（Shop 状态且有 ACTION）时，商店区域（`shop_jokers`, `shop_booster`, `shop_vouchers`）应该被隐藏，只显示 pack cards。  
    - 当前实现：在 `GamePatches.lua` 中检测到 `is_opening_pack` 时，从 `cardAreas` 中移除商店区域，并在 `start_run` 后清除 `G.shop_*` 和 `G.load_shop_*`。  
    - **问题**：移除商店区域会导致游戏打印 "ERROR LOADING GAME: Card area 'shop_jokers' not instantiated before load" 错误（虽然无害，但会产生日志噪音）。  
    - **未解决的问题**：恢复 opening pack 状态时，pack opening 状态会丢失，直接显示商店界面而不是 pack opening 界面。这可能是因为：  
      - 游戏在 `start_run` 中处理 `cardAreas` 时（第 2308-2315 行），如果 `G[k]` 不存在，会设置 `G['load_'..k] = v`，这可能导致商店构建器在 ACTION 触发 pack opening 之前就创建了商店区域。  
      - 或者 ACTION 的触发时机（第 2199-2217 行，延迟 0.5 秒）与商店区域的创建时机冲突。  
    - **尝试过的解决方案**：  
      1. 完全移除商店区域 → 导致 "not instantiated" 错误，且 pack opening 状态丢失。  
      2. 保留空结构的商店区域 → 游戏可能仍会创建商店区域并显示。  
      3. 在 `start_run` 后清除 `G.shop_*` 和 `G.load_shop_*` → 仍无法阻止 pack opening 状态丢失。  
    - **需要进一步调查**：可能需要阻止商店构建器在 ACTION 存在时运行，或者调整 ACTION 的触发时机。  

---

## 4. 架构演进与设计方法

### 4.1 尝试一：运行时 Hook `save_run`（已弃用）

- 做法：  
  - 在运行中「猴子补丁」式替换全局 `save_run`：  
    - 新函数中先调用原始 `save_run`，再执行备份逻辑。  
- 问题：  
  - 其他 Mod 也会 hook 核心函数（如 `print`, `love.filesystem.getInfo` 等）。  
  - 在 `start_run` → `save_run` → 备份逻辑 → `print()` → 其他 Mod 的 hook → `start_run` → ... 形成递归，最终出现 **stack overflow 崩溃**。  

### 4.2 尝试二：静态 Patch + 延迟执行（当前架构）

- 方法：  
  1. 在 `lovely.toml` 中通过正则定位原版 `functions/misc_functions.lua` 里 `G.ARGS.save_run = G.culled_table` 的位置。  
  2. 紧接其后插入 `LOADER.defer_save_creation()` 调用。  
  3. 在 `GamePatches.lua` 中实现 `defer_save_creation`：  
     - 对 `G.culled_table` 进行深拷贝（因为原数据是临时的，会在当前帧结束后被修改或销毁）。  
     - 使用 `G.E_MANAGER:add_event` 把真正的存档创建 (`SaveManager.create_save`) 延后到下一帧执行。  
  4. `SaveManager.create_save` 直接执行文件 I/O（序列化、压缩、写入），不再依赖独立线程。  

- 优点：  
  - **消除 Hook 顺序冲突**：  
    - 不再在 Lua 运行时层面 wrap 函数，而是「编译时」（加载脚本时）把一个稳定的调用植入原始源码。  
  - **打断递归调用栈**：  
    - 存档写盘与其他 Mod 钩住的 IO 调用不再在同一同步栈上执行，从而避免无限递归导致的 stack overflow。  
  - **简化架构**：  
    - 所有逻辑集中在 `SaveManager.lua`，降低复杂度。  
  - **兼容性更好**：  
    - 几乎不依赖其他 Mod 的实现细节，也不需要串行安排 hook 顺序。  
  - **性能优化**：  
    - 数组缓存结构（使用索引常量而非键值表）减少内存开销。  
    - 签名编码为字符串实现 O(1) 比较。  
    - 加载存档时使用 `FileIO.copy_save_to_main` 直接复制，避免重复解包。  
    - `.meta` 文件缓存元数据，避免每次打开 UI 都解包所有存档。  

---

## 5. 当前已知问题与风险点

1. **缓存一致性风险**  
   - `save_cache` 在内存中维护存档列表，但文件系统操作可能在其他地方发生（如手动删除文件）。  
   - 当前实现：`get_save_files(force_reload)` 支持强制重新扫描，但 UI 默认使用缓存。  
   - 风险：如果存档文件被外部删除，UI 可能显示过时信息，直到手动刷新或重启游戏。  
   - 启动时会强制重新加载所有存档以构建完整的元数据（包括 `action_type`）。  

2. **时间线修剪的延迟性**  
   - 当从旧存档恢复时，「未来」存档不会立即删除，而是等到下次保存时才删除。  
   - 优点：允许误操作后恢复。  
   - 缺点：如果用户恢复后立即退出游戏，这些「未来」存档会残留，占用磁盘空间。  
   - 当前实现已通过 `pending_future_prune` 机制处理，但需要确保每次保存都会执行修剪。  

3. **与其他 Mod 的潜在兼容性**  
   - 通过静态 patch + 延迟到下一帧这一架构，已经解决了最严重的 stack overflow 问题。  
   - 但：
     - 若未来有 Mod 同样对 `functions/misc_functions.lua` 做大范围改写或重写 `save_run`，仍可能产生冲突。  
     - 需要在文档中清晰标注依赖点（例如对 `G.culled_table` 的假设）。  
     - `card.lua` 的 `Card:open()` patch 可能与其他修改开包逻辑的 Mod 冲突。  

4. **Shop 状态恢复的复杂性**  
   - 商店区域的延迟加载机制（剥离 `cardAreas` 到 `load_*` 变量）依赖于游戏内部 `CardArea` 的特定行为。  
   - 如果游戏版本更新或 Mod 修改了 `CardArea` 的加载逻辑，可能导致商店恢复失败。  
   - 当前实现已包含 fallback 逻辑（`G.load_pack_cards`），但可能无法覆盖所有边缘情况。  

5. **签名比较的局限性**  
   - 状态签名包含 `Ante`, `Round`, `State`, `has_action`, `Money`, `discards_used`, `hands_played`，但不包含卡牌内容。  
   - 理论上，两个不同状态的存档可能具有相同签名（例如：相同 Ante/Round/State/Money，但卡牌不同）。  
   - 当前实现通过时间戳（< 0.5 秒）的重复检测来缓解，但极端情况下仍可能出现误判。  

6. **动作类型检测的准确性**  
   - 动作类型检测依赖于 `discards_used` 和 `hands_played` 的准确追踪。  
   - 如果游戏版本更新改变了这些字段的行为，可能导致动作类型检测失效。  
   - 当前实现会在每个新轮次重置追踪变量，确保准确性。

---
## 6. 后续可改进方向（建议）

> 这部分为在现有资料基础上的推演建议，便于后续规划任务。

1. **缓存失效与刷新机制**  
   - 实现文件系统监听（如果 Love2D 支持）或定期检查存档目录的修改时间。  
   - 在 UI 打开时自动验证缓存有效性，或提供「强制刷新」按钮（当前已有 `loader_save_reload`，但可优化体验）。  
   - 考虑在每次 `create_save` 后广播事件，通知其他组件更新缓存。  

2. **改进日志文案与分级**  
   - 当前日志已使用标签系统（`[save]`, `[restore]`, `[step]`, `[filter]`, `[monitor]`, `[error]` 等），但可以进一步优化：  
     - 区分「正常跳过」（签名相同）和「特殊跳过」（Pack Open）的日志消息。  
     - 对真正的异常情况使用更高严重级别和明确标签，减少误报感。  
   - 考虑添加日志级别配置（DEBUG / INFO / WARN / ERROR），允许用户过滤噪音。  

3. **补充开发者文档**  
   - 在当前这份说明的基础上，增加：
     - 调用序列图（从 `save_run` → `defer_save_creation` → `SaveManager.create_save` 的完整链路）；  
     - 各种状态（恢复、开包、手动保存）的签名变化示例；  
     - 与常见 Mod 的兼容性说明（如已测试组合列表）。  
     - `StateSignature` 模块的详细 API 文档。

4. **可选的配置增强**  
   - 当前已有配置项：
     - `save_on_blind`, `save_on_selecting_hand`, `save_on_round_end`, `save_on_shop`：控制何时创建存档（默认 `nil` 表示启用）。  
     - `keep_antes`：保留多少个 Ante 的存档（1/2/4/6/8/16/All）。  
     - `debug_saves`：是否显示存档通知。  
   - 可考虑新增：
     - 每个 Ante 最大存档数量上限（防止单个 Ante 产生过多存档）。  
     - 全局存档总数上限（磁盘空间保护）。  
     - 存档压缩级别配置（平衡文件大小与创建速度）。  

5. **性能优化与多线程架构**  
   - 已实现：
     - `.meta` 文件缓存：`MetaFile` 模块将签名信息缓存到单独的 `.meta` 文件，避免每次打开 UI 都解包所有存档。  
     - 签名编码为字符串实现快速比较。  
     - 数组缓存结构减少内存开销。  
     - 直接文件复制（`FileIO.copy_save_to_main`）优化加载性能。  
   - 可考虑：对于 UI 分页，可以延迟加载非当前页的元数据，进一步优化启动速度。  
   - **多线程优化计划**（高优先级，建议方案）：  
     - **问题**：当前实现在游戏主线程中执行大量文件 I/O 操作，导致游戏启动和 UI 打开时出现卡顿：  
       - `get_save_files()` 在启动时强制重新加载所有存档，读取所有 `.meta` 文件或解包 `.jkr` 文件。  
       - `get_save_meta()` 为每个存档执行文件系统操作（`love.filesystem.getInfo`, `love.filesystem.read`）。  
       - 缓存构建过程（`save_cache` 的构建和更新）在主线程中同步执行。  
       - UI 打开时，需要等待所有存档元数据加载完成才能显示列表。  
     - **建议的解决方案**（仅供参考，具体实现方式待定）：将文件 I/O 和缓存构建操作移到独立线程：  
       - 使用 Love2D 的 `love.thread` 创建后台工作线程（如果 Love2D 支持且性能允许）。  
       - 后台线程负责：  
         - 扫描存档目录并读取 `.meta` 文件。  
         - 构建和更新 `save_cache`。  
         - 在需要时解包 `.jkr` 文件获取元数据。  
       - 主线程通过线程通道（`love.thread.getChannel`）与后台线程通信：  
         - 主线程发送请求（如 "refresh_cache", "get_meta", "get_file_list"）。  
         - 后台线程处理请求并发送结果。  
         - 主线程异步接收结果并更新 UI。  
     - **可能的实现细节**（待验证）：  
       - 创建 `Utils/ThreadManager.lua` 模块管理后台线程。  
       - 修改 `SaveManager.get_save_files()` 使其从线程通道获取缓存数据，而不是直接读取文件。  
       - UI 打开时显示加载状态，后台线程完成后更新列表。  
       - 保持向后兼容：如果线程不可用，回退到当前同步实现。  
     - **预期收益**（如果方案可行）：  
       - 游戏启动时不再阻塞，后台线程在后台加载缓存。  
       - UI 打开时立即显示，数据异步加载完成后更新。  
       - 减少游戏主线程的 I/O 操作，提高整体流畅度。  
     - **注意事项与限制**：  
       - Love2D 的线程间通信是异步的，需要处理竞态条件。  
       - 确保缓存更新操作的原子性。  
       - 处理线程错误和超时情况。  
       - **注意**：此方案仅为建议，实际实现前需要验证 Love2D 的线程支持情况、性能影响，以及是否与其他 Mod 兼容。可能需要探索其他优化方案，如增量加载、更激进的缓存策略等。  

6. **时间线可视化增强**  
   - 当前 UI 已支持分页和「跳转到当前」功能，已实现：
     - 根据奇偶轮次为分隔符点着色（提高可读性）。  
     - 显示动作类型（如 "Selecting Hand (Play)"）。  
     - 对于有动作的 "selecting hand" 状态，显示 `discards_used` 或 `hands_played` 作为尾随数字。  
   - 可进一步改进：
     - 在 UI 中显示存档的时间戳（相对时间，如「2 分钟前」）。  
     - 显示存档文件大小，帮助用户判断哪些存档占用空间较大。  

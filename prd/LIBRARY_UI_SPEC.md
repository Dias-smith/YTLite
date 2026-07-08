YTLite: Library & History Tab UI/UX Architectural Specification

## 0. 产品决策（已确认）

| 决策 | 说明 |
|------|------|
| 设计范式 | 严格 YT Music 视觉/交互（Chips、List/Grid、FAB、BottomSheet） |
| 主页数据 | **默认仅本地**；登录后 **YouTube** 作为独立 Chip |
| Albums Chip | **暂不展示**（无 album 数据实体） |
| Start mix | **置灰**，标注 Coming soon |
| 旧底部菜单 | Your videos / Movies / Help 等 **已移除**，改由 Chips + 统一列表承担 |

## 0.1 非目标

- Shorts 媒体库
- YouTube 云端观看历史同步（API 不可用）
- 真·音乐专辑浏览
- 离线下载（Downloads Chip 展示空状态，功能未实现）

## 0.2 UI 术语 → 数据语义映射

| UI Chip / 文案 | 数据语义 | 数据源 |
|----------------|----------|--------|
| 默认（无 Chip） | 本地混合流（歌单 + 曲目 + 艺术家按 Recent activity 合并） | Room LOCAL |
| Playlists | 本地歌单（含 favorites / watch_later 系统歌单） | Room LOCAL |
| Songs | 去重本地曲目（各歌单内 track） | Room LOCAL |
| Artists | 播放过的频道（ArtistEntity） | Room LOCAL |
| Downloads | 空状态占位 | 未实现 |
| YouTube | 登录后 YouTube 只读歌单 | DataSource.YOUTUBE |
| History 页 | 仅 YTLite 本地历史，按月分组 | user_track_last_played |

## 0.3 账号态矩阵

| 状态 | 默认流 | YouTube Chip | 空状态 |
|------|--------|--------------|--------|
| Guest | 本地 | 隐藏 | Songs: Find music |
| Authenticated | 本地 | 可见 | YouTube 无歌单时显示引导 |

## 0.4 导航路由

```
MainTab.Library
  ├─ LibraryScreen（主页）
  ├─ HistoryScreen（钟表图标）
  └─ PlaylistDetailScreen（playlist/{id}）
```

## 1. 核心屏幕层级与路由 (Screen Hierarchy & Navigation)

媒体库模块由三个核心 Compose 页面及两个动态 BottomSheet 组成：

LibraryScreen (主页): 支持顶部 Filter Chips、排序下拉菜单、列表 (List) / 双列网格 (Grid) 视图切换、+ New 悬浮按钮 (FAB)。

HistoryScreen (历史): 通过顶部“钟表”图标进入，内容按时间跨度（如“June 2026”）纵向分组聚合。**仅 YTLite 本地历史**；顶部可展示 YouTube 历史不可用说明 Banner。

PlaylistDetailScreen (歌单详情): 包含大图大字头、快门式控制区、二级分类标签以及歌曲列表。

Action BottomSheets (底部菜单): 分别用于“歌单资产操作”与“单曲条目操作”。

## 2. 界面细化设计与低端机同构实现规范

### 2.1 主页：TopBar 与动态过滤器 (Library Home)

元素设计 (参考官方音乐布局):

顶部标头 Text("Library")，右侧并列放置 HistoryIcon（倒针钟表）与 ProfileIcon（打开 AccountSwitcherSheet）。

水平滚动 Chip 组: Playlists, Songs, Artists, Downloads；登录后追加 **YouTube** Chip。**Albums 暂不展示。**

交互状态机逻辑:

当未选中任何 Chip 时，展示**仅本地**混合流列表（不含 YouTube 歌单）。

当点击某 Chip 时，该 Chip 变成高亮选中状态，并在最左侧激活动态 "清除 (X)" 按钮。

空状态处理: 当选中 "Songs" 且本地无数据时，渲染居中音乐图标、引导文本及原生大按钮 "Find music"。

### 2.2 主页：控制栏与多视图同构 (List/Grid View Switcher)

控制元素:

左侧：排序文本下拉框（展示 "Recent activity" 或 "Recently saved"）。

右侧：视图切换开关。点击可在 列表流 (Single-Column List) 与 网格流 (2-Column Grid) 之间切换。

低端机图形优化性能约束:

列表状态下: 使用 LazyColumn 渲染。

网格状态下: 使用 LazyVerticalGrid(GridCells.Fixed(2)) 渲染。

核心约束: 无论是 Grid 还是 List，内部的 Item 数据结构（LibraryItem）必须完全同构，且必须显式声明 key = { it.id }。LazyListState 不可跨 List/Grid 共享；切换时允许滚动位置重置。

### 2.3 歌单详情页：自适应头部渲染 (Playlist Detail Layout)

大图视觉区:

官方“我喜欢” (Liked music / favorites)：固定展现粉蓝渐变 Thumbs-up 图标。

Watch later 系统歌单：时钟图标模板。

普通歌单：自适应网络大图，或当本地歌单无图时，自动拉取前 4 首歌曲的方形封面组成 2x2 的微缩拼接阵列。

功能操作区:

居中为大圆形 PlayButton（播放），两侧分别为 DownloadButton（置灰）和 MoreButton（YouTube 歌单含「克隆到本地」）。

列表内容注入规则:

如果是 LOCAL 歌单：列表第一项强制置顶展示 + Add a song 虚拟条目。

如果是 YOUTUBE 歌单：隐藏 + Add a song 选项。

### 2.4 二级菜单弹出矩阵 (Action BottomSheets)

单曲操作菜单:

头部区域: 水平两栏布局。左侧小封面 + 歌名 + 歌手；右侧放置一个高亮的 Thumbs Up (点赞状态) 原生按钮。

九宫格快捷动作行: Play next / **Start mix（置灰 Coming soon）** / Share。

下方纵向滚动列表: Add to queue, Download（置灰）, Save to playlist, Remove from playlist。

写锁机制控制:

如果当前歌曲所属的父歌单 source == DataSource.YOUTUBE，则 "Remove from playlist" 条目**置灰**并显示说明，不可点击。

## 3. Cursor 核心渲染层性能守则 (Performance Guards)

图片内存开销砍半: 整个 Library 的图片在 Coil 加载时，必须强制指定低内存位图配置：

```kotlin
bitmapConfig(Bitmap.Config.RGB_565)
```

封装为 `LibraryImage` 组件统一配置。

分组性能隔离: 历史记录页的时间分组（如 "June 2026"），必须在 ViewModel 中提前计算成 Map 映射结构，使用 `ZoneId.systemDefault()` 固定时区，在 Compose 中使用嵌套的 items 块渲染。

## 4. 验收标准

- List/Grid 切换不崩溃，key 稳定
- YouTube 歌单 Remove 置灰
- RGB_565 在 LibraryImage 全局生效
- 登录后 YouTube Chip 可见，访客不可见
- History 页按月预分组，Compose 内无动态日期格式化

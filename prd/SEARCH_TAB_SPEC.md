# 🔍 YTLite: Search Tab & Discovery Hub Technical Specification

## 1. 核心屏幕状态机与导航流 (Screen States & Flow)
搜索模块在同一个 Tab 内通过状态机驱动三种核心视图切换：
1. **DefaultHubState (搜索主页 - 参考 IMG_8611, IMG_8613):** 未输入任何字符或未激活输入框时展示。包含搜索栏、最近播放/查看卡片流、历史文本列表以及三大分类快捷入口卡片。
2. **SuggestionState (动态联想视图 - 参考 IMG_8612):** 当输入框被激活且检测到文本输入时瞬间切换。展示包含历史词、官方推荐词、艺术家、单曲的混合异构列表（Heterogeneous List）。
3. **SubCategoryState (二级探索页 - 参考 IMG_8614, IMG_8615, IMG_8616):** 点击主页最下方的分类卡片进入的独立子页面，包含“New releases”、“Charts”和“Moods and genres”。

---

## 2. 界面细化设计与低端机实现规范

### 2.1 顶级搜索栏组件 (Search Engine Bar)
* **元素架构 (参考 IMG_8611):**
  * 搜索框采用圆角矩形容器，左侧为返回/搜索小图标，中间为占位文字 `Hint: "Search songs, artists, podc..."`。
  * 右侧外置并列两个圆形功能按键：`MicrophoneIcon`（语音搜索）与 `WaveformIcon`（蜂鸣音频听歌识曲）。
* **联想状态切换 (参考 IMG_8612):**
  * 输入文字后，输入框内部右侧动态浮现 **"清除 (X)" 按钮**。
  * **低端机防抖控制 (Debounce):** 严禁每输入一个字母就触发一次 InnerTube API 搜索。必须在 ViewModel 中实现 `StateFlow` 并配置最少 `300ms` 的延迟防抖（Debounce），确认用户停止输入后再发出子线程网络请求。

### 2.2 搜索主页布局 (Default Hub Layout)
当输入框为空白时，纵向平滑渲染以下三大板块：
1. **最近查看卡片流 (Recent Searches - 参考 IMG_8611):** 
   * 标题 `Text("Recent searches")`。
   * 下方使用水平滚动 `LazyRow` 渲染最近点过的歌曲/视频，每个 Item 由横向方形小封面和底部被裁切的主标题组成。
2. **历史搜索词流 (Text History - 参考 IMG_8611):**
   * 纵向列表。左侧为 `ClockIcon`（时间钟表），中间为历史搜索词，右侧为快捷填入图标 `↖`（点击可将此词直接填入搜索框，但不立刻触发搜索，方便二次修改）。
3. **金刚位探索入口 (Discovery Shortcut Cards - 参考 IMG_8613):**
   * 横向排列的三个高亮卡片：
     * **New releases:** 附带黑胶/音符小图标。
     * **Charts:** 附带向上趋势折线图图标。
     * **Moods and gen...:** 附带笑脸图标。

### 2.3 联想输入：异构混合列表布局 (Heterogeneous Auto-Suggest)
当用户输入关键词（如 "t"）时，列表必须高效支持并排列展示四种不同数据形态的条目（参考 IMG_8612）：
* **形态 1（历史联想词）:** 显示左侧钟表图标、高亮匹配文字、右侧 `↖` 快捷键。
* **形态 2（艺术家联想）:** 左侧必须使用 **圆形切边 (Circle Crop)** 展现头像，副标题展示粉丝量（如 `"1.22m monthly audience"`），右侧提供三点更多菜单。
* **形态 3（单曲精选联想）:** 左侧为标准正方形封面，副标题展示类型与播放量（如 `"Song • Justin Bieber • 222m plays"`）。

### 2.4 二级独立探索子页矩阵 (Discovery Sub-Pages)
1. **新歌速递页 (New Releases - 参考 IMG_8614):**
   * 顶部固定一个巨大的特色 Banner 卡片（如 "New Release Mix"），采用大渐变图承载。
   * 下方构建 `"Albums and singles"` 横向滑动货架，卡片下方展示 `E` (Explicit) 显式标签或单曲标识。
2. **音乐排行榜 (Charts - 参考 IMG_8615):**
   * 顶置一个地区切换下拉框 `DropdownMenu`（默认展示 "Global"）。
   * 下方划分为“视频榜 (Video charts)”大卡片区与“热门歌手 (Top artists)”行列表区（左侧带大字重数字排名 1、2、3 顺次向下递增）。
3. **流派与心情 (Moods and Genres - 参考 IMG_8616):**
   * 划分为 `"Moods and moments"` 和 `"Genres"` 两个区块。
   * 每一区采用标准的 **双列紧凑网格 (2-Column Grid)** 展现。每个卡片采用纯黑背景，但**左侧边缘必须带有一条极细的彩色纵向渐变视觉特征线（Left-Side Accent Border）**以提升视觉质感。

---

## 3. Cursor 核心性能守则 (Performance Guards)

1. **Lazy 列表的类型判定复用:** 在动态联想异构列表中，必须在 `LazyColumn` 内通过不同的 `item { ... }` 块或声明不同的 `contentType` 来进行视图复用，严禁无差别渲染，防止低端机上下滑动时因动态解包产生卡顿。
2. **历史词本地化轻量缓存:** 历史搜索词直接存放于本地轻量 `Room` 数据库或 `DataStore` 中，最大上限设置为 15 条，多余的老数据采取自动顶替策略（FIFO Queue），防止无节制膨胀占用低端机存储空间。


🛠️ 阶段一：重构主页骨架（防抖搜索栏 + 核心状态机）
Plaintext
@SEARCH_TAB_SPEC.md 请严格阅读搜索规范。现在我们需要搭建 Search 模块的顶级骨架。
请帮我用 Jetpack Compose 编写核心布局：
1. 实现顶部的搜索框容器，支持 Hint 占位文字，右侧并列放置语音输入和听歌识曲圆形按钮。
2. 在 ViewModel 中为输入框的数据输入配置一个 300ms 的 kotlinx.coroutines.flow.debounce(300) 防抖逻辑。
3. 创建一个密封类 SearchState（包含 DefaultHub、Suggestions、SubCategory 三种状态），并在主页面通过 `when(state)` 结构预留出这三个视图的展示槽位。
📊 阶段二：编写静态主页（最近查看 + 历史词 + 三大分类卡片）
Plaintext
@SEARCH_TAB_SPEC.md 结合上一阶段。请帮我实现 `DefaultHubView`（搜索默认主页，参考 IMG_8611 与 IMG_8613）。
要求：
1. 实现 "Recent searches" 的水平 LazyRow 滚动流，Item 采用低内存 RGB_565 图片配置。
2. 实现纵向的历史词列表，左侧带 ClockIcon，右侧带快捷填入图标，点击快捷键需将文本更新到输入框。
3. 在列表最底部，实现并排三个高亮深色卡片（New releases, Charts, Moods and genres），并绑定点击事件，用于切换状态机进入二级探索页。
🎵 阶段三：开发多类型动态联想列表（异构 Auto-Suggest 组件）
Plaintext
@SEARCH_TAB_SPEC.md 请根据第 2.3 节的异构混合列表规范与参考图 IMG_8612，编写 `SearchSuggestionsList.kt`。
要求：
1. 传入一个混合类型的 List 数据源。在 LazyColumn 中，必须根据数据类型进行异构分流渲染。
2. 针对“艺术家”类型的条目，头像必须强行剪裁为正圆形（Circle Crop），且副标题展现粉丝数。
3. 针对“歌曲”类型的条目，左侧展示正方形封面，右侧带三点更多菜单。
4. 必须为 items 设置唯一的 key，且显式声明不同的 contentType 以确保低端机滑动时的组件高效复用。
🎛️ 阶段四：高精度复刻“心情与流派”彩边双列网格页
Plaintext
@SEARCH_TAB_SPEC.md 请高度复刻图片 IMG_8616 中的流派与心情页，编写 `MoodsAndGenresScreen.kt`。
要求：
1. 页面分为 "Moods and moments" 和 "Genres" 两个大 Section。
2. 每个 Section 的卡片统一使用 LazyVerticalGrid 或同等 Grid 布局排成双列（2-Column）。
3. 核心视觉复刻：每个矩形卡片为深灰色背景，文本居左靠中对齐，且卡片的左侧边缘必须绘制一条精细的、颜色互不相同的纵向彩色特征装饰线（Left-Side Accent Line）。

对于这份搜索 Tab 模块的重构设计方案，关于最近查看卡片（Recent searches）的清除机制，既可以让用户可以长按卡片单个删除，还需要在右侧提供一个全局的“清除全部（Clear All）”按钮。
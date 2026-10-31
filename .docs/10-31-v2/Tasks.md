# Tasks：Android 订阅页功能支持

**关联 Plan**：Plan.md —— Android 订阅页功能支持 v1.1
**状态**：DONE（2026-10-31 交付完成）
**日期**：2026-10-31
**版本**：v1.1（2026-10-31 评审修订）
**总计 Task**：12 个
**执行主体**：主线

---

## 前置约定

- 设计基线为 Material 3：复用 app/lib/core/widgets 下的卡片、确认框、骨架/空/错态、紧凑顶栏与金额格式化；金额使用现有 formatMoney/formatMonthDay，不新增硬编码色值。
- 数据与交互对齐 Web 订阅页与 internal/server/subscriptions.go 的既有契约；本轮不改后端、Web、数据库与依赖版本。
- 金额汇总只使用 amount_cents；禁止浮点累加。下次续费日、7 天窗口与分组分区由客户端纯函数推导，不落库。
- 所有新增 API 走既有 ApiClient 与控制器 _guard 链路；401 统一触发会话失效。
- 应用版本保持 0.1.6+5，不提升版本号，不新增依赖。
- 本机 Flutter 门禁（2026-10-31 基线：format 0 变更、analyze 无问题、141 项测试通过）：

  mkdir -p /tmp/ledger-dart-home
  cd app
  HOME=/tmp/ledger-dart-home /home/dev/flutter/bin/cache/dart-sdk/bin/dart format --output=none --set-exit-if-changed lib test
  HOME=/tmp/ledger-dart-home FLUTTER_ROOT=/home/dev/flutter FLUTTER_ALREADY_LOCKED=true PUB_CACHE=/home/dev/projects/Ledger/.pub-cache /home/dev/flutter/bin/cache/dart-sdk/bin/dart /home/dev/flutter/bin/cache/flutter_tools.snapshot analyze
  HOME=/tmp/ledger-dart-home FLUTTER_ROOT=/home/dev/flutter FLUTTER_ALREADY_LOCKED=true PUB_CACHE=/home/dev/projects/Ledger/.pub-cache /home/dev/flutter/bin/cache/dart-sdk/bin/dart /home/dev/flutter/bin/cache/flutter_tools.snapshot test --no-pub
  HOME=/tmp/ledger-dart-home FLUTTER_ROOT=/home/dev/flutter FLUTTER_ALREADY_LOCKED=true PUB_CACHE=/home/dev/projects/Ledger/.pub-cache /home/dev/flutter/bin/cache/dart-sdk/bin/dart /home/dev/flutter/bin/cache/flutter_tools.snapshot build web --no-pub

  Web 构建产物位于被忽略的 app/build/web；门禁通过后删除本次新增的该目录，保留工作区原有构建产物不动。

- 工作区当前存在已暂存的技能/规则文件、.pi 删除、temp/redesign-demo.html 删除，以及未跟踪的两张截图、temp/ledger-ui-variant-a.html 与根目录 Plan.md / Tasks.md；执行时以实时 git status 为准，不依赖本快照。不恢复、不 reset、不纳入本轮提交，提交使用路径白名单。
- 本机不构建 Android APK、不连接设备；Android 真机/模拟器验收列为待验证项。
- 根目录 Plan.md / Tasks.md 在本轮执行完成后按 Archive 流程移入按执行日计算的 archive_dir（规划时预计 .docs/10-31-v2/，执行时取实际值）。

---

## Phase 1：客户端契约与状态层

### TASK-001：新增订阅模型、API 方法与错误映射

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / 无
- **Description**：在 app/lib/core/api/models.dart 增加订阅状态、分组、订阅与提交输入模型；在 app/lib/core/api/api_client.dart 增加八个订阅端点方法；在 app/lib/core/api/api_exception.dart 补充分组重名的中文映射。
- **Details**：
  - SubscriptionStatus 枚举：active / paused；fromApi 对未知值回退 active；api 返回枚举名；label 为「使用中 / 已暂停」。
  - SubscriptionGroup：id、name、sortOrder；fromJson 解析 id、name、sort_order，忽略无消费方的 created_at；本轮不写 toJson（订阅不进入冷启动缓存）。
  - Subscription：id、groupId（可为空）、name、amountCents、billingDay、status；amount getter = amountCents / 100；解析 group_id 为空时保持 null；忽略响应中的 amount 浮点字段与 created_at；本轮不写 toJson。
  - SubscriptionInput：name、groupId（可为空）、amount、billingDay、status；toJson 输出 name、group_id、amount、billing_day、status.api。
  - ApiClient：getSubscriptionGroups、createSubscriptionGroup(name, sortOrder)、updateSubscriptionGroup(id, name, sortOrder)、deleteSubscriptionGroup(id)、getSubscriptions、createSubscription(input)、updateSubscription(id, input)、deleteSubscription(id)。路径为 /api/subscription-groups 与 /api/subscriptions，创建用 POST、更新用 PUT、删除用 DELETE；复用 _expectOk、_list、_one。
  - 错误映射新增 'subscription group already exists' => '分组名称已存在'；其余服务端错误保持既有兜底，不新增重复的前端校验。
  - createdAt 与 toJson 本轮没有消费方，不进入模型，避免与缓存/序列化约定形成未使用镜像。
  - 在 app/test/core/api_client_test.dart 增加一组订阅端点用例：GET 两组解析、POST 分组体、PUT 分组体、DELETE 分组路径、GET 订阅解析暂停状态与 group_id 空值、POST 订阅体（group_id 为空与整数两种）、PUT 订阅体与路径、DELETE 订阅路径。
- **Acceptance Criteria**：
  - dart format 无变更；flutter analyze 无问题。
  - 新增用例覆盖八个方法的路径、动词与关键请求体字段。
  - 金额以 amount_cents 为准，amount 仅作派生 getter；group_id 为空可正确往返。
  - 既有 API 客户端用例不回归。

### TASK-002：控制器接入订阅加载与清空

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001
- **Description**：在 app/lib/core/state/ledger_controller.dart 增加订阅分组、订阅列表、加载态、错误态、请求代际与 loadSubscriptions；把订阅纳入 loadAll 与 clear；在 app/lib/features/shell/app_shell.dart 的错误监听与缓存判断中纳入订阅。
- **Details**：
  - 字段：subscriptionGroups、subscriptions、subscriptionsLoading、subscriptionsError、_subscriptionsGeneration。
  - loadSubscriptions：递增代际并置 loading，Future.wait 并发拉取分组与订阅；代际不匹配直接返回；成功写入两个列表；ApiException 401 走 _expire；其他错误写入 subscriptionsError；finally 仅在代际匹配时清 loading 并 notifyListeners。
  - loadAll 增加 loadSubscriptions；clear 递增订阅代际并重置列表、loading、error。
  - AppShell 的 _onLedgerChanged：仅当订阅分组或订阅已有数据时，才把 subscriptionsError 纳入全局错误链；首次订阅加载失败只由订阅页 ErrorState 呈现，避免页面错误面板与 SnackBar 双提示。hasCachedData 追加订阅数据，供其他域的既有提示判断。
  - app/test/support/harness.dart 新增共享 subscriptionApiResponse(request) helper：按「方法 + 路径」处理 GET 列表、POST/PUT 单对象回显、DELETE success，并新增 subscriptionGroupJson、subscriptionJson 辅助构造函数；defaultApi 优先委托该 helper，默认数据覆盖两个分组、一个未分组、一个暂停项。
  - app/test/core/ledger_controller_test.dart 的 standardHandler 同样优先委托 subscriptionApiResponse，不再维护第二套订阅响应。
  - 页面用例若需要「变更后列表真的变化」，使用局部有状态 handler；共享 helper 只保证契约形状正确，避免把可变状态带进跨用例的 defaultApi。
  - 增加控制器用例：loadAll 填充分组与订阅；订阅加载 401 触发会话失效并清空；旧代际响应不覆盖新结果（可复用现有延迟响应模式）；订阅首次失败只写 subscriptionsError 且列表为空。
- **Acceptance Criteria**：
  - 全量测试通过，既有 141 项不回归。
  - 登录后 loadAll 同时填充订阅；订阅加载失败只写 subscriptionsError，不抛到 UI。
  - 401 清空订阅并回到登录；订阅首次失败不进入 Shell 提示，已有订阅数据时刷新失败仍只出现一条 SnackBar（Widget 用例在 TASK-009）。

### TASK-003：控制器订阅变更方法

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-002
- **Description**：在 LedgerController 增加分组与订阅的变更方法，统一使用 _guard，变更成功后重新拉取订阅，分组调序按 1..N 重写。
- **Details**：
  - createSubscriptionGroup(name)：sortOrder = 现有最大 sort_order + 1，创建后 loadSubscriptions，返回创建结果。
  - renameSubscriptionGroup(group, name)：保留原 sortOrder，更新后 loadSubscriptions。
  - moveSubscriptionGroup(group, direction)：按 sort_order、id 排序找到目标位置，移动后从 1 开始重写所有有变化的 sort_order；无论成功失败 finally 都 loadSubscriptions，异常向上抛出。
  - deleteSubscriptionGroup(group)：删除后 loadSubscriptions。
  - createSubscription(input)、updateSubscription(subscription, input)：调用 API 后 loadSubscriptions，返回结果。
  - setSubscriptionStatus(subscription, status)：以当前名称、分组、金额分转元、扣款日与新状态组装 SubscriptionInput，复用 updateSubscription。
  - deleteSubscription(subscription)：删除后 loadSubscriptions。
  - 变更方法不修改本地列表做乐观更新；由重新拉取提供唯一事实。
  - 扩展 app/test/core/ledger_controller_test.dart：用例内用记录型 MockClient（先记请求，再委托 subscriptionApiResponse）断言创建分组使用最大排序 +1、分组上移后的 PUT 顺序为 1..N、暂停订阅提交完整字段与 paused、删除订阅后触发一次订阅重载；变更失败仍重新拉取。
- **Acceptance Criteria**：
  - 所有变更路径都有 _guard；401 不会留下本地订阅脏数据。
  - 分组调序请求数量只覆盖排序值发生变化的项。
  - 控制器用例通过，既有用例不回归。

---

## Phase 2：订阅派生纯函数

### TASK-004：实现订阅派生纯函数与用例

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-001
- **Description**：新增 app/lib/features/subscriptions/subscriptions_utils.dart，集中实现续费日、整日差、汇总、筛选与分组分区；新增 app/test/features/subscriptions_utils_test.dart 覆盖边界。
- **Details**：
  - SubscriptionFilter：all / active / paused，label 为「全部 / 使用中 / 已暂停」。
  - SubscriptionSection：key、name、group（未分组为 null）、items、activeCount、totalCount、monthlyCents。
  - SubscriptionSummary：monthlyCents、annualCents、upcomingCents、upcomingCount、activeCount。
  - sortedSubscriptionGroups：按 sort_order、id 升序，供分区与页面配色共用，避免重复比较器。
  - daysInMonth(year, month) 使用 DateTime(year, month + 1, 0).day；nextRenewalDate(billingDay, now)：取本地零点，本月扣款日夹取到月末；若早于今天则取下月并再次夹取；今天返回今天；跨年由 DateTime 归一。
  - calendarDayDiff：使用 DateTime.utc(y,m,d) 的 difference，避免夏令时偏差。
  - summarizeSubscriptions：只累加 active 的 amount_cents；annual = monthly * 12；upcoming 仅 active 且整日差 0..6。
  - buildSubscriptionSections：分组按 sortedSubscriptionGroups；组内先按下次续费日再按名称 compareTo；未分组固定在最后；all 保留空分组，active/paused 只保留有匹配项的分区；未分组仅在存在匹配项时出现；分区 monthlyCents 与 activeCount 只统计 active，totalCount 统计全部。
  - 用例固定日期 new DateTime(2026, 10, 31) 等，覆盖：10-31 的 1 日/5 日/31 日；12-31 的 1 日跨年；2027-02-10 的 31 日夹取 02-28；2027-04-10 的 31 日夹取 04-30；当天差 0；差 6 计入、差 7 排除；暂停不计入月/年/未来 7 天；分组排序、组内续费日排序、空组保留、active 过滤隐藏空组、paused 只保留暂停项、未分组最后。
- **Acceptance Criteria**：
  - 新增用例不少于 10 条，flutter test 全部通过。
  - 金额派生只读取 amount_cents；函数不访问 BuildContext、不调用 API、不读写存储。
  - 移除月末夹取、把 7 天窗口写成 0..7、把暂停计入合计，任一改动都会使对应用例失败。

---

## Phase 3：订阅与分组表单

### TASK-005：订阅新增/编辑底部表单

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-003
- **Description**：新增 app/lib/features/subscriptions/subscription_sheet.dart，提供 SubscriptionSheet.show(context, initial, defaultGroupId)，承载新增与编辑订阅。
- **Details**：
  - 采用 showModalBottomSheet，isScrollControlled、useSafeArea、isDismissible: false、enableDrag: false；高度按可用高度 0.86，底部叠加 MediaQuery.viewInsets.bottom；结构为固定标题栏 + 可滚动表单 + SafeArea 底部保存按钮，沿用 ChannelSheet 的交互骨架；表单外层用 PopScope 在 busy 时阻止系统返回。
  - 字段：服务名称 TextField（maxLength 60，隐藏计数器）、分组 DropdownButtonFormField<int>（isExpanded，0 表示未分组，其余为分组 id）、每月金额 TextField（decimalInputFormatter、前缀 ¥、数字键盘）、扣款日 TextField（FilteringTextInputFormatter.digitsOnly、maxLength 2、后缀「日」）。
  - 编辑时回填名称、group_id（空为 0）、amountCents/100 的紧凑金额文本、billing_day；状态不在表单内修改，编辑保留原状态，新增固定 active。
  - 校验顺序：名称 TrimSpace 非空、金额 0.01–1,000,000、扣款日为 1–31、分组必须在当前分组列表或为 0；任一失败在表单顶部错误条给出中文提示并停止提交。
  - 提交时置 busy、禁用关闭与保存、保存按钮显示进度；busy 期间下滑、遮罩与系统返回均不关闭；成功 pop 并 SnackBar「订阅已添加 / 订阅已更新」；ApiException 保留表单与输入，错误条显示服务端消息；未知异常显示「保存失败，请稍后重试」。
  - 表单通过 context.watch 读取分组列表，保证打开期间分组变更可见；不直接操作页面状态。
- **Acceptance Criteria**：
  - 空名称、0 金额、1,000,000.01、32 日、不属于当前列表的分组均无法提交且不产生请求。
  - 320dp 下表单完整可见、可滚动，键盘弹出时保存按钮不被遮挡。
  - 关闭表单不产生请求；提交成功后才关闭并刷新列表。

### TASK-006：分组新建/重命名对话框

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-003
- **Description**：新增 app/lib/features/subscriptions/group_sheet.dart，提供 GroupSheet.show(context, group)，同时支持新建与重命名。
- **Details**：
  - 使用 showDialog(barrierDismissible: false) + 应用内 AlertDialog（沿用标签重命名的交互）：标题「新建分组 / 重命名分组」，TextField 自动聚焦、maxLength 30、隐藏计数器、textInputAction.done 提交；外层 PopScope 在 busy 时阻止系统返回。
  - 名称 TrimSpace 非空；与现有分组比较时忽略大小写并排除自身；重复时内联显示「分组名称已存在」，不发请求。
  - busy 时禁用取消与保存，且遮罩与系统返回不关闭；成功 pop 并 SnackBar「分组已创建 / 分组已重命名」；ApiException 保留对话框并显示消息。
  - 通过 LedgerController 的 createSubscriptionGroup / renameSubscriptionGroup 提交，不在页面内重复排序计算。
- **Acceptance Criteria**：
  - 空名称、仅空格、与现有分组大小写不敏感重名均无法提交。
  - 新建分组排序值为当前最大 +1；重命名保留原排序值与组内订阅。
  - 提交失败不关闭对话框、不丢失输入。

---

## Phase 4：订阅页、五段导航与管理动作

### TASK-007：订阅页展示层与五段导航

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-004, TASK-005, TASK-006
- **Description**：新增 app/lib/features/subscriptions/subscriptions_screen.dart 的只读展示层；在 app/lib/features/shell/app_shell.dart 接入第五个导航项；更新 Shell 用例。
- **Details**：
  - SubscriptionsScreen 为 StatefulWidget，持有 SubscriptionFilter；使用 RefreshIndicator + CustomScrollView（physics: AlwaysScrollableScrollPhysics）+ LedgerSliverAppBar(title: '订阅')，底部 padding 100 避开 FAB 与导航栏，内容不足一屏时仍可下拉刷新。
  - 内容顶部为右对齐 Wrap 操作区：OutlinedButton.icon「新建分组」（key subscriptions-add-group）与 FilledButton.icon「添加订阅」（key subscriptions-add）；320dp + 2x 下允许换行。
  - Hero 使用 LedgerCard(radius: 28)：eyebrow「每月固定开支」+ 使用中项数小胶囊；月合计大数字（¥ 前缀 + formatMoney(withCurrency:false) + / 月，FittedBox 防溢出）；下方两列 Expanded「年度预估 / 未来 7 天（含项数）」，标签允许换行、数值用 FittedBox 收缩；底部按分组 monthlyCents 绘制 7px 分布条，颜色统一取 FinanceColors.chart[index % chart.length]（分组下标来自 sortedSubscriptionGroups，未分组取分组数），无金额分段时不渲染分布条。
  - 筛选行：Wrap(spacing: 8, runSpacing: 8) 内放三个 ChoiceChip（全部 / 使用中 / 已暂停），key 为 subscriptions-filter-all/active/paused；320dp + 2x 下允许换行，不使用三段等宽控件；计数辅助文本「共 N 项 / N 项已暂停」放在胶囊组下一行右对齐，避免与胶囊抢宽。
  - 分区卡：LedgerCard(padding: EdgeInsets.zero)；组头分两行：首行色点 + Expanded 名称 + 使用中月合计（暂停视图无使用中金额显示「—」）+ 菜单占位，次行使用中项数（暂停视图显示已暂停项数），避免 2x 下名称/小计/项数/菜单四者抢宽；行展示首字母瓦片、名称与暂停胶囊（用 Wrap，长名称可换行）、元信息（使用中「每月 N 日 · 下次 M月D日」，暂停「原扣款日 N 日」，允许自然换行不截断）、金额 / 月（Flexible + FittedBox）与菜单占位。
  - 空分组在 all 视图保留分区，显示「暂无订阅」与「添加」TextButton（key subscriptions-empty-add-{groupId}），未分组分区不显示分组菜单。
  - 状态分流：首次加载且无数据 → SkeletonList(rows:5)；首次加载失败且无数据 → ErrorState + 重试；分组与订阅都为空 → EmptyState「还没有订阅」+「添加第一个订阅」；筛选无结果 → EmptyState「暂无使用中的订阅 / 暂无已暂停的订阅」+「查看全部」。
  - 窄屏约束：行内金额 Flexible + FittedBox；元信息不使用 maxLines 截断，允许增高；组头小计 FittedBox 且不挤压菜单；行高至少 62；筛选胶囊与操作按钮在 2x 下换行但不横向溢出。
  - AppShell：destinations 顺序改为流水 / 统计 / 订阅 / 资产 / 设置，订阅使用 Icons.autorenew_rounded；IndexedStack 增加 SubscriptionsScreen；引入 static const subscriptionsIndex = 2、settingsIndex = 4，替换设置分区重置与渠道直达中的裸 3；PopScope 行为不变。
  - 更新 app/test/features/shell_test.dart：断言五个导航项；点击「订阅」显示「每月固定开支」；系统返回回到「本月结余」；从设置确认「分类与标签」、从资产「管理」确认进入「渠道与账户」；保留 landscape 与 320dp + 2x 用例。
- **Acceptance Criteria**：
  - 五个 Tab 均可切换，订阅页首屏无 NaN/undefined/空金额；点击设置进入「分类与标签」，渠道直达进入「渠道与账户」。
  - 暂停项不计入 Hero、分组小计与未来 7 天；暂停筛选下分区小计显示「—」。
  - 320/360/390dp 与 2x 字体下无横向溢出、无标签截断、无不可达按钮；320dp 用例断言筛选胶囊与 Hero 标签的矩形落在视口内。
  - 既有流水/统计/资产/设置页面行为不回归。

### TASK-008：订阅与分组管理动作收口

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-007
- **Description**：在订阅页接通行菜单、分组菜单、暂停恢复、删除确认、分组调序与空分组添加入口。
- **Details**：
  - 行 PopupMenuButton（key subscription-menu-{id}，tooltip「订阅操作」）：编辑、暂停续费/恢复续费、分隔线、删除（错误色）。编辑打开 SubscriptionSheet(initial)；暂停/恢复调用 setSubscriptionStatus 并提示「已暂停续费 / 已恢复续费」；删除先 ConfirmDialog（标题「删除订阅」，说明含服务名与「删除后不可恢复」），确认后调用 deleteSubscription 并提示「订阅已删除」。
  - 分组 PopupMenuButton（key subscription-group-menu-{id}，tooltip「分组操作」）：在此分组添加订阅、重命名分组、上移、下移、分隔线、删除分组；首组禁用上移、末组禁用下移；未分组无菜单。
  - 上移/下移调用 moveSubscriptionGroup 并提示「分组顺序已更新」；失败用 ApiException 消息提示。
  - 删除分组 ConfirmDialog：标题「删除分组」，说明「「名称」内的 N 项订阅将移至未分组。」；确认后调用 deleteSubscriptionGroup 并提示「分组已删除，订阅已移至未分组」。
  - 空分组「添加」与分组菜单「在此分组添加订阅」都打开 SubscriptionSheet(defaultGroupId: 该组 id)。
  - 所有异步动作使用 context.read 在 await 前取控制器，await 后检查 mounted；失败不崩溃、不关闭已打开的表单。
  - 菜单由 Material 路由管理单开；不新增自定义菜单状态；确认框沿用 ConfirmDialog.show。
- **Acceptance Criteria**：
  - 新增/编辑后行内容、Hero、分组小计、年度预估与未来 7 天同步更新。
  - 暂停后该行不计入任何总额，恢复后重新计入；菜单文案与状态同步切换。
  - 删除分组后其订阅出现在未分组且仍计入 Hero；组内订阅不被删除。
  - 删除订阅与删除分组均需确认；取消不产生请求。
  - 320dp 下首行与末行菜单都可见、可点击，不被卡片裁切。

---

## Phase 5：测试、文档、归档与提交

### TASK-009：订阅页 Widget 测试

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-008
- **Description**：新增 app/test/features/subscriptions_test.dart，覆盖展示、筛选、空分组、表单校验与提交、暂停恢复、删除分组与窄屏布局。
- **Details**：
  - 使用 testControllersWithHandler + defaultApi 数据，pump SubscriptionsScreen；需要滚动时使用 scrollUntilVisible/drag，不依赖离屏缓存。
  - 用例一：Hero 显示使用中月合计与年度预估；暂停项金额不计入；分组小计正确；未分组在最后。
  - 用例二：切到「已暂停」只显示暂停行，辅助文案为已暂停项数；切回「全部」恢复；筛选不改变 Hero 总额。
  - 用例三：空分组在全部视图显示「暂无订阅」与「添加」；点击添加打开表单且分组已预选。
  - 用例四：新增订阅表单对空名称、0 金额、32 日给出错误且不产生 POST；填入合法值后 POST body 的 name、group_id、amount、billing_day、status 正确。
  - 用例五：行菜单暂停续费产生 PUT 且 status 为 paused，成功后出现提示；恢复相反。
  - 用例六：分组菜单删除弹出确认，说明包含组内数量；确认后发送 DELETE；取消不发送。
  - 用例七：编辑订阅时表单回填名称、分组、金额与扣款日；只改金额后保存，PUT body 包含原分组、原扣款日与保留的 status。
  - 用例八：分组重命名与上移各自产生正确 PUT；上移后按新顺序发送 1..N 的 sort_order，成功后提示「分组顺序已更新」。
  - 用例九：删除订阅确认弹窗含服务名；确认后发送 DELETE，取消不发送。
  - 用例十：仅订阅首次加载失败时，进入订阅页显示 ErrorState 且不出现 SnackBar；已有订阅数据后刷新失败保留内容并出现一条 SnackBar。
  - 用例十一：5 个分组 + 1 条未分组订阅时页面正常渲染，分布条与分组色点不越界（验证取模）。
  - 用例十二：320dp + 2x 渲染含空组、筛选胶囊与多行的页面，takeException 为 null；断言三个筛选胶囊、Hero 的「年度预估 / 未来 7 天」矩形均在视口内；操作按钮可达。
  - 需要「变更后状态真的变化」的用例使用局部有状态 handler；不把可变状态塞进共享 defaultApi。
  - 若测试需要稳定定位，使用 TASK-007/008 约定的 ValueKey；不新增测试专用生产参数。
- **Acceptance Criteria**：
  - 新增用例不少于 11 条，flutter test 全部通过。
  - 断言覆盖请求体关键字段与用户可见结果，不仅断言控件存在；编辑、分组调序、删除订阅、首次/刷新错误口径与设置直达均有覆盖。
  - 320dp + 2x 用例不仅断言无异常，还断言关键文本矩形在视口内。
  - 既有页面用例不回归。

### TASK-010：全量门禁与回归验证

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-009
- **Description**：执行格式、静态检查、全量 Flutter 测试与 Web 编译，进行派生函数变异校验，并修复发现的问题。
- **Details**：
  - 依次执行前置约定中的 format、analyze、test --no-pub、build web --no-pub；记录实际通过项数与构建结果。
  - 变异校验：临时移除 nextRenewalDate 的月末夹取，确认短月用例失败；临时把 7 天窗口改为 0..7，确认边界用例失败；恢复后复跑全部通过。
  - 检查既有 141 项测试是否全部保留通过；新增用例计入总数。
  - 检查 320dp + 2x 页面与 Shell 无异常；检查 360/390dp 常规尺寸无横向滚动。
  - 清理本次新增的 app/build/web 目录，不删除工作区其他构建产物。
  - 不运行 Go 测试（后端未改动）；若实现中意外触碰非 app 路径，回退并说明。
- **Acceptance Criteria**：
  - format 0 变更；analyze 无问题；test 全部通过；build web 成功。
  - 变异校验两项均能触发失败，恢复后全绿。
  - 门禁数字与命令写入 Tasks/Plan 完成记录与 Project.md。

### TASK-011：Project.md 同步

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-010
- **Description**：更新 .docs/Project.md 的阶段、Android 客户端结构、数据流、测试记录、已知限制与决策，确保只描述已落地事实。
- **Details**：
  - 概述阶段补充 Android 五段导航与订阅固定开支管理，并把当前状态描述中的「MD3 四段导航」改为五段。
  - 结构树补充 app/lib/features/subscriptions/ 下四个文件与 app/test/features/subscriptions_utils_test.dart、subscriptions_test.dart；AppShell 说明改为五段导航。
  - 逐条更新当前状态描述中的旧导航表述：共享顶栏注释「四页共用」改为五页；shell 注释「四段导航 Shell」改为五段；Android 界面卡片「四段导航 + Stream / Stats / Assets / Settings」改为五段并加入 Subscriptions；术语「会话门」中的「四段 Shell」改为五段。
  - 2026-10-15 与 2026-10-20 的历史决策记录保留当时四段/四页的事实，不做全局替换；只改描述当前状态的段落。
  - Android 客户端段落补充订阅数据加载、控制器状态、表单与测试覆盖；发布版本保持 0.1.6+5。
  - 已知限制移除「订阅仅在 Web 交付」，补充订阅不写冷启动快照与 Android 真机待验收。
  - 约定中的订阅数据条目补充客户端消费；决策区新增 2026-10-31 Android 订阅页交付记录，包含门禁结果与设计取舍。
  - 不修改 SCOPE.md，不提前宣称未完成项。
- **Acceptance Criteria**：
  - Project.md 的文件、路由、字段、测试数字与实现一致。
  - 不存在过期描述或未实现能力。
  - 本轮改动路径均在白名单内。

### TASK-012：归档与提交

- **Status**：DONE
- **Executor**：主线
- **Priority / Dependencies**：P0 / TASK-011
- **Description**：将 Plan.md / Tasks.md 标记 DONE、补完成日期、门禁数字与变异校验结论，按 Archive 规则计算 archive_dir 并移入，再按路径白名单提交。
- **Details**：
  - 先定义 archive_dir：以执行日为准，格式 .docs/MM-DD-vN；查询 .docs 下同日前缀取最大 N + 1；本轮规划预计 .docs/10-31-v2/，执行时必须使用实际变量值，不硬编码。
  - 归档前在两份文档写入：完成日期、交付结果、门禁命令与实际项数、变异校验、待验证项。
  - 用 mv 将根目录 Plan.md、Tasks.md 移入 archive_dir；移动后校验 archive_dir 同时含两份文档，根目录无残留。
  - 归档后只 add 归档目录与其余白名单：git add -- "$archive_dir"/ <其余白名单路径>；不再对已移动的根目录 Plan.md / Tasks.md 执行 git add。
  - 提交使用：git commit -m "<英文类型前缀 + 中文描述>" --only -- "$archive_dir"/ <同一组白名单路径>；选项必须写在 -- 之前。--only 只提交指定路径，既有暂存文件不会进入 HEAD 且保持暂存。禁止全局 git add -A / git add .。
  - 白名单：app/lib/core/api/models.dart、app/lib/core/api/api_client.dart、app/lib/core/api/api_exception.dart、app/lib/core/state/ledger_controller.dart、app/lib/features/subscriptions/、app/lib/features/shell/app_shell.dart、app/test/support/harness.dart、app/test/core/api_client_test.dart、app/test/core/ledger_controller_test.dart、app/test/features/subscriptions_utils_test.dart、app/test/features/subscriptions_test.dart、app/test/features/shell_test.dart、.docs/Project.md、$archive_dir/。
  - git status / git diff / git log 检查；记录既有暂存清单，不执行 git reset，不改变用户暂存区。
  - 提交前用 git diff --cached --name-only -- <白名单路径> 核对本轮暂存内容（避免把既有 24 个暂存文件误读成本轮改动）；提交后用 git show --name-only HEAD 确认只含白名单；既有技能文件、.pi 删除、temp 截图与 web 端改动不进入 HEAD。
  - 提交信息使用英文 Conventional Commits 前缀 + 中文描述，聚焦为什么；不加 --no-verify，不 amend。
- **Acceptance Criteria**：
  - 归档目录同时含 Plan.md 与 Tasks.md，根目录无 Plan.md / Tasks.md。
  - HEAD 只含白名单路径；既有暂存文件仍未进入 HEAD 且保持暂存。
  - 未使用全局 git add -A / git add .、git reset、--no-verify 或 amend；提交使用 git commit --only 白名单路径，既有暂存保持原状。
  - Android 待验证项（APK 安装、真机尺寸与字体、明文 HTTP）明确记录，不声称已在设备验证。

---

## 完成记录

- **完成日期**：2026-10-31
- **交付结果**：TASK-001 ~ TASK-012 全部完成。客户端新增订阅模型与八个 API 方法、控制器订阅加载/清空/变更（代际、401、变更后重拉）、续费日与汇总/分区纯函数、订阅底部表单、分组对话框、五段导航与订阅页、行/分组管理动作、12 条页面 Widget 用例与 12 条纯函数用例；Project.md 同步并归档。
- **回归结论**：`dart format --output=none --set-exit-if-changed lib test` 0 变更；`flutter analyze` No issues；`flutter test --no-pub` 177 项通过（既有 141 项保留，新增 36 项）；`flutter build web --no-pub` 成功，构建产物 `app/build/web` 已清理。未运行 Go 测试（后端未改动）。
- **变异校验**：移除短月夹取后短月用例失败（期望 2027-02-28，实际 2027-03-03）；把 7 天窗口改为 0..7 后边界用例失败（期望 600，实际 1300）；两次均恢复实现并复跑通过。
- **待验证项**：Android APK 安装、真机/模拟器尺寸与字体、debug 明文 HTTP、edge-to-edge 交互待用户验收；订阅不写冷启动快照，离线首帧不展示缓存订阅。
- **归档**：`.docs/10-31-v2/Plan.md` 与 `.docs/10-31-v2/Tasks.md`。

# DSH 桌宠 · 蓝色大肥鱼

一打开 DeepSeek Harness 就会自动浮在桌面上的小桌宠：显示你的实时余额，挂机时随机换姿势，右键可以自己点选姿势。

原型来自你给的 17 张蓝发鲸鱼女仆状态图（第 1 张三视图设定图没有使用）。

---

## 它长什么样 / 会做什么

| 能力 | 说明 |
| --- | --- |
| 自动出现 | 登录 Windows 时后台启动；启动时若 DSH 没在运行就自动退出，DSH 一关它也自动退出 |
| 实时余额 | 头顶气泡常驻显示「余额 ¥x.xx」，下面一行是「充值 ¥x.xx　赠送 ¥x.xx」；每 90 秒自动刷新 |
| 挂机换姿势 | 空闲时每 14–30 秒随机换一个姿势（微笑／端坐／挥手／思考／害羞／慌张／得意／看报／挠头…） |
| 发呆就睡 | 超过 90 秒没有任何操作，会变成「睡着」；你一动它就醒 |
| **拖动位置** | **在窗口任意处按住左键拖动**（整块区域都能拖，不只是角色像素上）；位置会记住，下次打开还在原处 |
| **点开设置** | **点气泡右边的 ⚙ 齿轮**，或**双击肥鱼**，或**右键选「设置」** —— 三种方式都能打开设置面板 |
| 手动切换 | **右键**弹出姿势菜单，点谁就切谁，并锁定 2 分钟不再自动乱切 |
| 滚轮换姿势 | 鼠标滚轮直接上一个／下一个姿势 |
| 动态效果 | 每个姿势有独立的呼吸／摇摆／跳动／发抖曲线，换姿势是 260ms 交叉淡入淡出 |

窗口是**透明无边框、置顶、不占任务栏**的，所以看起来就像角色直接站在桌面上，其余区域点得到下面的窗口。

---

## 文件说明

```
desktop-pet/
├── pet.ps1              桌宠主程序（透明窗口、动画、状态机、余额气泡、右键菜单）
├── autostart.ps1        开机自启的安装／卸载／状态查询
├── launch-pet.cmd       自启用的隐藏启动器（由 autostart.ps1 生成）
├── config.json          出厂默认：所有中文文案与行为参数（换姿势间隔、刷新频率、窗口尺寸…）
├── settings.ps1         设置面板（双击肥鱼打开的那一屏）
├── settings.json        你在设置面板里改过的值（首次运行后自动生成）
├── tools/               自测用脚本（探测窗口、截图、重启桌宠）
├── build-sprites.js     从原图重新生成 assets（抠图、去水印、缩放）
└── assets/              17 张处理好的透明状态图 + states.json 清单
```

`pet.ps1` 里没有任何中文：Windows PowerShell 5.1 会按 ANSI 读取无 BOM 的脚本，所以中文全部放在 `config.json` 和 `assets/states.json` 里，运行时按 UTF-8 读入。

---

## 常用操作

```powershell
# 看一遍自检：配置、素材、DSH 是否在跑、余额接口、自启状态
powershell -NoProfile -ExecutionPolicy Bypass -File .\desktop-pet\pet.ps1 -Doctor

# 立刻启动（不等 DSH、也不管有没有在跑）
powershell -NoProfile -ExecutionPolicy Bypass -File .\desktop-pet\pet.ps1 -Force

# 开机自启：安装 / 卸载 / 查看 / 重启
powershell -NoProfile -ExecutionPolicy Bypass -File .\desktop-pet\autostart.ps1 -Install
powershell -NoProfile -ExecutionPolicy Bypass -File .\desktop-pet\autostart.ps1 -Uninstall
powershell -NoProfile -ExecutionPolicy Bypass -File .\desktop-pet\autostart.ps1 -Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\desktop-pet\autostart.ps1 -Restart

# 只打开设置面板（调试用）
powershell -NoProfile -ExecutionPolicy Bypass -File .\desktop-pet\pet.ps1 -Force -OpenSettings
```

日志在 `%LOCALAPPDATA%\dsh-desktop-pet\pet.log`（超过 512KB 自动清空）。

---

## 余额是怎么来的

DSH 把 DeepSeek 账号的登录凭据存在 `~/.dsh/.credentials.yaml` 里。桌宠按 DSH 自己的方式使用它：

```
GET https://platform.deepseek.com/api/v0/users/get_user_summary
Header: x-dsh-auth-token: <deepseek-account-platform/default 里的 token>
```

返回 `normal_wallets`（充值余额）与 `bonus_wallets`（赠送余额），两者相加就是气泡上的总额。**不会重新登录、不会改你的凭据、不会把 token 写到别处**，只读地取出来发一次请求。

如果读不到或者请求失败，气泡会显示「余额不可用」，并在日志里记下原因——不会伪造一个 0。

---

## 图片是怎么处理的（`build-sprites.js`）

原图是白底 + 淡网格 + 右下角「豆包AI生成」水印，所以：

1. **背景用连通填充判断**，而不是按亮度阈值——按亮度会把围裙、头饰这些白色部分一起抠掉；
2. 边缘按亮度在「全透明↔全不透明」之间做渐变，抗锯齿的描边不会变成硬边；
3. 水印是灰的，会被亮度渐变处理成半透明灰字，所以**抠完之后把 alpha 拆成连通块，只丢掉明显偏小的碎块**（水印、噪点），角色本体和发丝、尾巴这些独立部分都保留；
4. 最后缩到 340px 宽。桌面上按 0.58 倍显示（约 200px），等于 1.7 倍超采样，所以看起来是清晰的而不是被拉大的。

重新生成素材：

```powershell
node desktop-pet\build-sprites.js "<原图目录>" "desktop-pet\assets" 340
```

---

## 想调什么改哪里

**首选：点气泡上的 ⚙（或双击肥鱼）打开设置面板里改**（改完立刻生效，存在 `settings.json`，不会被以后更新 `config.json` 覆盖）。
面板里能调：大小、自动换姿势间隔（最短/最长）、手动选完后锁定多久、多久没操作就睡着、余额刷新频率、
余额偏低提醒阈值、是否自动换姿势、是否记住窗口位置，还有「立即刷新余额」和「恢复默认」两个按钮。

**其次：改 `config.json` 的出厂默认**（只在 `settings.json` 里没有该项时生效）：

| 想改的东西 | 位置 |
| --- | --- |
| 大小 | `behaviour.displayScale`（0.5 小，0.8 大） |
| 换姿势快慢 | `behaviour.autoSwitchMinSeconds` / `autoSwitchMaxSeconds` |
| 余额刷新频率 | `behaviour.balanceRefreshSeconds` |
| 多久变睡着 | `behaviour.sleepAfterIdleSeconds` |
| 手动锁定多久 | `behaviour.fixedAfterManualSeconds` |
| 设置面板里的中文文案 | `ui.settings.*` |
| 右键菜单里的姿势名 | `config.json` → `states.<id>.label` |
| 每个姿势怎么动 | `assets/states.json` → 每条记录的 `motion`（`breathe`／`sway`／`hop`／`tremble`／`sleep`） |
| 哪些姿势参与挂机轮播 | `assets/states.json` → 每条记录的 `idle` |
| 默认位置 | `pet.ps1` 里 `Add_Loaded` 里的 `$window.Left` / `$window.Top` |

---

## 已知取舍

- 桌宠是**单独的进程**，不改 DSH 安装目录，所以 DSH 升级／重装都不会影响它；代价是它需要自己盯着 DSH 进程来决定何时出现和退出。
- 拖动用**屏幕绝对坐标**，而且光标与窗口位置先换算到**同一套单位**（你的显示器是 125% 缩放：`GetCursorPos` 给物理像素，WPF 的 `Left/Top` 给逻辑单位，不换算就会固定偏一大截）。手势期间姿势动画停住，松手后恢复；如果拖到一半换了姿势，会在松手时重新贴合窗口。
- 设置面板里的「回到右下角」可以把拖远的桌宠叫回来。
- 缩放是**整体等比例**的：余额气泡、气泡里的文字与内边距、角色，全部放在同一块设计画布上，外面套一个 `Viewbox` 一起缩放，所以任何尺寸下它们的比例都一致。窗口尺寸 = 设计画布 × 缩放系数，所以不会有空白框，也不会出现"只有角色变小、气泡还是原来大小"。
- 缩放系数有上限：如果按你设的系数算出来比工作区还高（角色会被切掉），就自动收到刚好放得下的大小。你的屏幕（1536×864，工作区高 816）上，最大可用系数约 0.83（视姿势高度而定）。
- 拖动缩放的写入都有 NaN/越界保护，窗口位置永远不会被写成非法值。
- 余额刷新用后台作业取值、主线程每秒轮询一次结果：刷新间隔由设置决定（默认 5 秒），单次请求本身约 1 秒。
- 设置面板自己也是**置顶**的（否则会被 DSH 窗口压住，看起来像"一打开就关了"）。它的所有按钮／键事件都通过 `$sender` 拿自己的窗口，不引用会随函数一起消失的局部变量——`Set-StrictMode` 下那种引用会直接抛异常把整个桌宠带走。
- 最后还有一道兜底：调度器上的未处理异常只记日志、不再结束进程，所以以后某个回调出问题也不会让桌宠突然消失。
- 气泡目前把「充值＋赠送」合成一个总额显示，明细在第二行常驻。想改成悬停才显示明细，改 `Update-BalanceDisplay` 即可。
- 右键菜单 17 项，屏幕太矮时会出现滚动条，属正常。

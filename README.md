# 🍅 番茄鐘 — Pomodoro Timer for macOS

A native macOS pomodoro timer (SwiftUI + AppKit) that shrinks to a floating dial
and stays visible **over other apps in full screen** — built for studying with a
PDF or a book filling the display.

**Highlights**

- A floating `NSPanel` that survives other apps' full-screen Spaces without stealing focus
- 10 dial styles — classic ticks, 8-bit pixel, flip clock, LCD, hourglass, moon phase,
  water level, Bauhaus, minimal ring, station clock — and the floating window takes each one's shape
- An alert you can't miss: 20 built-in sounds (plus your own from `~/Library/Sounds`),
  configurable repeat count or ring-until-dismissed, a dial that keeps pulsing until
  acknowledged, and an optional full-screen break mask
- Global hotkeys via Carbon `RegisterEventHotKey` — **no accessibility permission required**
- Presets (25/5, 30/10, 50/10, 90/20), task labels, history grouped by day
- ~0.5% CPU while running

Builds with **Xcode Command Line Tools only** — no Xcode needed: `./build.sh`

Every push is compiled on macOS by GitHub Actions (`.github/workflows/build.yml`).

> The rest of this README is in Traditional Chinese. Beyond usage, it documents the
> non-obvious macOS pitfalls this app hit — AppKit not counting `NSPanel`s as windows,
> the compositing cost of repainting over a full-screen app, and `@State` now requiring
> a macro plugin that ships only with full Xcode. Those sections may be useful if
> you're building something similar.

---

一個原生的 macOS 番茄鐘（SwiftUI）。

## 安裝

只要三步，**全程不會跳任何安全警告**——自己編譯出來的 App 不會被系統隔離。

1. 裝 Xcode Command Line Tools（如果還沒有）。開「終端機」貼上：

   ```bash
   xcode-select --install
   ```

   會跳出安裝視窗，照指示裝完即可（約 1–2 GB，要一點時間）。不需要完整版 Xcode。

2. 下載並編譯：

   ```bash
   git clone https://github.com/kalovee/pomodoro-mac.git && cd pomodoro-mac && ./build.sh
   ```

3. 搬到應用程式資料夾並打開：

   ```bash
   mkdir -p ~/Applications && mv 番茄鐘.app ~/Applications/ && open ~/Applications/番茄鐘.app
   ```

需要 macOS 14 以上（Info.plist 宣告的下限；實際只在 macOS 26 與 27 上測試過）。

> **為什麼不直接提供 .app 下載？**
> 這個 App 是 ad-hoc 簽章，沒有 Apple 的 Developer ID，也沒有經過公證。
> 透過 AirDrop、雲端或 email 傳過去的檔案會被標上隔離屬性，Gatekeeper 會擋下來，
> 收到的人得自己去「系統設定 → 隱私權與安全性」手動放行。
> 要做到下載就能開、零警告，需要 Apple Developer Program（年費 99 美元）
> 簽發的 Developer ID 憑證加上公證流程。自己編譯完全沒有這個問題。

## 功能

- **十種錶盤風格**（詳見下方「錶盤風格」）：經典刻度、像素、翻頁鐘、LCD 電子錶、沙漏、月相、
  水位、包浩斯、極簡環、車站鐘。設定最上方有縮圖牆可以點選，縮小模式按右鍵 →「風格」也能換。
  縮小模式的**形狀跟著風格走**：像素是方的、翻頁鐘和 LCD 是寬的、沙漏是高的
- **時間組合預設**：25/5、30/10、50/10、90/20，一鍵換掉專注／短休／長休／輪數。
  三個入口都可以切：設定裡的膠囊按鈕、選單列「計時」（⌘1–⌘4）、
  縮小模式在圓盤上按右鍵 →「時間長度」
- 每一項時間長度也都能自己微調（改成不符合任何預設就顯示「自訂」）
- **縮小模式**：收成一個浮動錶盤（經典刻度是 168pt 的圓），只剩計時器，可以直接拖著在桌面上移動；
  滑鼠移上去才出現播放／放大按鈕。陰影由系統畫在視窗外面、跟著錶盤的形狀走，後面不會有方框
- **浮在最上層**（可開關，右上角圖釘或設定裡）：視窗拉到狀態列層級、加入所有 Space，
  **別的 App 全螢幕時也蓋在上面**，適合一邊全螢幕讀書一邊計時。
  浮動時預設會把 Dock 圖示收起來（一般 App 在別人進全螢幕時會被系統收走，附屬模式才待得住）
- **縮小時閒置變半透明**：滑鼠不在上面就淡到 42%，移過去才恢復，讀書時不干擾
- **時間到自動接下一段**（可開關）
- 任務標籤：輸入正在做什麼，完成後存進紀錄。欄位右邊的時鐘選單列出最近用過的任務，點一下就填好
- **中途結束也能記**：讀到一半想收了，按「結束並記下 N 分鐘」就會把**實際專注的時間**
  寫進紀錄再進入休息。暫停的時間不會被算進去
- 今日完成番茄數與專注總時數，**從紀錄推導**（不另外存一份，所以讀書過午夜也不會累積到隔天）
- 完成紀錄**按日期分組**，每天有小計；今天／昨天用相對說法，更早的標月日與星期
- **紀錄統計**：紀錄頁上方有本週專注時數、連續專注天數、今天完成數，最近 7 天的長條圖，
  以及最近 7 天花最多時間的三個任務。全部從紀錄推導，不另外存
- **紀錄可以修正**：在任何一筆上按右鍵可以改任務名稱或刪除；「清除紀錄」會先確認。
  紀錄最多保留一萬筆（原本只有 200 筆，大約一個月前的會被悄悄刪掉）
- **時間到的提醒**（這一版重做過）：
  - 20 種內建鈴聲可選、可試聽，音量可調
  - **想要更多聲音**：把任何 `.aiff / .wav / .m4a / .mp3` 丟進 `~/Library/Sounds`
    （設定裡有「打開」按鈕），就會出現在選單的「我的」分組裡。
    這是 macOS 官方的擴充點，不必改程式
  - 「響固定次數」或「直到你按掉」，兩種都有 5 分鐘安全上限
  - **圓盤會變成全亮並脈動，直到你按掉為止**——聲音有長度上限，視覺沒有。
    一個你沒聽到的鈴聲再長也是沒聽到，但三分鐘後還在脈動的圓盤，下次瞄到角落就會發現
  - **休息全螢幕遮罩**：專注結束時蓋住整個畫面，休息期間持續顯示，休息完自動消失
  - 系統通知標為 time-sensitive，專心模式也穿得過去
- 淺色／深色模式都有設計過

## 操作

| 動作 | 方式 |
|---|---|
| 開始 / 暫停 | 中間大按鈕，或 ⌘↩ |
| 重設這一段 | 左邊 ↺ |
| 跳過這一段 | 右邊 ⏭（不計入完成數） |
| 縮小 / 放大 | 右上角箭頭；縮小後滑鼠移上圓盤即可放大（270ms，以視窗中心為軸心） |
| 浮在最上層 | 右上角圖釘 |
| 查看紀錄 | 左下角「今日 N」 |
| 設定 | 右下角齒輪 |
| 停止提醒 | 點一下圓盤，或右鍵選單的「停止提醒」 |
| 提前結束休息 | 遮罩上的「跳過休息」 |
| 記下中途的進度 | 按鈕下方的「結束並記下 N 分鐘」（累積滿 1 分鐘才出現）、右鍵選單，或 ⌘⇧L |
| 只收起遮罩（休息繼續） | 點遮罩任意處 |
| 切換時間組合 | ⌘1 = 25/5，⌘2 = 30/10，⌘3 = 50/10，⌘4 = 90/20（App 在前景時） |
| **全域熱鍵**（焦點在別的 App 也有效） | ⌃⌥空白鍵 開始／暫停、⌃⌥R 重設、⌃⌥S 跳過 |
| **視窗有焦點時**（不用修飾鍵） | 空白鍵 開始／暫停、R 重設、S 跳過、Esc 停止提醒 |
| 選單列 | ⌘↩ 開始／暫停、⌘R 重設、⌘⇧S 跳過 |
| 移動縮小後的圓盤 | 直接拖曳圓盤任何位置（拖曳不會被當成點擊，提醒中拖一下不會誤按掉） |
| 換錶盤風格 | 設定最上方的「風格」，或縮小模式右鍵 →「風格」 |
| 取消任務欄位的焦點 | Esc（不會關掉視窗） |

縮小模式下三顆紅綠燈按鈕會隱藏。**在圓盤上按右鍵**可以開始／暫停、重設、放大、
取消浮動、結束 App——浮動時沒有 Dock 圖示和選單列，這是固定的出口。

## 設計

- 中性色刻意偏一點暖，跟蕃茄紅同一個色溫家族；強調色只花在錶盤和主要按鈕上
- 數字一律等寬（tabular），倒數時不會左右跳動
- 輪數用實心／空心圓點表示，因為它本來就是一個有序的序列
- 三個階段各有自己的色相：專注紅、短休息綠、長休息藍

## 錶盤風格

| 風格 | 縮小尺寸 | 進度怎麼表示 | 休息時怎麼區分 |
|---|---|---|---|
| 經典刻度（預設） | 168 圓 | 60 格刻度，走過的上色；內側一片淡色扇形＝剩下的時間（參考 Time Timer） | 換階段色 |
| 像素 | 160 方 | 外框一圈 60 個像素方塊，剩下的亮；數字下一條 10 格 HP 條 | 番茄圖示換成咖啡杯 |
| 翻頁鐘 | 232×112 | 卡片下方細線；**分鐘變的時候翻一頁**，秒數就地換字。卡片上下半明度不同、轉軸縫有亮邊、角落印「分」「秒」 | 角落小字 BREAK |
| LCD 電子錶 | 212×112 | 帶括號的分段條；沒亮的段淡淡留著；右上角小七段顯示輪數，錶殼兩側有按鍵 | 液晶上的「短休／長休」段亮起 |
| 沙漏 | 132×184 | 上半部的沙＝剩下的時間，沙面中間凹陷、下面堆成圓錐 | 換階段色 |
| 月相 | 168 圓 | 由滿月慢慢缺成新月 | 換階段色 |
| 水位 | 168 圓 | 水位＝剩下的時間；兩道波浪每秒挪一點（暫停就停），淹到的數字反白 | 換階段色 |
| 包浩斯 | 164 方 | 紅圓裡的扇形隨時間收縮；右上四片四分之一圓記輪數 | 黑帶上一個藍色半圓 |
| 極簡環 | 168 圓 | 圓頭粗弧往回縮，末端一顆圓鈕；分鐘大字、秒數小字 | 換階段色 |
| 車站鐘 | 168 圓 | 分針一圈＝這一段的長度，外緣紅色細弧＝剩下的時間，紅色秒針每秒跳一格 | 錶面小字「休息」 |

- **進度一律表示「剩多少」**，跟倒數的數字同一個方向：沙往下流、水位下降、月亮由滿到缺。
- **有自己配色身分的風格不改色**（像素、翻頁鐘、LCD、包浩斯、車站鐘），休息時改用小標記區分。
  掌機的四階綠、液晶的灰綠、黑白紅的車站鐘，換成階段色就不是它們了。
- 像素數字和七段顯示都是**在程式裡畫的**（`Sources/PixelGlyphs.swift`），不附字型檔，沒有授權問題。
- **車站鐘刻意不叫「瑞士鐵路鐘」**，秒針也不做尖端的紅色圓盤：那是瑞士聯邦鐵路（SBB）
  受保護的設計（Apple 在 iOS 用了類似的樣子後付過授權費），而這個 repo 是公開的。
  這裡用的是一般的紅色細秒針加尾端配重。
- 按鈕、任務欄、設定頁維持原本的主題，只有錶盤本身換風格。
- 設定頁的縮圖吃固定的範例資料、不訂閱計時器，開著設定頁時十個縮圖不會每秒跟著重畫。

## 縮小模式後面的方框：為什麼改用系統陰影

原本縮小模式的圓盤用 SwiftUI 的 `.shadow(radius: 12, y: 4)`，陰影要伸出約 16pt，
但圓盤離視窗邊緣只有 6pt，超出的部分被視窗邊界硬切掉，切口就是圓盤後面那一圈方框。

現在改成 `panel.hasShadow = true`，由視窗伺服器依內容的透明度輪廓算陰影、**畫在視窗外面**：

- 不會被視窗邊界切掉，而且自動跟著每個風格的形狀走（方的錶盤就是方的陰影）
- 系統陰影是**算一次就快取**的，所以：
  - 輪廓本身不縮放——提醒時的呼吸只縮裡面的內容，輪廓一動陰影就對不上
  - 閒置淡出改用 `panel.alphaValue`，不用 SwiftUI 的 `opacity`；
    只把內容調淡的話，會變成很淡的錶盤配一圈全黑的陰影。`alphaValue` 會連陰影一起淡
  - 切換模式或風格後，等縮放動畫結束再 `invalidateShadow()` 一次
- 輪廓外的透明角落不吃點擊，點下去會穿到後面的 App

**拖曳不再被當成點擊**：視窗跟著游標移動，放開時游標在視窗內的座標跟按下時幾乎一樣，
SwiftUI 會把它看成原地按下放開＝一次點擊（提醒中拖一下就被誤確認）。
現在拖動超過 3pt 的話，放開事件會被改到視窗外面再交給 SwiftUI，它就會當成「拖出去取消」。
小於 3pt 的晃動仍算點擊。

## 為什麼視窗是 NSPanel 而不是 SwiftUI 的 WindowGroup

浮動小工具需要的是 `NSPanel`。用 `WindowGroup` 會有三個問題：

1. 視窗被文字輸入搶成 key window 時，系統會把 App 拉回它原本的 Space，
   視窗就「卡」在主桌面不再跟著你走
2. SwiftUI 會重設我們設過的視窗屬性，只能趁畫面更新時補回去；
   使用者一停止操作就沒機會補
3. hosting view 會反過來決定視窗尺寸，跟自訂的縮放動畫互相打架

`NSPanel` 的 `.nonactivatingPanel` 讓人可以操作視窗而不會啟動 App、不會換 Space；
`hosting.sizingOptions = []` 則讓尺寸完全由我們決定。

不過用 `NSPanel` 有三個陷阱：

- **絕對不能讓 `applicationShouldTerminateAfterLastWindowClosed` 回傳 true。**
  AppKit 判斷「最後一個視窗」時不把 NSPanel 算進去，所以只要任何視窗關閉
  （例如關掉設定或紀錄的 sheet），它就認為一個視窗都不剩而結束整個 App。
  因為是正常結束，不會留下 crash log，看起來就是毫無徵兆的閃退。
  關閉改走 `windowShouldClose` 明確呼叫 terminate。

另外兩個預設行為也要關掉：

- **Esc 會關閉視窗**（`cancelOperation`）。常駐小工具被關掉就等於 App 結束，
  看起來像閃退。`FloatingPanel` 把 Esc 改成只取消文字欄位的焦點。
- **`hidesOnDeactivate` 預設為 true**，App 一失焦視窗就自己躲起來。

另外縮小模式用 `.borderless`：有標題列的視窗會自己畫一層圓角底加模糊，
就算把背景設成透明，那層底還是會在圓盤後面透出來。

## 效能：為什麼浮在全螢幕上面不能一直重畫

浮動視窗每重畫一次，系統就得把它重新合成到底下那個全螢幕 App 上面。
所以「安定下來不動」比「畫得漂亮」重要。原本跑動時要 **11.3% CPU**，
現在是 **0.4%**（縮小模式）／**1.0%**（完整模式），暫停時是 0%。

三個原因，都不明顯：

1. **指針的隱式動畫永遠不會結束。** `Dial` 的指針原本掛
   `.animation(.linear(duration: 0.25), value: progress)`，而 `progress`
   每 0.2 秒就變一次——等於每次都重啟一段新動畫，視窗以螢幕更新率
   （ProMotion 最高 120Hz）持續重繪，永遠不會安定。拿掉隱式動畫即可；
   一秒走 0.24 度，本來就不需要補間。
2. **60 根刻度是 60 個 view。** 每根 Capsule 帶兩層 frame 加 rotationEffect，
   每次重畫要重建兩百多個 view modifier。改成 `Ticks` 這個 Shape，
   一次畫成一條路徑，整個錶盤只剩三層。
3. **每 0.2 秒發佈一次 `remaining`。** 畫面以 5Hz 重畫，但顯示的秒數一秒才變一次。
   改成只在「顯示出來的秒數真的變了」才發佈。內部仍然每 0.2 秒檢查，
   所以「時間到」的判定精度不變。

十種錶盤風格都照同樣的規則畫：用 Shape／Path／Canvas、不綁 `progress` 的隱式動畫、
只吃 1Hz 的更新。唯一的動畫是翻頁鐘的翻頁，它綁在「一分鐘才變一次」的分鐘數上，
0.35 秒翻完就停。實測計時中每個風格、縮小和完整模式都低於 3%，多半在 0.4%–1.3%；
翻頁那一刻也不到 1%。

> 改動 `Dial`、錶盤風格或計時器發佈頻率之前，先跑一次 CPU 量測（把畫面放進一個
> `.statusBar` 層級的視窗，用 `getrusage` 量跑動 vs 暫停的差距）。
> 這三個問題從程式碼上都看不出來，只有量了才知道。

## 「跳過」和「結束並記錄」的差別

兩個動作**刻意分開**，語意才不會混在一起：

- **跳過**＝這段不算。不寫任何紀錄，輪數也不推進。
- **結束並記錄**＝這段算，只是提早收。寫入實際專注的分鐘數、推進輪數，然後進入休息。

實際專注時間是 `total - remaining` 算出來的。`remaining` 只在計時中減少，
所以中間暫停多久都不會被算進去。

## 提醒脈動的條件

**只要處於「提醒中」就會呼吸**——一段結束後、你按掉之前。相位由 `PomodoroModel.breath`
用計時器驅動，每 `Metrics.pulse` 秒翻一次。

放在 model 而不是各自的 view，是因為原本兩個毛病合起來會變成「有時候會、有時候不會」：

1. 兩個模式各有自己的 `ViewState`，而且只掛 `onChange`。切換縮小／完整時整個 view
   會重建，`onChange` 不會為「已經是 true 的值」觸發，新的 view 就再也不會開始呼吸。
2. 在同一個 runloop 裡先設 `false` 再設 `true`，SwiftUI 會把更新合併，
   可能只看到最終值而認為沒有變化，`repeatForever` 就不啟動。

單一來源加明確的計時器之後，兩個模式共用同一個相位，切換模式不中斷，
也不依賴 SwiftUI 動畫的啟動時機——而且測得到（可以直接斷言它有沒有在翻轉）。

## 熱鍵是怎麼做的

三層，各自解決不同情況：

1. **全域熱鍵**（`Sources/Hotkeys.swift`）用 Carbon 的 `RegisterEventHotKey`，
   **不需要任何權限**——`CGEventTap` 才要輔助使用授權，為了熱鍵去要求錄製鍵盤
   的權限代價太高。一律帶 ⌃⌥：純空白鍵當全域熱鍵會把整個系統的空白鍵吃掉。
   某組鍵被別的 App 先佔走時只跳過那一組，不會整組放棄。
2. **視窗有焦點時的純按鍵**在 `FloatingPanel.keyDown`。
   第一回應者是文字欄位時整個讓開，不然空白鍵打不出空格。
3. **選單列**的 ⌘ 組合，App 在前景時有效，也負責讓人看得到有哪些鍵。

⌘↩ 刻意只放在選單列，不放在 SwiftUI 按鈕上：縮小模式沒有那顆按鈕，
放選單才是兩種模式都有效，也不會兩邊搶同一組鍵。

## 關於背景白噪音

用 macOS 內建的：**系統設定 → 輔助使用 → 音訊 → 背景音效**，
有雨聲、海洋、溪流和三種噪音，都是 Apple 自己的素材。
設定頁的「背景音效」區塊有按鈕可以直接跳過去。

**一鍵開關**：系統設定 → 控制中心 → 聽力，設成「在選單列中顯示」。
背景音效就在那個選單裡，讀書時點一下就開。

番茄鐘**沒辦法自動跟著專注段開關它**，三個原因都查證過：

- 沒有公開 API。偏好設定域是私有的 `com.apple.ComfortSounds`
- 音檔是按需下載的，磁碟上讀不到，所以也不能自己播 Apple 的雨聲
- **macOS 的捷徑沒有對應動作**（iOS 有「設定背景音效」，macOS 沒有暴露），
  所以連「跑一個捷徑」這條路也走不通

App 內合成白／粉／棕噪音是做得到的（零音檔），但那就不是 Apple 原生素材了。

## 提醒的幾個設計取捨

- **自動接下一段的語意改了。** 開啟時不再立刻開始下一段，而是等你按掉提醒才開始，
  最多等 5 分鐘。原因：漏聽的那幾分鐘本來是從休息時間扣掉的。
- **聲音和視覺的壽命不同。** 響鈴次數只管聲音；圓盤脈動和遮罩會撐到你確認為止。
- **響鈴一律有 5 分鐘上限**，連「直到按掉」也是。無上限的響鈴等於對著空房間尖叫。
- **音量是相對系統音量的衰減**，系統音量本身太小的話調 App 裡的沒用。
- 通知橫幅想讓它不要自動消失，要去系統設定 → 通知把番茄鐘改成「提示」樣式，
  這個程式改不了。

### 遮罩視窗的三個雷

遮罩是這個 App 裡最危險的東西：一個覆蓋所有螢幕、吃掉點擊、又沒有 Dock 圖示
可以求助的視窗。拆不掉的話使用者只剩強制結束一條路。

1. **`delegate` 必須留 nil。** `PanelController` 是 `NSWindowDelegate`，
   它的 `windowShouldClose` 直接呼叫 `NSApp.terminate`。遮罩若沾到那個 delegate，
   關遮罩就會關掉整個 App。拆除也要用 `orderOut(nil)` 而不是 `close()`。
2. **不能變成 key window。** 搶了會把使用者從別的 App 的全螢幕 Space 拽走。
   代價是 Esc 到不了遮罩，所以改成點任意處關閉。
3. **要有獨立於其他程式碼的硬逾時**（休息長度 + 2 分鐘）。就算狀態機壞掉，
   遮罩也一定會自己消失。

## 重新編譯

需要 Xcode Command Line Tools（`xcode-select --install`）。

> **不要用 `@State`。**
> macOS 26 之後的 SDK 把 `@State` 改成巨集實作，而那個巨集外掛（`SwiftUIMacros`）
> 只跟完整版 Xcode 一起出貨，純命令列工具會編不過：
> `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`。
> 本專案改用 `@StateObject` 搭配 `ViewState`（在 `ContentView.swift` 最上方）。
> `@StateObject`、`@ObservedObject`、`@EnvironmentObject`、`@FocusState`、
> `@Binding`、`@Environment` 都正常，只有 `@State` 不行。

```bash
./build.sh              # 產出到專案目錄
./build.sh ~/Desktop    # 產出到指定資料夾
```

## 檔案

| 檔案 | 內容 |
|---|---|
| `Sources/Model.swift` | 計時邏輯、偏好設定、紀錄儲存 |
| `Sources/Theme.swift` | 設計 token、刻度錶盤、輪數圓點 |
| `Sources/ContentView.swift` | 完整模式與縮小模式 |
| `Sources/DialStyle.swift` | 十種錶盤風格的名稱、尺寸、輪廓、配色 |
| `Sources/StyleDials.swift` | 每個風格的畫法，以及設定頁的縮圖 |
| `Sources/PixelGlyphs.swift` | 像素數字與七段顯示的字形 |
| `Sources/SettingsView.swift` | 設定與紀錄 sheet（標題／按鈕固定，中間可捲動） |
| `Sources/PanelController.swift` | 視窗（NSPanel）：尺寸、縮放動畫、浮動層級、位置記憶 |
| `Sources/Alarm.swift` | 響鈴：可停止、可重複、可調音量 |
| `Sources/Notifier.swift` | 系統通知（發聲已移到 Alarm） |
| `Sources/OverlayController.swift` | 休息全螢幕遮罩 |
| `Sources/Diagnostics.swift` | 結束／例外記錄到 `~/Library/Logs/番茄鐘.log` |
| `Sources/main.swift` | App 進入點 |
| `Sources/MenuController.swift` | 選單列、時間組合的 ⌘1–⌘4 |
| `Tools/MakeIcon.swift` | 產生 App 圖示 |

設定與紀錄存在 `UserDefaults`（bundle id `local.pomodoro.timer`）。

## 授權

MIT，詳見 [LICENSE](LICENSE)。

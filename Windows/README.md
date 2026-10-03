# Pomodoro Timer — Windows 實用版

Windows 11 x64。解壓 ZIP 後直接開啟 `Pomodoro.exe`，不必另外安裝 .NET 或取得管理員權限。

番茄鐘／倒數／碼錶；專注與休息長度可調；任務、紀錄、今日統計；聲音與持續視覺提醒；
可置頂與拖曳的縮小錶盤；小／中／大尺寸；重開後選擇接續、恢復並暫停或重新開始。
聲音固定響三次，視覺提醒會持續至按「停止提醒」；縮小時從右鍵選單操作。

資料獨立保存在 `%LOCALAPPDATA%\PomodoroTimer\state.json`，不寫進下載資料夾。
正常退出及操作時保存，計時中每十秒保存；突然中止最多可能遺失最後約十秒的進度。
App 關閉期間不計時，不會補記完成紀錄；本版沒有跨平台同步。

未購買程式簽章憑證，因此 Windows SmartScreen 可能顯示「Windows 已保護您的電腦」。
只從 https://github.com/kalovee/pomodoro-mac/releases 下載並核對 SHA256SUMS.txt。
確認來源後，可使用警告中的「其他資訊 → 仍要執行」（如果系統政策允許）。
不需要關閉 Defender 或 SmartScreen；若由學校／公司管理，請遵守管理政策。

這是實用版，只有經典錶盤，沒有 Mac 版其餘十二種風格、全域快捷鍵、休息遮罩或進階週統計。
置頂適用一般桌面與瀏覽器全螢幕，不保證蓋過獨佔全螢幕遊戲、安全桌面或其他強制置頂視窗。
Windows ARM 和舊版 Windows 不列入本次驗收。

Developer checks: `dotnet run --project Windows/Tests -c Release`
Publish: `dotnet publish Windows/App -c Release -r win-x64 --self-contained true`
Native UI probe (isolated folder required): `Pomodoro.exe --smoke-test --data-dir C:\Temp\pomodoro-test`

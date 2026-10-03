using System.Text.Json;
using Pomodoro.Core;

var checks = 0;
void Check(bool condition, string message)
{
    if (!condition) throw new Exception("FAIL: " + message);
    checks++; Console.WriteLine("PASS: " + message);
}
double time = 0;
var date = new DateTimeOffset(2026, 10, 3, 12, 0, 0, TimeSpan.FromHours(8));
var path = Path.Combine(Path.GetTempPath(), "pomodoro-tests-" + Guid.NewGuid());
var store = new StateStore(path);
var model = new TimerEngine(store, () => time, () => date);
Check(model.PendingRecovery == null && model.Remaining == 1500, "fresh install");
model.SetTask("閱讀國際關係"); model.Start(); time += 61.25; model.Tick(); model.Pause();
Check(Math.Abs(model.Remaining - 1438.75) < .001 && !model.Running, "precise pause");
var left = model.Remaining; time += 50000;
var recovered = new TimerEngine(store, () => time, () => date);
Check(recovered.PendingRecovery?.Task == "閱讀國際關係", "task checkpoint");
recovered.Recover(false);
Check(recovered.Remaining == left && !recovered.Running && recovered.Sessions.Count == 0, "closed time frozen, no duplicate history");
recovered.Start(); time += 1; recovered.Tick(); recovered.Pause();
Check(recovered.Remaining == left - 1, "resumes from saved remainder");
var fresh = new TimerEngine(store, () => time, () => date); fresh.DiscardRecovery();
Check(new TimerEngine(store).PendingRecovery == null, "discard checkpoint");
fresh.ApplySettings(fresh.Settings with { WorkMinutes = 1, ShortMinutes = 1, LongMinutes = 2, Rounds = 2 });
fresh.Start(); time += 60; fresh.Tick();
Check(fresh.Sessions.Count == 1 && fresh.Phase == Phase.ShortBreak && fresh.Round == 1 && fresh.Alerting, "work completion records and advances");
fresh.Tick(); fresh.Tick();
Check(fresh.Sessions.Count == 1, "completion cannot duplicate");
var restoredBreak = new TimerEngine(store, () => time, () => date); restoredBreak.Recover(false);
Check(restoredBreak.Phase == Phase.ShortBreak && restoredBreak.Round == 1 && restoredBreak.Sessions.Count == 1, "break phase and history restore");
restoredBreak.Start(); time += 60; restoredBreak.Tick();
Check(restoredBreak.Phase == Phase.Work && restoredBreak.Sessions.Count == 1, "break adds no session");
restoredBreak.Start(); time += 60; restoredBreak.Tick();
Check(restoredBreak.Phase == Phase.LongBreak && restoredBreak.Round == 0 && restoredBreak.Remaining == 120, "long break after configured rounds");
restoredBreak.Skip();
Check(restoredBreak.Phase == Phase.Work && restoredBreak.Sessions.Count == 2, "skip does not record");
restoredBreak.ApplySettings(restoredBreak.Settings with { AutoContinue = true });
restoredBreak.Start(); time += 60; restoredBreak.Tick();
Check(restoredBreak.Running && restoredBreak.Alerting && restoredBreak.Phase == Phase.ShortBreak, "auto continue preserves visual alert");
restoredBreak.Acknowledge();
Check(restoredBreak.Running && !restoredBreak.Alerting, "acknowledge does not interrupt next segment");
restoredBreak.Pause();
restoredBreak.ApplySettings(restoredBreak.Settings with { Mode = TimerMode.Countdown, CountdownMinutes = 1 });
var count = restoredBreak.Sessions.Count;
restoredBreak.Start(); time += 60; restoredBreak.Tick();
Check(!restoredBreak.Running && restoredBreak.Alerting && restoredBreak.Sessions.Count == count, "countdown completes once without records or auto continue");
restoredBreak.ApplySettings(restoredBreak.Settings with { Mode = TimerMode.Stopwatch });
restoredBreak.Start(); time += 123.5; restoredBreak.Tick(); restoredBreak.Pause();
Check(restoredBreak.Elapsed == 123.5, "stopwatch elapsed");
var watch = new TimerEngine(store, () => time, () => date); watch.Recover(true); time += 10; watch.Tick(); watch.Pause();
Check(watch.Elapsed == 133.5, "stopwatch recovery continues accumulated time");
watch.RecordProgress();
Check(watch.Sessions.Count == count + 1 && watch.Sessions.Last().Minutes == 2 && watch.Elapsed == 0, "stopwatch manual record uses actual minutes");
watch.RecordProgress(); Check(watch.Sessions.Count == count + 1, "manual record cannot duplicate");
watch.ApplySettings(watch.Settings with { Mode = TimerMode.Pomodoro, WorkMinutes = 25 });
watch.Start(); time += 125; watch.Tick(); watch.RecordProgress();
Check(watch.Sessions.Last().Minutes == 2 && watch.Phase == Phase.ShortBreak && watch.Round == 0, "partial work logs actual duration without completed round");
Check(watch.TodayMinutes == watch.Sessions.Sum(s => s.Minutes), "today derived from sessions");
date = date.AddDays(1); Check(watch.TodayCount == 0 && watch.TodayMinutes == 0, "midnight statistics boundary");
watch.DeleteSession(watch.Sessions.Last().Id); Check(watch.Sessions.Count == count + 1, "delete one record persists");
watch.ClearHistory(); Check(new TimerEngine(store).Sessions.Count == 0, "clear history persists");
Check(!(new Settings { WorkMinutes = 0 }).Valid && !(new Settings { Rounds = 13 }).Valid, "settings validation");
foreach (var size in Enum.GetValues<CompactSize>())
{
    watch.ApplySettings(watch.Settings with { Size = size });
    Check(new TimerEngine(store).Settings.Size == size, "compact size persists: " + size);
}
watch.ApplySettings(watch.Settings with { Mode = TimerMode.Countdown }); watch.Start(); time += 11; watch.Tick();
var rejectedWhileRunning = false;
try { watch.ApplySettings(watch.Settings with { CountdownMinutes = 2 }); }
catch (InvalidOperationException) { rejectedWhileRunning = true; }
Check(rejectedWhileRunning && watch.Running && watch.Settings.CountdownMinutes == 1,
    "running duration edits rejected without changing timer");
var checkpoint = new TimerEngine(store).PendingRecovery;
Check(checkpoint != null && Math.Abs(checkpoint.Remaining - watch.Remaining) < .001, "periodic checkpoint at ten seconds");
watch.Pause();
File.WriteAllText(Path.Combine(path, "state.json"), "not JSON");
var damaged = new TimerEngine(store);
Check(damaged.Sessions.Count == 0 && damaged.PendingRecovery == null && damaged.StorageError != null, "corrupt data fallback is visible");
Check(Directory.GetFiles(path, "state.json.unreadable-*").Length == 1, "corrupt original retained");
var deniedPath = Path.Combine(path, "not-a-directory"); File.WriteAllText(deniedPath, "blocking file");
var denied = new TimerEngine(new StateStore(deniedPath)); denied.SetTask("保存測試");
Check(denied.StorageError != null, "write failure visible without crash");
Console.WriteLine($"{checks} core checks passed. Isolated data: {path}");

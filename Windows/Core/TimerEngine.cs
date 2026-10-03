using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Pomodoro.Core;

public enum TimerMode { Pomodoro, Countdown, Stopwatch }
public enum Phase { Work, ShortBreak, LongBreak }
public enum CompactSize { Small, Medium, Large }

public sealed record Settings
{
    public int WorkMinutes { get; init; } = 25;
    public int ShortMinutes { get; init; } = 5;
    public int LongMinutes { get; init; } = 15;
    public int Rounds { get; init; } = 4;
    public int CountdownMinutes { get; init; } = 10;
    public bool AutoContinue { get; init; }
    public bool Sound { get; init; } = true;
    public bool AlwaysOnTop { get; init; } = true;
    public bool Compact { get; init; }
    public CompactSize Size { get; init; } = CompactSize.Medium;
    public TimerMode Mode { get; init; }
    public double? Left { get; init; }
    public double? Top { get; init; }
    public bool Valid => WorkMinutes is >= 1 and <= 180 && ShortMinutes is >= 1 and <= 180
        && LongMinutes is >= 1 and <= 180 && CountdownMinutes is >= 1 and <= 180
        && Rounds is >= 1 and <= 12 && Enum.IsDefined(Size) && Enum.IsDefined(Mode)
        && (Left == null || double.IsFinite(Left.Value)) && (Top == null || double.IsFinite(Top.Value));
    public double Scale => Size switch { CompactSize.Small => .8, CompactSize.Large => 1.25, _ => 1 };
}

public sealed record Session(Guid Id, DateTimeOffset FinishedAt, string Task, int Minutes);
public sealed record Progress(TimerMode Mode, Phase Phase, int Round, double Remaining,
    double Elapsed, string Task, DateTimeOffset SavedAt)
{
    public bool Valid => Enum.IsDefined(Mode) && Enum.IsDefined(Phase) && Round is >= 0 and < 12
        && double.IsFinite(Remaining) && Remaining is >= 0 and <= 10800
        && double.IsFinite(Elapsed) && Elapsed is >= 0 and <= 31536000 && Task != null;
}
public sealed record SavedState(int Version, Settings Settings, List<Session> Sessions, Progress? Progress);

public sealed class StateStore(string directory)
{
    private bool protectedOriginal;
    private static readonly JsonSerializerOptions Json = new()
    {
        WriteIndented = true, Converters = { new JsonStringEnumConverter() }
    };
    public string DirectoryPath { get; } = directory;
    public string? Error { get; private set; }
    private string PathName => Path.Combine(DirectoryPath, "state.json");

    public SavedState Load()
    {
        try
        {
            if (!File.Exists(PathName)) return Fresh();
            var state = JsonSerializer.Deserialize<SavedState>(File.ReadAllText(PathName), Json);
            if (state == null || state.Version != 1 || state.Settings == null || !state.Settings.Valid
                || state.Sessions == null || state.Sessions.Any(s => s == null || s.Task == null || s.Minutes <= 0))
                throw new JsonException("Invalid state");
            return state with { Sessions = state.Sessions.TakeLast(10000).ToList(),
                Progress = state.Progress is { Valid: true } ? state.Progress : null };
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or NotSupportedException)
        {
            // Keep the damaged original recoverable before allowing a new state to be saved.
            Error = "無法讀取原有資料；已使用預設設定，請查看資料資料夾。";
            try { File.Copy(PathName, PathName + ".unreadable-" + DateTime.UtcNow.Ticks); }
            catch (Exception backupError) when (backupError is IOException or UnauthorizedAccessException) { protectedOriginal = true; }
            return Fresh();
        }
    }

    public bool Save(SavedState state)
    {
        if (protectedOriginal) { Error = "原有資料讀取失敗且無法備份；暫不覆蓋，請查看資料資料夾。"; return false; }
        try
        {
            Directory.CreateDirectory(DirectoryPath);
            var temporary = PathName + ".tmp";
            using (var stream = new FileStream(temporary, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                JsonSerializer.Serialize(stream, state, Json);
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporary, PathName, overwrite: true);
            Error = null;
            return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        {
            Error = "資料無法儲存，請確認資料夾權限或剩餘空間。";
            return false;
        }
    }
    private static SavedState Fresh() => new(1, new Settings(), [], null);
}

public sealed class TimerEngine
{
    private readonly StateStore store;
    private readonly Func<double> now;
    private readonly Func<DateTimeOffset> wallClock;
    private double anchor, baseValue, lastSave;
    public Settings Settings { get; private set; }
    public TimerMode Mode => Settings.Mode;
    public Phase Phase { get; private set; } = Phase.Work;
    public int Round { get; private set; }
    public double Remaining { get; private set; }
    public double Elapsed { get; private set; }
    public bool Running { get; private set; }
    public bool Alerting { get; private set; }
    public string Task { get; private set; } = "";
    public List<Session> Sessions { get; }
    public Progress? PendingRecovery { get; private set; }
    public string? StorageError => store.Error;
    public event Action? Completed;
    public double Total => 60 * (Mode == TimerMode.Countdown ? Settings.CountdownMinutes
        : Phase switch { Phase.ShortBreak => Settings.ShortMinutes, Phase.LongBreak => Settings.LongMinutes,
            _ => Settings.WorkMinutes });
    public double FocusElapsed => Mode == TimerMode.Stopwatch ? Elapsed : Total - Remaining;
    public bool CanRecord => (Mode == TimerMode.Stopwatch || Mode == TimerMode.Pomodoro && Phase == Phase.Work)
        && FocusElapsed >= 60;
    public int TodayCount => Sessions.Count(s => s.FinishedAt.LocalDateTime.Date == wallClock().LocalDateTime.Date);
    public int TodayMinutes => Sessions.Where(s => s.FinishedAt.LocalDateTime.Date == wallClock().LocalDateTime.Date)
        .Sum(s => s.Minutes);

    public TimerEngine(StateStore store, Func<double>? clock = null, Func<DateTimeOffset>? wallClock = null)
    {
        this.store = store;
        now = clock ?? (() => (double)System.Diagnostics.Stopwatch.GetTimestamp() / System.Diagnostics.Stopwatch.Frequency);
        this.wallClock = wallClock ?? (() => DateTimeOffset.Now);
        var state = store.Load();
        Settings = state.Settings;
        Sessions = state.Sessions;
        PendingRecovery = state.Progress;
        Remaining = Total;
        lastSave = now();
    }
    public void SetTask(string text) { Task = text; Save(); }
    public void ApplySettings(Settings settings)
    {
        if (!settings.Valid) throw new ArgumentException("Invalid settings");
        var old = Settings;
        if (Running && settings.Mode == Mode && (old.WorkMinutes != settings.WorkMinutes
            || old.ShortMinutes != settings.ShortMinutes || old.LongMinutes != settings.LongMinutes
            || old.CountdownMinutes != settings.CountdownMinutes || old.Rounds != settings.Rounds))
            throw new InvalidOperationException("Pause before changing timer durations");
        if (settings.Mode != Mode) { Pause(); Phase = Phase.Work; Round = 0; Elapsed = 0; }
        Settings = settings;
        if (!Running && (old.Mode != Mode || old.WorkMinutes != settings.WorkMinutes
            || old.ShortMinutes != settings.ShortMinutes || old.LongMinutes != settings.LongMinutes
            || old.CountdownMinutes != settings.CountdownMinutes)) Remaining = Total;
        Save();
    }
    public void Toggle() { if (Running) Pause(); else Start(); }
    public void Start()
    {
        if (PendingRecovery != null || Running) return;
        Acknowledge();
        Begin(); Save();
    }
    private void Begin()
    {
        if (Mode != TimerMode.Stopwatch && Remaining <= 0) Remaining = Total;
        baseValue = Mode == TimerMode.Stopwatch ? Elapsed : Remaining;
        anchor = now(); Running = true;
    }
    private void UpdateTime()
    {
        if (!Running) return;
        var delta = Math.Max(0, now() - anchor);
        if (Mode == TimerMode.Stopwatch) Elapsed = baseValue + delta;
        else Remaining = Math.Max(0, baseValue - delta);
    }
    public void Tick()
    {
        UpdateTime();
        if (Running && Mode != TimerMode.Stopwatch && Remaining <= 0) Finish();
        if (Running && now() - lastSave >= 10) Save();
    }
    public void Pause() { UpdateTime(); Running = false; Save(); }
    public void Acknowledge() => Alerting = false;
    public void Reset()
    {
        Running = false; Acknowledge(); Elapsed = 0; Remaining = Total; Save();
    }
    public void Skip()
    {
        if (Mode != TimerMode.Pomodoro) return;
        Running = false; Acknowledge(); Advance(false); Save();
    }
    private void Advance(bool completed)
    {
        if (Phase == Phase.Work)
        {
            if (completed) Round++;
            if (Round >= Settings.Rounds) { Round = 0; Phase = Phase.LongBreak; }
            else Phase = Phase.ShortBreak;
        }
        else Phase = Phase.Work;
        Remaining = Total;
    }
    private void Finish()
    {
        Running = false;
        if (Mode == TimerMode.Pomodoro)
        {
            if (Phase == Phase.Work) Record(Settings.WorkMinutes);
            Advance(true);
        }
        else Remaining = Total;
        Alerting = true;
        if (Settings.AutoContinue && Mode == TimerMode.Pomodoro) Begin();
        Save(); Completed?.Invoke();
    }
    private void Record(int minutes)
    {
        Sessions.Add(new(Guid.NewGuid(), wallClock(), string.IsNullOrWhiteSpace(Task) ? "未命名任務" : Task.Trim(), minutes));
        if (Sessions.Count > 10000) Sessions.RemoveRange(0, Sessions.Count - 10000);
    }
    public void RecordProgress()
    {
        UpdateTime();
        if (!CanRecord) return;
        Record((int)(FocusElapsed / 60)); Running = false; Acknowledge();
        if (Mode == TimerMode.Stopwatch) Elapsed = 0;
        else Advance(false);
        Save();
    }
    public void DeleteSession(Guid id) { Sessions.RemoveAll(s => s.Id == id); Save(); }
    public void ClearHistory() { Sessions.Clear(); Save(); }
    public void Recover(bool startImmediately)
    {
        if (PendingRecovery is not { } saved) return;
        Settings = Settings with { Mode = saved.Mode };
        Phase = saved.Phase; Round = Math.Min(saved.Round, Settings.Rounds - 1);
        Remaining = Math.Min(Total, saved.Remaining); Elapsed = saved.Elapsed; Task = saved.Task;
        PendingRecovery = null;
        if (startImmediately) Start(); else Save();
    }
    public void DiscardRecovery() { PendingRecovery = null; Save(); }
    public void Save()
    {
        UpdateTime();
        var progress = PendingRecovery;
        if (progress == null && (Running || Remaining < Total || Elapsed > 0 || Round > 0
            || Phase != Phase.Work || !string.IsNullOrWhiteSpace(Task)))
            progress = new(Mode, Phase, Round, Remaining, Elapsed, Task, wallClock());
        store.Save(new(1, Settings, Sessions, progress)); lastSave = now();
    }
}

using System.IO;
using System.Media;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Pomodoro.Core;

namespace Pomodoro.Windows;

internal sealed class MainWindow : Window
{
    public TimerEngine Model { get; }
    private readonly DispatcherTimer ticker;
    private readonly DialDisplay dial;
    private Button? play, record, acknowledge;
    private TextBlock? summary, error;
    private TextBox? task;
    private ComboBox? modes;
    private bool rebuilding;
    private Point? dragStart;
    private Point dragOrigin;
    private bool dragging;
    private int ringsLeft;
    private DateTime nextRing;
    private string lastDisplay = "";
    public Button PlayButton => play!;
    public double CompactDiameter => 168 * Model.Settings.Scale;
    public bool IsDragging => dragging;

    public MainWindow(TimerEngine model)
    {
        Model = model;
        Title = "番茄鐘 · Pomodoro";
        WindowStyle = WindowStyle.None; AllowsTransparency = true; Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize; FontFamily = new FontFamily("Microsoft JhengHei UI");
        FontSize = 14; WindowStartupLocation = WindowStartupLocation.CenterScreen;
        dial = new(model);
        Resources.Add(typeof(Button), MakeButtonStyle());
        Build();
        Loaded += (_, _) => RestorePosition();
        LocationChanged += (_, _) => { /* Persist on release/exit, not every mouse movement. */ };
        Closing += (_, _) => { RememberPosition(); Model.Save(); ticker?.Stop(); };
        model.Completed += () => { ringsLeft = 3; nextRing = DateTime.MinValue; };
        ticker = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        ticker.Tick += (_, _) =>
        {
            Model.Tick();
            if (!Model.Alerting) ringsLeft = 0;
            if (Model.Settings.Sound && ringsLeft > 0 && DateTime.UtcNow >= nextRing)
            { SystemSounds.Asterisk.Play(); ringsLeft--; nextRing = DateTime.UtcNow.AddSeconds(2); }
            var state = $"{Math.Ceiling(Model.Remaining)}:{Math.Ceiling(Model.Elapsed)}:{Model.Running}:{Model.Alerting}:{Model.Phase}";
            if (state != lastDisplay || Model.Alerting) { Refresh(); lastDisplay = state; }
        };
        ticker.Start();
    }
    private static Style MakeButtonStyle()
    {
        var style = new Style(typeof(Button));
        style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(10, 6, 10, 6)));
        style.Setters.Add(new Setter(Control.MarginProperty, new Thickness(3)));
        style.Setters.Add(new Setter(Control.BackgroundProperty, new SolidColorBrush(Color.FromRgb(245, 238, 224))));
        style.Setters.Add(new Setter(Control.BorderBrushProperty, new SolidColorBrush(Color.FromRgb(215, 206, 189))));
        style.Setters.Add(new Setter(Control.ForegroundProperty, Brushes.Black));
        return style;
    }
    public static Button Button(string text, Action action, string? help = null)
    {
        var button = new Button { Content = text, ToolTip = help ?? text };
        AutomationProperties.SetName(button, help ?? text);
        button.Click += (_, _) => action();
        return button;
    }
    private void Act(Action action) { action(); Refresh(); }
    private void Build()
    {
        rebuilding = true;
        // Detach the reusable dial before replacing its old visual parent.
        if (dial.Parent is Panel parent) parent.Children.Remove(dial);
        Topmost = Model.Settings.AlwaysOnTop;
        var compact = Model.Settings.Compact;
        Width = compact ? CompactDiameter : 380;
        Height = compact ? CompactDiameter : 620;
        dial.Compact = compact;
        play = Button("開始", () => Act(Model.Toggle), "開始或暫停");
        if (compact)
        {
            var grid = new Grid { Width = 168, Height = 168 };
            dial.Width = dial.Height = 168;
            grid.Children.Add(dial);
            var controls = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 20) };
            play.Padding = new Thickness(5, 2, 5, 2); play.FontSize = 12;
            var expand = Button("↗", () => SetCompact(false), "放大");
            expand.Padding = new Thickness(5, 2, 5, 2); expand.FontSize = 12;
            controls.Children.Add(play); controls.Children.Add(expand); grid.Children.Add(controls);
            Content = new Viewbox { Child = grid, Stretch = Stretch.Uniform };
            task = null; modes = null; record = null; acknowledge = null; summary = null; error = null;
        }
        else
        {
            var panel = new StackPanel { Margin = new Thickness(18, 10, 18, 16) };
            var titleRow = new DockPanel();
            var close = Button("×", Close, "結束番茄鐘"); DockPanel.SetDock(close, Dock.Right); titleRow.Children.Add(close);
            var shrink = Button("↙", () => SetCompact(true), "縮小"); DockPanel.SetDock(shrink, Dock.Right); titleRow.Children.Add(shrink);
            titleRow.Children.Add(new TextBlock { Text = "番茄鐘", FontWeight = FontWeights.SemiBold, FontSize = 20, VerticalAlignment = VerticalAlignment.Center });
            panel.Children.Add(titleRow);
            modes = new ComboBox { ItemsSource = new[] { "番茄鐘", "倒數", "碼錶" }, SelectedIndex = (int)Model.Mode, Margin = new Thickness(3, 8, 3, 8) };
            modes.SelectionChanged += (_, _) =>
            {
                if (!rebuilding && modes.SelectedIndex >= 0) Act(() => Model.ApplySettings(Model.Settings with { Mode = (TimerMode)modes.SelectedIndex }));
            };
            panel.Children.Add(modes);
            task = new TextBox { Text = Model.Task, MaxLength = 500, Margin = new Thickness(3, 4, 3, 8), Padding = new Thickness(8), ToolTip = "正在做什麼？任務會存進完成紀錄。" };
            AutomationProperties.SetName(task, "任務名稱");
            task.TextChanged += (_, _) => { if (!rebuilding) Model.SetTask(task.Text); };
            panel.Children.Add(task);
            dial.Width = dial.Height = 244; dial.HorizontalAlignment = HorizontalAlignment.Center;
            panel.Children.Add(dial);
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            buttons.Children.Add(Button("重設", () => Act(Model.Reset))); buttons.Children.Add(play);
            buttons.Children.Add(Button("跳過", () => Act(Model.Skip)));
            panel.Children.Add(buttons);
            record = Button("結束並記下進度", () => Act(Model.RecordProgress)); panel.Children.Add(record);
            acknowledge = Button("停止提醒", () => Act(Model.Acknowledge)); panel.Children.Add(acknowledge);
            summary = new TextBlock { Margin = new Thickness(3, 8, 3, 4), HorizontalAlignment = HorizontalAlignment.Center };
            panel.Children.Add(summary);
            var bottom = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
            bottom.Children.Add(Button("紀錄", ShowHistory)); bottom.Children.Add(Button("設定", () => CreateSettingsWindow().ShowDialog()));
            panel.Children.Add(bottom);
            error = new TextBlock { Foreground = Brushes.Firebrick, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(3, 8, 3, 0) };
            panel.Children.Add(error);
            var scroll = new ScrollViewer { Content = panel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
            Content = new Border { Background = new SolidColorBrush(Color.FromRgb(250, 247, 240)), BorderBrush = Brushes.Tan,
                BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(18), Child = scroll };
        }
        ContextMenu = CreateContextMenu();
        rebuilding = false;
        Refresh();
        // Small displays still leave the controls accessible through the scroll view.
        if (!compact) Height = Math.Min(Height, SystemParameters.WorkArea.Height);
        ClampPosition();
    }
    private ContextMenu CreateContextMenu()
    {
        var menu = new ContextMenu();
        void Add(string name, Action action) { var item = new MenuItem { Header = name }; item.Click += (_, _) => Act(action); menu.Items.Add(item); }
        Add("開始／暫停", Model.Toggle); Add("停止提醒", Model.Acknowledge); Add("重設", Model.Reset);
        Add("跳過", Model.Skip); Add("結束並記下進度", Model.RecordProgress);
        var sizeMenu = new MenuItem { Header = "尺寸" };
        foreach (var size in Enum.GetValues<CompactSize>())
        {
            var item = new MenuItem { Header = SizeName(size), IsCheckable = true, IsChecked = Model.Settings.Size == size };
            item.Click += (_, _) => SetSize(size); sizeMenu.Items.Add(item);
        }
        menu.Items.Add(sizeMenu);
        Add(Model.Settings.Compact ? "放大" : "縮小", () => SetCompact(!Model.Settings.Compact));
        Add(Model.Settings.AlwaysOnTop ? "取消置頂" : "浮在最上層", () => { Model.ApplySettings(Model.Settings with { AlwaysOnTop = !Model.Settings.AlwaysOnTop }); Build(); });
        Add("設定", () => CreateSettingsWindow().ShowDialog()); Add("紀錄", ShowHistory); Add("結束番茄鐘", Close);
        return menu;
    }
    public void SetCompact(bool compact) { Model.ApplySettings(Model.Settings with { Compact = compact }); ResizeAroundCenter(Build); }
    public void SetSize(CompactSize size) { Model.ApplySettings(Model.Settings with { Size = size }); ResizeAroundCenter(Build); }
    private void ResizeAroundCenter(Action change)
    {
        var x = Left + Width / 2; var y = Top + Height / 2;
        change(); Left = x - Width / 2; Top = y - Height / 2; ClampPosition(); RememberPosition();
    }
    private void Refresh()
    {
        dial.InvalidateVisual();
        play!.Content = Model.Settings.Compact ? Model.Running ? "Ⅱ" : "▶" : Model.Running ? "暫停" : "開始";
        if (record != null) { record.IsEnabled = Model.CanRecord; record.Content = $"結束並記下 {(int)(Model.FocusElapsed / 60)} 分鐘"; }
        if (acknowledge != null) acknowledge.Visibility = Model.Alerting ? Visibility.Visible : Visibility.Collapsed;
        if (summary != null) summary.Text = $"今日 {Model.TodayCount} 個 · {Model.TodayMinutes} 分鐘";
        if (error != null) error.Text = Model.StorageError ?? "";
    }
    protected override void OnPreviewMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnPreviewMouseLeftButtonDown(e);
        var current = e.OriginalSource as DependencyObject;
        while (current != null && current != this)
        {
            if (current is ButtonBase or TextBoxBase or ComboBox or ScrollBar) return;
            current = current is Visual ? VisualTreeHelper.GetParent(current) : LogicalTreeHelper.GetParent(current);
        }
        BeginDrag(PointToScreen(e.GetPosition(this))); CaptureMouse(); e.Handled = true;
    }
    public void BeginDrag(Point screenPoint) { dragStart = screenPoint; dragOrigin = new Point(Left, Top); dragging = false; }
    public void MoveDrag(Point screenPoint)
    {
        if (dragStart is not { } origin) return;
        var dpi = VisualTreeHelper.GetDpi(this);
        var dx = (screenPoint.X - origin.X) / dpi.DpiScaleX; var dy = (screenPoint.Y - origin.Y) / dpi.DpiScaleY;
        if (Math.Abs(dx) > 3 || Math.Abs(dy) > 3) dragging = true;
        if (dragging) { Left = dragOrigin.X + dx; Top = dragOrigin.Y + dy; }
    }
    public void EndDrag() { dragStart = null; dragging = false; ReleaseMouseCapture(); RememberPosition(); }
    protected override void OnPreviewMouseMove(MouseEventArgs e)
    { base.OnPreviewMouseMove(e); if (dragStart != null) { MoveDrag(PointToScreen(e.GetPosition(this))); e.Handled = true; } }
    protected override void OnPreviewMouseLeftButtonUp(MouseButtonEventArgs e)
    { base.OnPreviewMouseLeftButtonUp(e); if (dragStart != null) { EndDrag(); e.Handled = true; } }
    protected override void OnLostMouseCapture(MouseEventArgs e) { base.OnLostMouseCapture(e); dragStart = null; dragging = false; }
    private void RememberPosition() => Model.ApplySettings(Model.Settings with { Left = Left, Top = Top });
    private void RestorePosition()
    {
        if (Model.Settings.Left is { } left && Model.Settings.Top is { } top) { Left = left; Top = top; }
        ClampPosition();
    }
    private void ClampPosition()
    {
        if (!IsLoaded) return;
        // Retain positions on any attached monitor; fall back when that monitor disappears.
        var left = SystemParameters.VirtualScreenLeft; var top = SystemParameters.VirtualScreenTop;
        Left = Math.Clamp(Left, left, Math.Max(left, left + SystemParameters.VirtualScreenWidth - Width));
        Top = Math.Clamp(Top, top, Math.Max(top, top + SystemParameters.VirtualScreenHeight - Height));
    }
    public void OfferRecovery()
    {
        if (Model.PendingRecovery is not { } saved) return;
        var dialog = Dialog("繼續上次的計時嗎？", 420, 280);
        var stack = new StackPanel { Margin = new Thickness(20) };
        stack.Children.Add(new TextBlock { Text = $"{(string.IsNullOrWhiteSpace(saved.Task) ? "未命名任務" : saved.Task)}\n{DialDisplay.PhaseName(saved.Phase)} · {DialDisplay.Clock(saved.Mode == TimerMode.Stopwatch ? saved.Elapsed : saved.Remaining)}\n\n關閉期間不計時；恢復不會新增完成紀錄。", TextWrapping = TextWrapping.Wrap });
        void Choice(string label, Action action) => stack.Children.Add(Button(label, () => { action(); dialog.Close(); }));
        Choice("繼續計時", () => Model.Recover(true)); Choice("恢復並暫停", () => Model.Recover(false)); Choice("重新開始", Model.DiscardRecovery);
        dialog.Content = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        dialog.Closing += (_, e) => { if (Model.PendingRecovery != null) e.Cancel = true; };
        dialog.ShowDialog(); Build();
    }
    private Window Dialog(string title, double width, double height) => new()
    { Title = title, Width = width, Height = height, Owner = this, WindowStartupLocation = WindowStartupLocation.CenterOwner,
        Background = new SolidColorBrush(Color.FromRgb(250, 247, 240)), FontFamily = FontFamily, FontSize = 14, Topmost = Topmost };
    public Window CreateSettingsWindow()
    {
        var dialog = Dialog("設定", 360, 470);
        dialog.MinHeight = 260; dialog.MinWidth = 300;
        var stack = new StackPanel { Margin = new Thickness(18) };
        TextBox Number(string name, int value)
        {
            stack.Children.Add(new TextBlock { Text = name, Margin = new Thickness(3, 8, 3, 0) });
            var input = new TextBox { Text = value.ToString(), Padding = new Thickness(6), Margin = new Thickness(3) };
            AutomationProperties.SetName(input, name); stack.Children.Add(input); return input;
        }
        var work = Number("專注（分鐘）", Model.Settings.WorkMinutes);
        var shortBreak = Number("短休息（分鐘）", Model.Settings.ShortMinutes);
        var longBreak = Number("長休息（分鐘）", Model.Settings.LongMinutes);
        var rounds = Number("幾輪後長休息", Model.Settings.Rounds);
        var countdown = Number("單次倒數（分鐘）", Model.Settings.CountdownMinutes);
        CheckBox Flag(string label, bool value)
        { var box = new CheckBox { Content = label, IsChecked = value, Margin = new Thickness(3, 10, 3, 0) }; stack.Children.Add(box); return box; }
        var auto = Flag("時間到自動接下一段", Model.Settings.AutoContinue);
        var sound = Flag("聲音提醒（固定三次）", Model.Settings.Sound);
        var onTop = Flag("浮在最上層", Model.Settings.AlwaysOnTop);
        stack.Children.Add(new TextBlock { Text = "縮小尺寸", Margin = new Thickness(3, 12, 3, 3) });
        var size = new ComboBox { ItemsSource = new[] { "小 · 80%", "中 · 100%", "大 · 125%" }, SelectedIndex = (int)Model.Settings.Size, Margin = new Thickness(3) };
        stack.Children.Add(size);
        stack.Children.Add(new TextBlock { Text = "時間 1–180 分鐘；輪數 1–12。\n暫停時修改長度會重設目前這一段。\n縮小錶盤可按右鍵操作。", TextWrapping = TextWrapping.Wrap, Foreground = Brushes.DimGray, Margin = new Thickness(3, 12, 3, 8) });
        var validation = new TextBlock { Foreground = Brushes.Firebrick, TextWrapping = TextWrapping.Wrap };
        stack.Children.Add(validation);
        stack.Children.Add(Button("儲存設定", () =>
        {
            if (!int.TryParse(work.Text, out var w) || !int.TryParse(shortBreak.Text, out var s)
                || !int.TryParse(longBreak.Text, out var l) || !int.TryParse(rounds.Text, out var r)
                || !int.TryParse(countdown.Text, out var c)) { validation.Text = "請輸入整數。"; return; }
            var settings = Model.Settings with { WorkMinutes = w, ShortMinutes = s, LongMinutes = l, Rounds = r,
                CountdownMinutes = c, AutoContinue = auto.IsChecked == true, Sound = sound.IsChecked == true,
                AlwaysOnTop = onTop.IsChecked == true, Size = (CompactSize)size.SelectedIndex };
            if (!settings.Valid) { validation.Text = "時間限 1–180 分鐘，輪數限 1–12。"; return; }
            if (Model.Running && (w != Model.Settings.WorkMinutes || s != Model.Settings.ShortMinutes
                || l != Model.Settings.LongMinutes || r != Model.Settings.Rounds || c != Model.Settings.CountdownMinutes))
            { validation.Text = "請先暫停計時，再修改時間或輪數。"; return; }
            Model.ApplySettings(settings); ResizeAroundCenter(Build); dialog.Close();
        }));
        dialog.Content = new ScrollViewer { Content = stack, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        return dialog;
    }
    private void ShowHistory()
    {
        var dialog = Dialog("完成紀錄", 440, 490);
        var root = new DockPanel { Margin = new Thickness(16) };
        var clear = Button("清除紀錄…", () =>
        {
            if (MessageBox.Show(dialog, "確定清除全部紀錄？這個動作無法復原。", "清除紀錄", MessageBoxButton.YesNo) == MessageBoxResult.Yes)
            { Model.ClearHistory(); Refresh(); dialog.Close(); }
        });
        DockPanel.SetDock(clear, Dock.Bottom); root.Children.Add(clear);
        var list = new StackPanel();
        foreach (var group in Model.Sessions.OrderByDescending(s => s.FinishedAt).GroupBy(s => s.FinishedAt.LocalDateTime.Date))
        {
            list.Children.Add(new TextBlock { Text = $"{group.Key:yyyy/MM/dd} · {group.Sum(s => s.Minutes)} 分鐘", FontWeight = FontWeights.Bold, Margin = new Thickness(3, 12, 3, 6) });
            foreach (var session in group)
            {
                var row = new TextBlock { Text = $"{session.FinishedAt.LocalDateTime:HH:mm}  {session.Task} · {session.Minutes} 分鐘", TextWrapping = TextWrapping.Wrap, Margin = new Thickness(3, 5, 3, 5) };
                var menu = new ContextMenu(); var delete = new MenuItem { Header = "刪除此筆…" };
                delete.Click += (_, _) =>
                {
                    if (MessageBox.Show(dialog, "刪除此筆紀錄？", "刪除紀錄", MessageBoxButton.YesNo) == MessageBoxResult.Yes)
                    { Model.DeleteSession(session.Id); list.Children.Remove(row); Refresh(); }
                };
                menu.Items.Add(delete); row.ContextMenu = menu; list.Children.Add(row);
            }
        }
        if (Model.Sessions.Count == 0) list.Children.Add(new TextBlock { Text = "還沒有完成紀錄。" });
        root.Children.Add(new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        dialog.Content = root; dialog.ShowDialog();
    }
    private static string SizeName(CompactSize size) => size switch { CompactSize.Small => "小", CompactSize.Large => "大", _ => "中" };
}

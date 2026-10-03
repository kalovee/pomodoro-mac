using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Pomodoro.Core;

namespace Pomodoro.Windows;

internal static class SmokeTests
{
    public static async Task Run(MainWindow main, string directory)
    {
        var lines = new List<string>();
        void Check(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException("FAIL: " + message);
            lines.Add("PASS: " + message);
            File.WriteAllLines(Path.Combine(directory, "smoke-results.txt"), lines);
        }
        async Task Layout() { await Task.Delay(120); main.UpdateLayout(); }
        main.Model.ApplySettings(main.Model.Settings with { Sound = false });
        await Layout();
        Check(main.IsVisible && main.Topmost && main.Width == 380, "published executable opens full floating window");
        var input = Descendants<TextBox>(main).First();
        input.Text = "Windows 輸入測試";
        Check(main.Model.Task == input.Text, "task text input persists without closing window");
        main.PlayButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(main.Model.Running, "start button routed click");
        main.PlayButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
        Check(!main.Model.Running && main.IsVisible, "pause button routed click");
        var mode = Descendants<ComboBox>(main).First(); mode.SelectedIndex = 1;
        Check(main.Model.Mode == TimerMode.Countdown, "mode control switches to countdown");
        mode.SelectedIndex = 2; Check(main.Model.Mode == TimerMode.Stopwatch, "mode control switches to stopwatch");
        mode.SelectedIndex = 0;
        Capture(main, Path.Combine(directory, "full.png"));
        main.SetCompact(true);
        foreach (var size in Enum.GetValues<CompactSize>())
        {
            main.SetSize(size); await Layout();
            Check(Math.Abs(main.ActualWidth - main.CompactDiameter) < 1 && Math.Abs(main.ActualHeight - main.CompactDiameter) < 1,
                "scaled compact layout fits: " + size);
            var origin = new Point(main.Left, main.Top);
            var dpi = VisualTreeHelper.GetDpi(main);
            main.BeginDrag(new Point(300, 300)); main.MoveDrag(new Point(300 + 60 * dpi.DpiScaleX, 300 + 20 * dpi.DpiScaleY));
            Check(main.IsDragging && Math.Abs(main.Left - origin.X - 60) < 1 && Math.Abs(main.Top - origin.Y - 20) < 1,
                "drag respects DPI: " + size);
            main.EndDrag();
            Check(!main.Model.Running && !main.IsDragging, "drag does not activate timer: " + size);
            main.PlayButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Check(main.Model.Running, "compact button works after drag: " + size);
            main.PlayButton.RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            Capture(main, Path.Combine(directory, "compact-" + size + ".png"));
        }
        main.SetCompact(false); await Layout();
        Check(main.Width == 380 && main.Height > 400, "expand restores full controls");
        var settings = main.CreateSettingsWindow(); settings.Height = 280; settings.Show();
        await Task.Delay(120); settings.UpdateLayout();
        var scroll = (ScrollViewer)settings.Content;
        Check(scroll.ScrollableHeight > 0, "settings has scrollable content at small height");
        scroll.ScrollToEnd(); await Task.Delay(120);
        Check(scroll.VerticalOffset > 0, "settings can scroll to lower controls");
        Capture(settings, Path.Combine(directory, "settings.png")); settings.Close();
        Check(main.IsVisible, "closing settings does not exit app");
        main.Model.Save();
        var saved = new TimerEngine(new StateStore(directory));
        Check(saved.PendingRecovery?.Task == "Windows 輸入測試", "published executable writes recoverable task");
        saved.Recover(false); Check(!saved.Running && saved.Sessions.Count == 0, "recovery is paused without duplicate sessions");
        var pending = new TimerEngine(new StateStore(directory));
        pending.ApplySettings(pending.Settings with { Compact = true });
        var recovery = new MainWindow(pending) { Owner = main };
        recovery.Show(); await Task.Delay(120);
        Exception? recoveryFailure = null;
        _ = recovery.Dispatcher.BeginInvoke(new Action(() =>
        {
            try
            {
                var dialog = recovery.OwnedWindows.OfType<Window>().Single();
                var choices = Descendants<Button>(dialog).ToList();
                Check(choices.Count == 3, "native recovery dialog exposes all three choices");
                choices.Single(b => (string)b.Content == "恢復並暫停").RaiseEvent(new RoutedEventArgs(Button.ClickEvent));
            }
            catch (Exception e) { recoveryFailure = e; pending.DiscardRecovery(); foreach (Window dialog in recovery.OwnedWindows) dialog.Close(); }
        }), System.Windows.Threading.DispatcherPriority.ApplicationIdle);
        recovery.OfferRecovery();
        if (recoveryFailure != null) throw recoveryFailure;
        Check(pending.PendingRecovery == null && !pending.Running && pending.Task == "Windows 輸入測試",
            "native recovery choice restores paused task");
        Check(Math.Abs(recovery.Width - recovery.CompactDiameter) < 1, "compact recovery retains saved size");
        recovery.Close();
        File.AppendAllText(Path.Combine(directory, "smoke-results.txt"), $"{lines.Count} native UI checks passed. Synthetic events, not physical desktop interaction.\n");
    }
    private static IEnumerable<T> Descendants<T>(DependencyObject root) where T : DependencyObject
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is T result) yield return result;
            foreach (var nested in Descendants<T>(child)) yield return nested;
        }
    }
    private static void Capture(Window window, string path)
    {
        window.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(window.ActualWidth), (int)Math.Ceiling(window.ActualHeight), 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(window);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path); encoder.Save(stream);
    }
}

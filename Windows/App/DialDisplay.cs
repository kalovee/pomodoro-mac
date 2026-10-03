using System.Globalization;
using System.Windows;
using System.Windows.Media;
using Pomodoro.Core;

namespace Pomodoro.Windows;

internal sealed class DialDisplay(TimerEngine model) : FrameworkElement
{
    public bool Compact { get; set; }
    public static string Clock(double seconds)
    {
        var s = (int)Math.Max(0, Math.Ceiling(seconds));
        return s >= 3600 ? $"{s / 3600}:{s / 60 % 60:00}:{s % 60:00}" : $"{s / 60:00}:{s % 60:00}";
    }
    public static string PhaseName(Phase phase) => phase switch
    { Phase.ShortBreak => "短休息", Phase.LongBreak => "長休息", _ => "專注" };
    protected override void OnRender(DrawingContext dc)
    {
        var size = Math.Min(ActualWidth, ActualHeight);
        var center = new Point(ActualWidth / 2, ActualHeight / 2);
        var r = size / 2 - 5;
        var color = model.Phase switch
        { Phase.ShortBreak => Color.FromRgb(47, 139, 108), Phase.LongBreak => Color.FromRgb(70, 125, 181), _ => Color.FromRgb(220, 87, 69) };
        var accent = new SolidColorBrush(color);
        dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(250, 247, 240)), new Pen(new SolidColorBrush(Color.FromRgb(226, 219, 207)), 1), center, r, r);
        double fraction = model.Mode == TimerMode.Stopwatch ? model.Elapsed % 3600 / 3600 : model.Remaining / model.Total;
        for (var i = 0; i < 60; i++)
        {
            var angle = i * Math.PI / 30 - Math.PI / 2;
            var a = new Point(center.X + Math.Cos(angle) * (r - 8), center.Y + Math.Sin(angle) * (r - 8));
            var b = new Point(center.X + Math.Cos(angle) * (r - (i % 5 == 0 ? 19 : 14)), center.Y + Math.Sin(angle) * (r - (i % 5 == 0 ? 19 : 14)));
            dc.DrawLine(new Pen(i < fraction * 60 || model.Alerting ? accent : Brushes.LightGray, i % 5 == 0 ? 2 : 1.2), a, b);
        }
        if (model.Alerting)
        {
            var alpha = .35 + .3 * Math.Sin(DateTime.UtcNow.TimeOfDay.TotalSeconds * 4);
            var pulse = new SolidColorBrush(color) { Opacity = alpha };
            dc.DrawEllipse(null, new Pen(pulse, 5), center, r - 2, r - 2);
        }
        void Text(string value, double y, double font, Brush brush, bool bold = false)
        {
            var text = new FormattedText(value, CultureInfo.GetCultureInfo("zh-TW"), FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Microsoft JhengHei UI"), FontStyles.Normal, bold ? FontWeights.SemiBold : FontWeights.Normal, FontStretches.Normal),
                font, brush, VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(text, new Point(center.X - text.Width / 2, y - text.Height / 2));
        }
        var display = Clock(model.Mode == TimerMode.Stopwatch ? model.Elapsed : model.Remaining);
        Text(model.Mode == TimerMode.Stopwatch ? "碼錶" : model.Mode == TimerMode.Countdown ? "倒數" : PhaseName(model.Phase), size * .33, size * .068, accent);
        Text(display, size * .50, size * (display.Length > 5 ? .14 : .19), Brushes.Black, true);
        Text(model.Alerting ? "時間到了 · 請停止提醒" : model.Mode == TimerMode.Pomodoro ? $"第 {model.Round + 1} / {model.Settings.Rounds} 輪" : model.Running ? "計時中" : "已暫停",
            size * .65, size * (Compact ? .057 : .065), Brushes.DimGray);
    }
    protected override HitTestResult? HitTestCore(PointHitTestParameters parameters)
    {
        var p = parameters.HitPoint;
        var r = Math.Min(ActualWidth, ActualHeight) / 2 - 5;
        return Math.Pow(p.X - ActualWidth / 2, 2) + Math.Pow(p.Y - ActualHeight / 2, 2) <= r * r
            ? new PointHitTestResult(this, p) : null;
    }
}

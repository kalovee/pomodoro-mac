using System.IO;
using System.Windows;
using Pomodoro.Core;

namespace Pomodoro.Windows;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        var smoke = args.Contains("--smoke-test");
        var index = Array.IndexOf(args, "--data-dir");
        if (smoke && (index < 0 || index + 1 >= args.Length)) return 2;
        var directory = index >= 0 && index + 1 < args.Length ? args[index + 1]
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PomodoroTimer");
        Directory.CreateDirectory(directory);
        // Only one process may write this user's state. Smoke tests always use their own directory.
        FileStream stateLock;
        try { stateLock = new FileStream(Path.Combine(directory, "instance.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
        catch (IOException)
        {
            if (!smoke) MessageBox.Show("番茄鐘已經開啟。請從工作列切換回原有視窗。", "番茄鐘");
            return smoke ? 2 : 0;
        }
        using (stateLock)
        {
            var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            var model = new TimerEngine(new StateStore(directory));
            var main = new MainWindow(model);
            app.MainWindow = main;
            var startupHandled = false;
            if (smoke)
                main.ContentRendered += async (_, _) =>
                {
                    // WPF raises ContentRendered again when compact/full content is replaced.
                    if (startupHandled) return;
                    startupHandled = true;
                    try { await SmokeTests.Run(main, directory); app.Shutdown(0); }
                    catch (Exception e) { File.WriteAllText(Path.Combine(directory, "smoke-failed.txt"), e.ToString()); app.Shutdown(1); }
                };
            else main.ContentRendered += (_, _) =>
            {
                if (startupHandled) return;
                startupHandled = true;
                main.OfferRecovery();
            };
            return app.Run(main);
        }
    }
}

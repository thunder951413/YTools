using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Threading;
using YTools.Infrastructure;
using YTools.Services;

namespace YTools.Windows;

/// <summary>Application entry: self-test mode, single instance and controller wiring.</summary>
public partial class App : Application
{
    private MainController? _controller;
    private Mutex? _singleInstanceMutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        DispatcherUnhandledException += OnDispatcherUnhandledException;

        if (e.Args.Contains("--selftest"))
        {
            var code = SelfTest.Run();
            Shutdown(code);
            return;
        }

        _singleInstanceMutex = new Mutex(initiallyOwned: true, "YTools.SingleInstance", out var createdNew);
        if (!createdNew)
        {
            Shutdown();
            return;
        }

        _controller = new MainController();
        _controller.Start();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _controller?.Shutdown();
        _singleInstanceMutex?.ReleaseMutex();
        _singleInstanceMutex?.Dispose();
        base.OnExit(e);
    }

    private void OnDispatcherUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e)
    {
        try
        {
            AppPaths.EnsureDirectories();
            File.AppendAllText(
                Path.Combine(AppPaths.RootDirectory, "error.log"),
                $"[{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss}] {e.Exception}\n\n");
        }
        catch
        {
            // Never mask the original failure with a logging failure.
        }

        MessageBox.Show(
            $"YTools 遇到未处理的错误：\n{e.Exception.Message}\n\n详细日志已写入 %APPDATA%\\YTools\\error.log。",
            "YTools",
            MessageBoxButton.OK,
            MessageBoxImage.Error);
    }
}

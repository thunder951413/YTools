using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using YTools.Infrastructure;
using YTools.Models;
using YTools.Services;

namespace YTools.UI;

public partial class SettingsWindow : Window
{
    private AppPreferences? _preferences;
    private ClipboardHistoryManager? _clipboard;
    private SnippetManager? _snippets;
    private RecentDocumentsManager? _recentDocuments;
    private readonly Dictionary<NavItem, UserControl> _pages = [];
    private readonly List<NavItem> _navItems = [];
    private readonly ObservableCollection<string> _scopePaths = [];
    private readonly ObservableCollection<AliasEntry> _aliasEntries = [];
    private readonly ObservableCollection<CustomApplicationEntry> _customApplications = [];
    private readonly ObservableCollection<string> _ignoredApps = [];
    private readonly ObservableCollection<SnippetItem> _snippetItems = [];
    private HotKeyRecorder? _launcherRecorder;
    private HotKeyRecorder? _clipboardRecorder;

    public SettingsWindow()
    {
        InitializeComponent();
        ThemeService.ThemeApplied += OnThemeApplied;
        Closed += (_, _) => ThemeService.ThemeApplied -= OnThemeApplied;
        NavList.SelectionChanged += (_, _) =>
        {
            if (NavList.SelectedItem is NavItem item && _pages.TryGetValue(item, out var page))
            {
                PageHost.Content = page;
            }
        };
        SourceInitialized += (_, _) => ApplyDarkTitleBar();
    }

    public void Attach(
        AppPreferences preferences,
        ClipboardHistoryManager clipboard,
        SnippetManager snippets,
        RecentDocumentsManager recentDocuments)
    {
        _preferences = preferences;
        _clipboard = clipboard;
        _snippets = snippets;
        _recentDocuments = recentDocuments;
        DataContext = preferences;
        _scopePaths.Clear();
        foreach (var path in preferences.SearchScopePaths)
        {
            _scopePaths.Add(path);
        }

        _aliasEntries.Clear();
        foreach (var pair in preferences.ApplicationAliases)
        {
            _aliasEntries.Add(new AliasEntry(pair.Key, pair.Value));
        }

        RefreshCustomApplications();

        _ignoredApps.Clear();
        foreach (var name in preferences.ClipboardIgnoredProcessNames)
        {
            _ignoredApps.Add(name);
        }

        RefreshSnippets();
        _launcherRecorder?.Bind(preferences.LauncherHotKey);
        _clipboardRecorder?.Bind(preferences.ClipboardHotKey);
        preferences.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName is nameof(AppPreferences.Theme))
            {
                ApplyDarkTitleBar();
            }
        };
        BuildPages();
        SelectFirstTab();
    }

    public void RefreshChrome()
    {
        ApplyDarkTitleBar();
    }

    private void OnThemeApplied()
    {
        if (IsInitialized)
        {
            ApplyDarkTitleBar();
        }
    }

    public void SelectFirstTab()
    {
        if (_navItems.Count > 0)
        {
            NavList.SelectedIndex = 0;
        }
    }

    private void BuildPages()
    {
        _navItems.Clear();
        _pages.Clear();
        _navItems.AddRange(
        [
            new NavItem("通用", "\uE713"),
            new NavItem("搜索", "\uE721"),
            new NavItem("应用别名", "\uE8F1"),
            new NavItem("自定义应用", "\uE8F1"),
            new NavItem("外观", "\uE790"),
            new NavItem("快捷键", "\uE765"),
            new NavItem("剪贴板", "\uE8C8"),
            new NavItem("片段", "\uE8FD"),
            new NavItem("系统命令", "\uE756"),
            new NavItem("隐私", "\uE72E")
        ]);
        NavList.ItemsSource = _navItems;
        _pages[_navItems[0]] = SafePage("通用", BuildGeneralPage);
        _pages[_navItems[1]] = SafePage("搜索", BuildSearchPage);
        _pages[_navItems[2]] = SafePage("应用别名", BuildAliasesPage);
        _pages[_navItems[3]] = SafePage("自定义应用", BuildCustomApplicationsPage);
        _pages[_navItems[4]] = SafePage("外观", BuildAppearancePage);
        _pages[_navItems[5]] = SafePage("快捷键", BuildHotKeysPage);
        _pages[_navItems[6]] = SafePage("剪贴板", BuildClipboardPage);
        _pages[_navItems[7]] = SafePage("片段", BuildSnippetsPage);
        _pages[_navItems[8]] = SafePage("系统命令", BuildSystemCommandsPage);
        _pages[_navItems[9]] = SafePage("隐私", BuildPrivacyPage);
    }

    private UserControl SafePage(string name, Func<UserControl> build)
    {
        try
        {
            return build();
        }
        catch (Exception exception)
        {
            AppPaths.LogException(exception);
            var page = new UserControl();
            var error = new TextBlock
            {
                Text = $"页面“{name}”加载失败：{exception.Message}",
                TextWrapping = TextWrapping.Wrap
            };
            error.SetResourceReference(TextBlock.ForegroundProperty, "ErrorBrush");
            page.Content = error;
            return page;
        }
    }

    private UserControl BuildGeneralPage()
    {
        var page = new UserControl();
        var stack = new StackPanel();
        stack.Children.Add(Header("通用"));
        stack.Children.Add(CheckBox("开机启动", "LaunchAtLogin", "登录 Windows 后自动运行 YTools"));
        stack.Children.Add(CheckBox("显示托盘图标", "ShowTrayIcon", "隐藏后全局快捷键和剪贴板监听不受影响"));
        stack.Children.Add(ComboRow("主题", "Theme", EnumMetadata.ThemeOptions()));
        stack.Children.Add(ComboRow("强调色", "AccentColor", EnumMetadata.AccentOptions()));
        var launchError = new TextBlock
        {
            Style = (Style)FindResource("HintText")
        };
        launchError.SetResourceReference(TextBlock.ForegroundProperty, "ErrorBrush");
        launchError.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding(nameof(AppPreferences.LaunchAtLoginError)));
        stack.Children.Add(launchError);
        var restore = Button("恢复默认设置", () => _preferences?.RestoreDefaults());
        stack.Children.Add(restore);
        page.Content = Scroll(stack);
        return page;
    }

    private UserControl BuildSearchPage()
    {
        var page = new UserControl();
        var stack = new StackPanel();
        stack.Children.Add(Header("搜索内容"));
        var panel = new WrapPanel();
        foreach (var type in Enum.GetValues<SearchContentType>())
        {
            var box = new CheckBox
            {
                Content = type.Title(),
                Margin = new Thickness(0, 4, 18, 4),
                IsChecked = _preferences?.IsSearchContentEnabled(type) ?? true
            };
            box.Checked += (_, _) => _preferences?.SetSearchContent(type, true);
            box.Unchecked += (_, _) => _preferences?.SetSearchContent(type, false);
            panel.Children.Add(box);
        }

        stack.Children.Add(panel);
        stack.Children.Add(CheckBox("默认结果包含文件", "IncludeFilesInDefaultResults", "关闭后仅输入 open/打开 等前缀时返回文件"));
        stack.Children.Add(SliderRow("最大结果数", "MaximumSearchResults", 3, 20, 1));
        stack.Children.Add(SliderRow(
            "输入停止后搜索",
            "SearchInputDelay",
            0.05,
            0.4,
            0.025,
            valueMultiplier: 1_000,
            valueSuffix: " 毫秒",
            detail: "连续输入会重新计时；停顿达到该时间后才开始并显示最终搜索结果。"));
        stack.Children.Add(SubHeader("搜索范围"));
        stack.Children.Add(new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Text = "留空时默认搜索用户目录（Everything 可用时不受范围限制）。"
        });
        var scopeList = new ListBox
        {
            ItemsSource = _scopePaths,
            Height = 120
        };
        stack.Children.Add(scopeList);
        var scopeButtons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
        scopeButtons.Children.Add(Button("添加目录", () =>
        {
            var dialog = new Microsoft.Win32.OpenFolderDialog { Multiselect = true };
            if (dialog.ShowDialog(this) == true)
            {
                foreach (var folder in dialog.FolderNames)
                {
                    _preferences?.AddSearchScope(folder);
                    if (!_scopePaths.Contains(folder))
                    {
                        _scopePaths.Add(folder);
                    }
                }
            }
        }));
        scopeButtons.Children.Add(Button("移除", () =>
        {
            if (scopeList.SelectedItem is string path)
            {
                _preferences?.RemoveSearchScope(path);
                _scopePaths.Remove(path);
            }
        }));
        stack.Children.Add(scopeButtons);
        page.Content = Scroll(stack);
        return page;
    }

    private UserControl BuildAliasesPage()
    {
        var page = new UserControl();
        var stack = new StackPanel();
        stack.Children.Add(Header("应用别名"));
        stack.Children.Add(new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Text = "为应用添加中文名、简称或拼音别名；多个别名用逗号或分号分隔。"
        });
        var aliasList = new ListBox
        {
            ItemsSource = _aliasEntries,
            DisplayMemberPath = nameof(AliasEntry.Target),
            Height = 150
        };
        stack.Children.Add(aliasList);
        var aliasText = new TextBox
        {
            Margin = new Thickness(0, 8, 0, 0),
            ToolTip = "别名，如：微信,wechat"
        };
        stack.Children.Add(aliasText);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
        buttons.Children.Add(Button("添加应用…", () =>
        {
            var dialog = new Microsoft.Win32.OpenFileDialog
            {
                Filter = "应用 (*.exe;*.lnk;*.appref-ms)|*.exe;*.lnk;*.appref-ms",
                Multiselect = false
            };
            if (dialog.ShowDialog(this) == true)
            {
                _preferences?.AddApplicationAliasTarget(dialog.FileName);
                if (_aliasEntries.All(entry => entry.Target != dialog.FileName))
                {
                    _aliasEntries.Add(new AliasEntry(dialog.FileName, ""));
                }
            }
        }));
        buttons.Children.Add(Button("保存别名", () =>
        {
            if (aliasList.SelectedItem is AliasEntry entry)
            {
                _preferences?.SetApplicationAliases(entry.Target, aliasText.Text);
                entry.Aliases = aliasText.Text;
                aliasList.Items.Refresh();
            }
        }));
        buttons.Children.Add(Button("移除", () =>
        {
            if (aliasList.SelectedItem is AliasEntry entry)
            {
                _preferences?.RemoveApplicationAliasTarget(entry.Target);
                _aliasEntries.Remove(entry);
            }
        }));
        stack.Children.Add(buttons);
        aliasList.SelectionChanged += (_, _) =>
        {
            if (aliasList.SelectedItem is AliasEntry entry)
            {
                aliasText.Text = entry.Aliases;
            }
        };
        page.Content = Scroll(stack);
        return page;
    }

    private UserControl BuildCustomApplicationsPage()
    {
        var page = new UserControl();
        var stack = new StackPanel();
        stack.Children.Add(Header("自定义应用"));
        stack.Children.Add(new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Text = "添加本机应用或快捷方式后，它们会作为应用搜索结果显示。可为选中的应用设置搜索别名。"
        });

        var applicationList = new ListBox
        {
            ItemsSource = _customApplications,
            Height = 160,
            Margin = new Thickness(0, 6, 0, 0)
        };
        applicationList.ItemTemplate = CreateCustomApplicationTemplate();
        stack.Children.Add(applicationList);

        var applicationButtons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Margin = new Thickness(0, 8, 0, 0)
        };
        applicationButtons.Children.Add(Button("添加应用…", () =>
        {
            var dialog = new Microsoft.Win32.OpenFileDialog
            {
                Filter = "应用 (*.exe;*.lnk;*.appref-ms)|*.exe;*.lnk;*.appref-ms",
                Multiselect = false
            };
            if (dialog.ShowDialog(this) == true && _preferences is not null)
            {
                var normalizedPath = _preferences.AddCustomApplication(dialog.FileName);
                if (normalizedPath is not null)
                {
                    _preferences.AddApplicationAliasTarget(normalizedPath);
                }
                RefreshCustomApplications();
            }
        }));
        applicationButtons.Children.Add(Button("移除", () =>
        {
            if (applicationList.SelectedItem is CustomApplicationEntry entry)
            {
                _preferences?.RemoveCustomApplication(entry.Path);
                RefreshCustomApplications();
            }
        }));
        stack.Children.Add(applicationButtons);

        stack.Children.Add(SubHeader("搜索别名"));
        var aliasText = new TextBox
        {
            ToolTip = "别名，如：微信,wechat"
        };
        stack.Children.Add(aliasText);
        stack.Children.Add(Button("保存别名", () =>
        {
            if (applicationList.SelectedItem is CustomApplicationEntry entry)
            {
                _preferences?.AddApplicationAliasTarget(entry.Path);
                _preferences?.SetApplicationAliases(entry.Path, aliasText.Text);
                entry.Aliases = aliasText.Text;
                applicationList.Items.Refresh();
            }
        }));
        applicationList.SelectionChanged += (_, _) =>
        {
            aliasText.Text = applicationList.SelectedItem is CustomApplicationEntry entry
                ? entry.Aliases
                : "";
        };

        page.Content = Scroll(stack);
        return page;
    }

    private DataTemplate CreateCustomApplicationTemplate()
    {
        var template = new DataTemplate(typeof(CustomApplicationEntry));
        var panel = new FrameworkElementFactory(typeof(StackPanel));
        var name = new FrameworkElementFactory(typeof(TextBlock));
        name.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding(nameof(CustomApplicationEntry.Name)));
        name.SetValue(TextBlock.FontWeightProperty, FontWeights.SemiBold);
        name.SetResourceReference(TextBlock.ForegroundProperty, "TextPrimaryBrush");
        panel.AppendChild(name);

        var path = new FrameworkElementFactory(typeof(TextBlock));
        path.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding(nameof(CustomApplicationEntry.Path)));
        path.SetValue(TextBlock.TextWrappingProperty, TextWrapping.Wrap);
        path.SetValue(TextBlock.FontSizeProperty, 12d);
        path.SetResourceReference(TextBlock.ForegroundProperty, "TextSecondaryBrush");
        panel.AppendChild(path);
        template.VisualTree = panel;
        return template;
    }

    private UserControl BuildAppearancePage()
    {
        var page = new UserControl();
        var stack = new StackPanel();
        stack.Children.Add(Header("启动器外观"));
        stack.Children.Add(ComboRow("外观样式", "LauncherAppearanceStyle", EnumMetadata.StyleOptions()));
        stack.Children.Add(ComboRow("默认位置", "PanelPosition", EnumMetadata.PositionOptions()));
        stack.Children.Add(ComboRow("屏幕偏好", "ScreenPreference", EnumMetadata.ScreenOptions()));
        stack.Children.Add(SliderRow("面板宽度", "PanelWidth", 640, 960, 10));
        stack.Children.Add(SliderRow("圆角半径", "PanelCornerRadius", 10, 20, 1));
        stack.Children.Add(CheckBox("紧凑结果行", "CompactResults", "以更小的行高显示结果"));
        stack.Children.Add(CheckBox("显示结果副标题", "ShowSubtitles", "显示结果副标题"));
        stack.Children.Add(CheckBox("显示数字快捷键", "ShowNumberShortcuts", "显示数字快捷键"));
        stack.Children.Add(SliderRow("结果展开动画（秒）", "ResultExpansionDuration", 0, 0.4, 0.05));
        stack.Children.Add(SliderRow("预览延迟（秒）", "PreviewSelectionDelay", 0, 0.8, 0.05));
        stack.Children.Add(Button("清除使用学习", () => _preferences?.ClearUsageLearning()));
        page.Content = Scroll(stack);
        return page;
    }

    private UserControl BuildHotKeysPage()
    {
        var page = new UserControl();
        var stack = new StackPanel();
        stack.Children.Add(Header("全局快捷键"));
        stack.Children.Add(new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Text = "点击下方按键框，然后按下新的组合键。至少需要一个修饰键（Ctrl/Alt/Shift/Win）。"
        });
        _launcherRecorder = new HotKeyRecorder("启动器显示快捷键");
        _launcherRecorder.Changed += definition =>
        {
            if (_preferences is not null)
            {
                _preferences.LauncherHotKey = definition;
            }
        };
        _launcherRecorder.Bind(_preferences?.LauncherHotKey ?? HotKeyDefinition.LauncherDefault);
        stack.Children.Add(_launcherRecorder);
        _clipboardRecorder = new HotKeyRecorder("剪贴板历史快捷键");
        _clipboardRecorder.Changed += definition =>
        {
            if (_preferences is not null)
            {
                _preferences.ClipboardHotKey = definition;
            }
        };
        _clipboardRecorder.Bind(_preferences?.ClipboardHotKey ?? HotKeyDefinition.ClipboardDefault);
        stack.Children.Add(_clipboardRecorder);
        var hotKeyError = new TextBlock
        {
            Style = (Style)FindResource("HintText")
        };
        hotKeyError.SetResourceReference(TextBlock.ForegroundProperty, "ErrorBrush");
        hotKeyError.SetBinding(
            TextBlock.TextProperty,
            new System.Windows.Data.Binding(nameof(AppPreferences.HotKeyError)));
        stack.Children.Add(hotKeyError);
        page.Content = Scroll(stack);
        return page;
    }

    private UserControl BuildClipboardPage()
    {
        var page = new UserControl();
        var stack = new StackPanel();
        stack.Children.Add(Header("剪贴板历史"));
        stack.Children.Add(CheckBox("启用剪贴板历史", "ClipboardEnabled", "启用剪贴板历史"));
        stack.Children.Add(CheckBox("暂停记录", "ClipboardPaused", "暂停记录"));
        stack.Children.Add(ComboRow("保留天数", "ClipboardRetentionDays", EnumMetadata.RetentionOptions()));
        stack.Children.Add(SliderRow("最大条数", "ClipboardMaximumItems", 50, 1_000, 10));
        stack.Children.Add(SliderRow("单条文本上限（字符）", "ClipboardMaximumTextCharacters", 100, 10_000, 100));
        stack.Children.Add(CheckBox("保存图片", "ClipboardStoreImages", "图片默认关闭，单项限制 5 MB"));
        stack.Children.Add(SubHeader("忽略的进程"));
        stack.Children.Add(new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Text = "来自这些进程的剪贴板内容不会被记录（默认包含常见密码管理器）。"
        });
        var ignoredList = new ListBox
        {
            ItemsSource = _ignoredApps,
            Height = 110
        };
        stack.Children.Add(ignoredList);
        var ignoredRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
        var ignoredText = new TextBox
        {
            Width = 180,
            ToolTip = "进程名，如 1password"
        };
        ignoredRow.Children.Add(ignoredText);
        ignoredRow.Children.Add(Button("添加", () =>
        {
            if (!string.IsNullOrWhiteSpace(ignoredText.Text))
            {
                _preferences?.AddClipboardIgnoredApplication(ignoredText.Text);
                _ignoredApps.Add(ignoredText.Text.Trim().ToLowerInvariant());
                ignoredText.Clear();
            }
        }));
        ignoredRow.Children.Add(Button("移除", () =>
        {
            if (ignoredList.SelectedItem is string name)
            {
                _preferences?.RemoveClipboardIgnoredApplication(name);
                _ignoredApps.Remove(name);
            }
        }));
        stack.Children.Add(ignoredRow);
        stack.Children.Add(SubHeader("坚果云加密同步"));
        stack.Children.Add(CheckBox("启用坚果云剪贴板同步", "ClipboardCloudSyncEnabled", "仅在已保存凭据后启用；内容始终先加密再上传"));
        stack.Children.Add(new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Text = "通过 https://dav.jianguoyun.com/dav/ 使用坚果云应用密码。每条新内容独立加密上传；每 15 分钟仅拉取轻量变更标记，无变化时不下载内容。"
        });
        var syncFolder = LabeledTextBox("坚果云目录（仅字母、数字、点、下划线、连字符）", 260);
        syncFolder.Box.Text = _preferences?.ClipboardCloudSyncFolder ?? "YTools/clipboard-sync";
        syncFolder.Box.LostFocus += (_, _) =>
        {
            if (_preferences is not null)
            {
                _preferences.ClipboardCloudSyncFolder = syncFolder.Box.Text;
            }
        };
        stack.Children.Add(syncFolder.Label);
        stack.Children.Add(syncFolder.Box);
        stack.Children.Add(SliderRow("后台拉取间隔（分钟）", "ClipboardCloudSyncIntervalMinutes", 15, 240, 15));
        var username = LabeledTextBox("坚果云用户名", 260);
        var appPasswordLabel = new TextBlock { Text = "坚果云应用密码", Style = (Style)FindResource("RowLabel") };
        var appPassword = new PasswordBox { Width = 260, Margin = new Thickness(0, 4, 0, 0) };
        var syncPasswordLabel = new TextBlock { Text = "同步口令（至少 12 个字符；所有设备必须相同）", Style = (Style)FindResource("RowLabel") };
        var syncPassword = new PasswordBox { Width = 260, Margin = new Thickness(0, 4, 0, 0) };
        stack.Children.Add(username.Label);
        stack.Children.Add(username.Box);
        stack.Children.Add(appPasswordLabel);
        stack.Children.Add(appPassword);
        stack.Children.Add(syncPasswordLabel);
        stack.Children.Add(syncPassword);
        var syncStatus = new TextBlock { Style = (Style)FindResource("HintText") };
        syncStatus.SetBinding(
            TextBlock.TextProperty,
            new System.Windows.Data.Binding(nameof(ClipboardHistoryManager.CloudSyncStatus)) { Source = _clipboard });
        stack.Children.Add(Button("加密保存凭据并启用同步", () =>
        {
            if (_clipboard is null || _preferences is null)
            {
                return;
            }

            if (_clipboard.SaveCloudSyncCredentials(username.Box.Text, appPassword.Password, syncPassword.Password, out var error))
            {
                _preferences.ClipboardCloudSyncEnabled = true;
                appPassword.Clear();
                syncPassword.Clear();
                MessageBox.Show(this, "凭据已加密保存在当前 Windows 用户的数据保险库中。", "坚果云同步", MessageBoxButton.OK, MessageBoxImage.Information);
            }
            else
            {
                MessageBox.Show(this, error, "坚果云同步", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }));
        stack.Children.Add(Button("立即同步一次", async () => await (_clipboard?.SyncCloudNowAsync() ?? Task.CompletedTask), margin: new Thickness(0, 8, 0, 0)));
        stack.Children.Add(syncStatus);
        page.Content = Scroll(stack);
        return page;
    }

    private UserControl BuildSnippetsPage()
    {
        var page = new UserControl();
        var stack = new StackPanel();
        stack.Children.Add(Header("文本片段"));
        var snippetList = new ListBox
        {
            ItemsSource = _snippetItems,
            DisplayMemberPath = nameof(SnippetItem.Title),
            Height = 180
        };
        stack.Children.Add(snippetList);
        var leftButtons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 0) };
        leftButtons.Children.Add(Button("新建", () =>
        {
            _snippets?.Save("新片段内容", title: "新片段");
            RefreshSnippets();
        }));
        leftButtons.Children.Add(Button("删除", () =>
        {
            if (snippetList.SelectedItem is SnippetItem item)
            {
                _snippets?.Delete(item);
                RefreshSnippets();
            }
        }));
        stack.Children.Add(leftButtons);
        stack.Children.Add(SubHeader("编辑"));
        var title = LabeledTextBox("标题", 200);
        var keyword = LabeledTextBox("关键词", 200);
        var collection = LabeledTextBox("分类", 200);
        var content = new TextBox
        {
            Height = 180,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Margin = new Thickness(0, 6, 0, 0)
        };
        var contentLabel = new TextBlock { Text = "内容（支持 {date} {time} {clipboard} {cursor}）", Style = (Style)FindResource("RowLabel") };
        stack.Children.Add(title.Label);
        stack.Children.Add(title.Box);
        stack.Children.Add(keyword.Label);
        stack.Children.Add(keyword.Box);
        stack.Children.Add(collection.Label);
        stack.Children.Add(collection.Box);
        stack.Children.Add(contentLabel);
        stack.Children.Add(content);
        stack.Children.Add(Button("保存修改", () =>
        {
            if (snippetList.SelectedItem is SnippetItem item)
            {
                _snippets?.Update(
                    item.Id,
                    title: title.Box.Text,
                    keyword: keyword.Box.Text,
                    content: content.Text,
                    collection: collection.Box.Text);
                RefreshSnippets();
            }
        }, margin: new Thickness(0, 10, 0, 0)));
        snippetList.SelectionChanged += (_, _) =>
        {
            if (snippetList.SelectedItem is SnippetItem item)
            {
                title.Box.Text = item.Title;
                keyword.Box.Text = item.Keyword;
                collection.Box.Text = item.Collection;
                content.Text = item.Content;
            }
        };
        page.Content = Scroll(stack);
        return page;
    }

    private UserControl BuildSystemCommandsPage()
    {
        var page = new UserControl();
        var stack = new StackPanel();
        stack.Children.Add(Header("系统命令"));
        stack.Children.Add(new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Text = "关键词只触发编译期固定的系统动作，永远不会作为命令或参数执行。"
        });
        foreach (var id in Enum.GetValues<SystemCommandID>())
        {
            var row = new Grid { Margin = new Thickness(0, 6, 0, 6) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(160) });
            var enabled = new CheckBox
            {
                Content = id.Title(),
                IsChecked = _preferences?.IsSystemCommandEnabled(id) ?? true,
                VerticalAlignment = VerticalAlignment.Center
            };
            enabled.Checked += (_, _) => _preferences?.SetSystemCommand(id, true);
            enabled.Unchecked += (_, _) => _preferences?.SetSystemCommand(id, false);
            row.Children.Add(enabled);
            var detail = new TextBlock
            {
                Text = id.Detail(),
                Style = (Style)FindResource("HintText"),
                Margin = new Thickness(12, 0, 12, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(detail, 1);
            row.Children.Add(detail);
            var keyword = new TextBox
            {
                Text = _preferences?.SystemCommandKeywords.TryGetValue(id, out var stored) == true
                    ? stored
                    : id.DefaultKeyword(),
                VerticalAlignment = VerticalAlignment.Center
            };
            keyword.LostFocus += (_, _) => _preferences?.SetSystemCommandKeyword(id, keyword.Text);
            Grid.SetColumn(keyword, 2);
            row.Children.Add(keyword);
            stack.Children.Add(row);
        }

        stack.Children.Add(Button("恢复系统命令默认值", () => _preferences?.RestoreSystemCommandDefaults()));
        page.Content = Scroll(stack);
        return page;
    }

    private UserControl BuildPrivacyPage()
    {
        var page = new UserControl();
        var stack = new StackPanel();
        stack.Children.Add(Header("隐私"));
        stack.Children.Add(new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Text = "YTools 默认完全离线。仅当你明确启用坚果云剪贴板同步时，程序才会向固定的坚果云 WebDAV 地址发送经端到端加密的剪贴板变更记录。"
        });
        stack.Children.Add(SubHeader("加密存储状态"));
        var clipboardError = new TextBlock
        {
            Style = (Style)FindResource("HintText")
        };
        clipboardError.SetResourceReference(TextBlock.ForegroundProperty, "ErrorBrush");
        clipboardError.SetBinding(
            TextBlock.TextProperty,
            new System.Windows.Data.Binding(nameof(ClipboardHistoryManager.StorageError)) { Source = _clipboard });
        stack.Children.Add(clipboardError);
        var snippetError = new TextBlock
        {
            Style = (Style)FindResource("HintText")
        };
        snippetError.SetResourceReference(TextBlock.ForegroundProperty, "ErrorBrush");
        snippetError.SetBinding(
            TextBlock.TextProperty,
            new System.Windows.Data.Binding(nameof(SnippetManager.StorageError)) { Source = _snippets });
        stack.Children.Add(snippetError);
        var recentError = new TextBlock
        {
            Style = (Style)FindResource("HintText")
        };
        recentError.SetResourceReference(TextBlock.ForegroundProperty, "ErrorBrush");
        recentError.SetBinding(
            TextBlock.TextProperty,
            new System.Windows.Data.Binding(nameof(RecentDocumentsManager.StorageError)) { Source = _recentDocuments });
        stack.Children.Add(recentError);
        stack.Children.Add(SubHeader("清除数据"));
        stack.Children.Add(Button("清除使用学习记录", () => _preferences?.ClearUsageLearning()));
        stack.Children.Add(Button("清除最近文档", () => _recentDocuments?.Clear(), margin: new Thickness(0, 8, 0, 0)));
        stack.Children.Add(Button("清空剪贴板历史", () =>
        {
            if (_clipboard is null)
            {
                return;
            }

            var confirmation = MessageBox.Show(
                this,
                "永久清空全部剪贴板历史？此操作无法撤销。",
                "清空剪贴板历史",
                MessageBoxButton.OKCancel,
                MessageBoxImage.Warning);
            if (confirmation == MessageBoxResult.OK)
            {
                _clipboard.Clear();
            }
        }, margin: new Thickness(0, 8, 0, 0)));
        page.Content = Scroll(stack);
        return page;
    }

    private UIElement Header(string text)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 0, 2) };
        panel.Children.Add(new TextBlock { Text = text, Style = (Style)FindResource("SectionHeader") });
        var separator = new Border
        {
            Height = 1,
            Margin = new Thickness(0, 0, 0, 10)
        };
        separator.SetResourceReference(Border.BackgroundProperty, "BorderBrush");
        panel.Children.Add(separator);
        return panel;
    }

    private UIElement SubHeader(string text)
    {
        return new TextBlock { Text = text, Style = (Style)FindResource("SubHeader") };
    }

    private CheckBox CheckBox(string label, string binding, string tooltip)
    {
        var box = new CheckBox
        {
            Content = label,
            Margin = new Thickness(0, 6, 0, 6),
            ToolTip = tooltip
        };
        box.SetBinding(
            System.Windows.Controls.Primitives.ToggleButton.IsCheckedProperty,
            new System.Windows.Data.Binding(binding)
            {
                Mode = System.Windows.Data.BindingMode.TwoWay,
                UpdateSourceTrigger = System.Windows.Data.UpdateSourceTrigger.PropertyChanged
            });
        return box;
    }

    private UIElement SliderRow(
        string label,
        string binding,
        double min,
        double max,
        double tick,
        double valueMultiplier = 1,
        string valueSuffix = "",
        string? detail = null)
    {
        var grid = new Grid { Margin = new Thickness(0, 6, 0, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(60) });
        var labelText = new TextBlock
        {
            Text = label,
            VerticalAlignment = VerticalAlignment.Center,
            FontSize = 13
        };
        labelText.SetResourceReference(TextBlock.ForegroundProperty, "TextPrimaryBrush");
        grid.Children.Add(labelText);
        var slider = new Slider
        {
            Minimum = min,
            Maximum = max,
            TickFrequency = tick,
            IsSnapToTickEnabled = true,
            VerticalAlignment = VerticalAlignment.Center
        };
        slider.SetBinding(
            RangeBase.ValueProperty,
            new System.Windows.Data.Binding(binding)
            {
                Mode = System.Windows.Data.BindingMode.TwoWay,
                UpdateSourceTrigger = System.Windows.Data.UpdateSourceTrigger.PropertyChanged
            });
        Grid.SetColumn(slider, 1);
        grid.Children.Add(slider);
        var valueText = new TextBlock
        {
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Right,
            FontSize = 12
        };
        valueText.SetResourceReference(TextBlock.ForegroundProperty, "TextSecondaryBrush");
        valueText.SetBinding(
            TextBlock.TextProperty,
            new System.Windows.Data.Binding(binding)
            {
                Converter = new ScaledValueTextConverter(valueMultiplier, valueSuffix)
            });
        Grid.SetColumn(valueText, 2);
        grid.Children.Add(valueText);
        if (string.IsNullOrWhiteSpace(detail))
        {
            return grid;
        }

        return new StackPanel
        {
            Children =
            {
                grid,
                new TextBlock
                {
                    Text = detail,
                    Style = (Style)FindResource("HintText"),
                    Margin = new Thickness(170, -4, 0, 6),
                    TextWrapping = TextWrapping.Wrap
                }
            }
        };
    }

    private UIElement ComboRow(string label, string binding, IReadOnlyList<EnumOption> options)
    {
        var grid = new Grid { Margin = new Thickness(0, 6, 0, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var labelText = new TextBlock
        {
            Text = label,
            VerticalAlignment = VerticalAlignment.Center,
            FontSize = 13
        };
        labelText.SetResourceReference(TextBlock.ForegroundProperty, "TextPrimaryBrush");
        grid.Children.Add(labelText);
        var combo = new ComboBox
        {
            ItemsSource = options,
            DisplayMemberPath = nameof(EnumOption.Title),
            SelectedValuePath = nameof(EnumOption.Value),
            VerticalAlignment = VerticalAlignment.Center
        };
        combo.SetBinding(
            Selector.SelectedValueProperty,
            new System.Windows.Data.Binding(binding)
            {
                Mode = System.Windows.Data.BindingMode.TwoWay,
                UpdateSourceTrigger = System.Windows.Data.UpdateSourceTrigger.PropertyChanged
            });
        Grid.SetColumn(combo, 1);
        grid.Children.Add(combo);
        return grid;
    }

    private (TextBlock Label, TextBox Box) LabeledTextBox(string label, double width)
    {
        var labelText = new TextBlock
        {
            Text = label,
            Style = (Style)FindResource("RowLabel")
        };
        var box = new TextBox
        {
            Width = width,
            HorizontalAlignment = HorizontalAlignment.Left,
            Margin = new Thickness(0, 2, 0, 4)
        };
        return (labelText, box);
    }

    private static Button Button(string content, Action click, Thickness? margin = null)
    {
        var button = new Button
        {
            Content = content,
            Margin = margin ?? new Thickness(0, 8, 8, 0),
            Padding = new Thickness(12, 5, 12, 5)
        };
        button.Click += (_, _) => click();
        return button;
    }

    private static ScrollViewer Scroll(UIElement content)
    {
        return new ScrollViewer
        {
            Content = content,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
    }

    private void RefreshSnippets()
    {
        _snippetItems.Clear();
        if (_snippets is not null)
        {
            foreach (var item in _snippets.Items)
            {
                _snippetItems.Add(item);
            }
        }
    }

    private void RefreshCustomApplications()
    {
        _customApplications.Clear();
        if (_preferences is null)
        {
            return;
        }

        foreach (var path in _preferences.CustomApplicationPaths)
        {
            _customApplications.Add(new CustomApplicationEntry(
                path,
                _preferences.ApplicationAliases.TryGetValue(path, out var aliases) ? aliases : ""));
        }
    }

    private void ApplyDarkTitleBar()
    {
        var dark = _preferences is { } preferences
            ? ThemeService.IsDarkEffective(preferences)
            : ThemeService.IsSystemDark();
        var handle = new WindowInteropHelper(this).Handle;
        var value = dark ? 1 : 0;
        if (handle != IntPtr.Zero)
        {
            _ = DwmSetWindowAttribute(handle, 20, ref value, sizeof(int));
        }
    }

    private sealed class AliasEntry
    {
        public AliasEntry(string target, string aliases)
        {
            Target = target;
            Aliases = aliases;
        }

        public string Target { get; }

        public string Aliases { get; set; }
    }

    private sealed class CustomApplicationEntry
    {
        public CustomApplicationEntry(string path, string aliases)
        {
            Path = path;
            Name = System.IO.Path.GetFileName(path);
            Aliases = aliases;
        }

        public string Name { get; }

        public string Path { get; }

        public string Aliases { get; set; }
    }

    private sealed class ScaledValueTextConverter : System.Windows.Data.IValueConverter
    {
        private readonly double _multiplier;
        private readonly string _suffix;

        public ScaledValueTextConverter(double multiplier, string suffix)
        {
            _multiplier = multiplier;
            _suffix = suffix;
        }

        public object Convert(
            object? value,
            Type targetType,
            object? parameter,
            System.Globalization.CultureInfo culture)
        {
            if (value is not IConvertible convertible)
            {
                return "";
            }

            var scaled = convertible.ToDouble(culture) * _multiplier;
            var format = _multiplier == 1 ? "0.##" : "0";
            return scaled.ToString(format, culture) + _suffix;
        }

        public object ConvertBack(
            object? value,
            Type targetType,
            object? parameter,
            System.Globalization.CultureInfo culture)
        {
            throw new NotSupportedException();
        }
    }

    private sealed class HotKeyRecorder : Border
    {
        private readonly TextBlock _display = new()
        {
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            FontWeight = FontWeights.SemiBold
        };

        public HotKeyRecorder(string title)
        {
            var titleText = new TextBlock
            {
                Text = title,
                FontSize = 12,
                HorizontalAlignment = HorizontalAlignment.Center
            };
            titleText.SetResourceReference(TextBlock.ForegroundProperty, "TextSecondaryBrush");
            _display.SetResourceReference(TextBlock.ForegroundProperty, "TextPrimaryBrush");
            Child = new StackPanel
            {
                Children =
                {
                    titleText,
                    _display
                }
            };
            SetResourceReference(BackgroundProperty, "InputBackgroundBrush");
            SetResourceReference(BorderBrushProperty, "BorderBrush");
            BorderThickness = new Thickness(1);
            CornerRadius = new CornerRadius(8);
            Padding = new Thickness(12, 8, 12, 8);
            Margin = new Thickness(0, 6, 0, 6);
            MinHeight = 54;
            Focusable = true;
            Cursor = Cursors.Hand;
            MouseLeftButtonDown += OnMouseLeftButtonDown;
            PreviewKeyDown += OnPreviewKeyDown;
            GotKeyboardFocus += (_, _) =>
            {
                SetResourceReference(BackgroundProperty, "SelectionBrush");
                SetResourceReference(BorderBrushProperty, "AccentBrush");
            };
            LostKeyboardFocus += (_, _) =>
            {
                SetResourceReference(BackgroundProperty, "InputBackgroundBrush");
                SetResourceReference(BorderBrushProperty, "BorderBrush");
            };
        }

        public event Action<HotKeyDefinition>? Changed;

        public void Bind(HotKeyDefinition definition)
        {
            _display.Text = definition.DisplayString;
        }

        private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            // Border does not take keyboard focus on mouse clicks by default.
            // Explicitly focusing it makes the recorder reliably usable even
            // when a child TextBlock is the original hit-test target.
            Focus();
            Keyboard.Focus(this);
            e.Handled = true;
        }

        private void OnPreviewKeyDown(object sender, KeyEventArgs e)
        {
            var modifiers = Keyboard.Modifiers;
            var hasModifier = modifiers != ModifierKeys.None;
            var key = e.Key == Key.System ? e.SystemKey : e.Key;
            var isModifierKey = key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt
                or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin;
            if (!hasModifier || isModifierKey)
            {
                return;
            }

            var hotKeyModifiers = HotKeyModifiers.None;
            if (modifiers.HasFlag(ModifierKeys.Control))
            {
                hotKeyModifiers |= HotKeyModifiers.Control;
            }

            if (modifiers.HasFlag(ModifierKeys.Alt))
            {
                hotKeyModifiers |= HotKeyModifiers.Alt;
            }

            if (modifiers.HasFlag(ModifierKeys.Shift))
            {
                hotKeyModifiers |= HotKeyModifiers.Shift;
            }

            if (modifiers.HasFlag(ModifierKeys.Windows))
            {
                hotKeyModifiers |= HotKeyModifiers.Windows;
            }

            var definition = new HotKeyDefinition(
                KeyInterop.VirtualKeyFromKey(key),
                hotKeyModifiers);
            _display.Text = definition.DisplayString;
            Changed?.Invoke(definition);
            e.Handled = true;
        }
    }

    internal sealed record EnumOption(string Title, object Value);

    private sealed record NavItem(string Title, string Glyph);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}

internal static class EnumMetadata
{
    public static IReadOnlyList<SettingsWindow.EnumOption> ThemeOptions()
    {
        return Enum.GetValues<AppTheme>()
            .Select(value => new SettingsWindow.EnumOption(value.Title(), value))
            .ToList();
    }

    public static IReadOnlyList<SettingsWindow.EnumOption> AccentOptions()
    {
        return Enum.GetValues<AppAccentColor>()
            .Select(value => new SettingsWindow.EnumOption(value.Title(), value))
            .ToList();
    }

    public static IReadOnlyList<SettingsWindow.EnumOption> StyleOptions()
    {
        return Enum.GetValues<LauncherAppearanceStyle>()
            .Select(value => new SettingsWindow.EnumOption(value.Title(), value))
            .ToList();
    }

    public static IReadOnlyList<SettingsWindow.EnumOption> PositionOptions()
    {
        return Enum.GetValues<PanelPosition>()
            .Select(value => new SettingsWindow.EnumOption(value.Title(), value))
            .ToList();
    }

    public static IReadOnlyList<SettingsWindow.EnumOption> ScreenOptions()
    {
        return Enum.GetValues<ScreenPreference>()
            .Select(value => new SettingsWindow.EnumOption(value.Title(), value))
            .ToList();
    }

    public static IReadOnlyList<SettingsWindow.EnumOption> RetentionOptions()
    {
        return new[] { 1, 7, 30, 90 }
            .Select(days => new SettingsWindow.EnumOption($"{days} 天", days))
            .ToList();
    }
}

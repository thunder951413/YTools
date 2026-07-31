using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Interop;
using YTools.Models;
using YTools.Services;

namespace YTools.UI;

public partial class SettingsWindow : Window
{
    private AppPreferences? _preferences;
    private ClipboardHistoryManager? _clipboard;
    private SnippetManager? _snippets;
    private RecentDocumentsManager? _recentDocuments;
    private readonly Dictionary<TabItem, Page> _pages = [];
    private readonly ObservableCollection<string> _scopePaths = [];
    private readonly ObservableCollection<AliasEntry> _aliasEntries = [];
    private readonly ObservableCollection<string> _ignoredApps = [];
    private readonly ObservableCollection<SnippetItem> _snippetItems = [];
    private HotKeyRecorder? _launcherRecorder;
    private HotKeyRecorder? _clipboardRecorder;

    public SettingsWindow()
    {
        InitializeComponent();
        NavTabs.SelectionChanged += (_, _) =>
        {
            if (NavTabs.SelectedItem is TabItem tab && _pages.TryGetValue(tab, out var page))
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

        _ignoredApps.Clear();
        foreach (var name in preferences.ClipboardIgnoredProcessNames)
        {
            _ignoredApps.Add(name);
        }

        RefreshSnippets();
        _launcherRecorder?.Bind(preferences.LauncherHotKey);
        _clipboardRecorder?.Bind(preferences.ClipboardHotKey);
        BuildPages();
        SelectFirstTab();
    }

    public void SelectFirstTab()
    {
        if (NavTabs.Items.Count > 0)
        {
            NavTabs.SelectedIndex = 0;
        }
    }

    private void BuildPages()
    {
        var tabs = NavTabs.Items.Cast<TabItem>().ToList();
        _pages[tabs[0]] = BuildGeneralPage();
        _pages[tabs[1]] = BuildSearchPage();
        _pages[tabs[2]] = BuildAliasesPage();
        _pages[tabs[3]] = BuildAppearancePage();
        _pages[tabs[4]] = BuildHotKeysPage();
        _pages[tabs[5]] = BuildClipboardPage();
        _pages[tabs[6]] = BuildSnippetsPage();
        _pages[tabs[7]] = BuildSystemCommandsPage();
        _pages[tabs[8]] = BuildPrivacyPage();
    }

    private Page BuildGeneralPage()
    {
        var page = new Page();
        var stack = new StackPanel();
        stack.Children.Add(Header("通用"));
        stack.Children.Add(CheckBox("开机启动", "登录 Windows 后自动运行 YTools", "LaunchAtLogin"));
        stack.Children.Add(CheckBox("显示托盘图标", "隐藏后全局快捷键和剪贴板监听不受影响", "ShowTrayIcon"));
        stack.Children.Add(ComboRow("主题", "Theme", EnumMetadata.ThemeOptions()));
        stack.Children.Add(ComboRow("强调色", "AccentColor", EnumMetadata.AccentOptions()));
        var launchError = new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Foreground = System.Windows.Media.Brushes.OrangeRed
        };
        launchError.SetBinding(TextBlock.TextProperty, new System.Windows.Data.Binding(nameof(AppPreferences.LaunchAtLoginError)));
        stack.Children.Add(launchError);
        var restore = Button("恢复默认设置", () => _preferences?.RestoreDefaults());
        stack.Children.Add(restore);
        page.Content = Scroll(stack);
        return page;
    }

    private Page BuildSearchPage()
    {
        var page = new Page();
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
        stack.Children.Add(CheckBox("默认结果包含文件", "关闭后仅输入 open/打开 等前缀时返回文件", "IncludeFilesInDefaultResults"));
        stack.Children.Add(SliderRow("最大结果数", "MaximumSearchResults", 3, 20, 1));
        stack.Children.Add(SliderRow("输入防抖（秒）", "SearchInputDelay", 0.05, 0.4, 0.05));
        stack.Children.Add(Header("搜索范围"));
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

    private Page BuildAliasesPage()
    {
        var page = new Page();
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
                Filter = "应用 (*.exe;*.lnk)|*.exe;*.lnk",
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

    private Page BuildAppearancePage()
    {
        var page = new Page();
        var stack = new StackPanel();
        stack.Children.Add(Header("启动器外观"));
        stack.Children.Add(ComboRow("外观样式", "LauncherAppearanceStyle", EnumMetadata.StyleOptions()));
        stack.Children.Add(ComboRow("默认位置", "PanelPosition", EnumMetadata.PositionOptions()));
        stack.Children.Add(ComboRow("屏幕偏好", "ScreenPreference", EnumMetadata.ScreenOptions()));
        stack.Children.Add(SliderRow("面板宽度", "PanelWidth", 640, 960, 10));
        stack.Children.Add(SliderRow("圆角半径", "PanelCornerRadius", 10, 20, 1));
        stack.Children.Add(CheckBox("紧凑结果行", "以更小的行高显示结果", "CompactResults"));
        stack.Children.Add(CheckBox("显示结果副标题", "ShowSubtitles", "显示结果副标题"));
        stack.Children.Add(CheckBox("显示数字快捷键", "ShowNumberShortcuts", "显示数字快捷键"));
        stack.Children.Add(SliderRow("结果展开动画（秒）", "ResultExpansionDuration", 0, 0.4, 0.05));
        stack.Children.Add(SliderRow("预览延迟（秒）", "PreviewSelectionDelay", 0, 0.8, 0.05));
        stack.Children.Add(Button("清除使用学习", () => _preferences?.ClearUsageLearning()));
        page.Content = Scroll(stack);
        return page;
    }

    private Page BuildHotKeysPage()
    {
        var page = new Page();
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
        stack.Children.Add(_launcherRecorder);
        _clipboardRecorder = new HotKeyRecorder("剪贴板历史快捷键");
        _clipboardRecorder.Changed += definition =>
        {
            if (_preferences is not null)
            {
                _preferences.ClipboardHotKey = definition;
            }
        };
        stack.Children.Add(_clipboardRecorder);
        var hotKeyError = new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Foreground = System.Windows.Media.Brushes.OrangeRed
        };
        hotKeyError.SetBinding(
            TextBlock.TextProperty,
            new System.Windows.Data.Binding(nameof(AppPreferences.HotKeyError)));
        stack.Children.Add(hotKeyError);
        page.Content = Scroll(stack);
        return page;
    }

    private Page BuildClipboardPage()
    {
        var page = new Page();
        var stack = new StackPanel();
        stack.Children.Add(Header("剪贴板历史"));
        stack.Children.Add(CheckBox("启用剪贴板历史", "ClipboardEnabled", "启用剪贴板历史"));
        stack.Children.Add(CheckBox("暂停记录", "ClipboardPaused", "暂停记录"));
        stack.Children.Add(ComboRow("保留天数", "ClipboardRetentionDays", EnumMetadata.RetentionOptions()));
        stack.Children.Add(SliderRow("最大条数", "ClipboardMaximumItems", 50, 1_000, 10));
        stack.Children.Add(SliderRow("单条文本上限（字符）", "ClipboardMaximumTextCharacters", 100, 10_000, 100));
        stack.Children.Add(CheckBox("保存图片", "ClipboardStoreImages", "图片默认关闭，单项限制 5 MB"));
        stack.Children.Add(Header("忽略的进程"));
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
        page.Content = Scroll(stack);
        return page;
    }

    private Page BuildSnippetsPage()
    {
        var page = new Page();
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var left = new StackPanel();
        left.Children.Add(Header("文本片段"));
        var snippetList = new ListBox
        {
            ItemsSource = _snippetItems,
            DisplayMemberPath = nameof(SnippetItem.Title),
            Height = 320
        };
        left.Children.Add(snippetList);
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
        left.Children.Add(leftButtons);
        grid.Children.Add(left);
        var right = new StackPanel { Margin = new Thickness(16, 0, 0, 0) };
        right.Children.Add(Header("编辑"));
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
        right.Children.Add(title.Label);
        right.Children.Add(title.Box);
        right.Children.Add(keyword.Label);
        right.Children.Add(keyword.Box);
        right.Children.Add(collection.Label);
        right.Children.Add(collection.Box);
        right.Children.Add(contentLabel);
        right.Children.Add(content);
        right.Children.Add(Button("保存修改", () =>
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
        grid.Children.Add(right);
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
        page.Content = grid;
        return page;
    }

    private Page BuildSystemCommandsPage()
    {
        var page = new Page();
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

    private Page BuildPrivacyPage()
    {
        var page = new Page();
        var stack = new StackPanel();
        stack.Children.Add(Header("隐私"));
        stack.Children.Add(new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Text = "YTools 是本机应用：主程序不包含任何网络客户端，不发送查询、剪贴板、文件名、使用记录或设备信息。"
        });
        stack.Children.Add(Header("加密存储状态"));
        var clipboardError = new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Foreground = System.Windows.Media.Brushes.OrangeRed
        };
        clipboardError.SetBinding(
            TextBlock.TextProperty,
            new System.Windows.Data.Binding(nameof(ClipboardHistoryManager.StorageError)) { Source = _clipboard });
        stack.Children.Add(clipboardError);
        var snippetError = new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Foreground = System.Windows.Media.Brushes.OrangeRed
        };
        snippetError.SetBinding(
            TextBlock.TextProperty,
            new System.Windows.Data.Binding(nameof(SnippetManager.StorageError)) { Source = _snippets });
        stack.Children.Add(snippetError);
        var recentError = new TextBlock
        {
            Style = (Style)FindResource("HintText"),
            Foreground = System.Windows.Media.Brushes.OrangeRed
        };
        recentError.SetBinding(
            TextBlock.TextProperty,
            new System.Windows.Data.Binding(nameof(RecentDocumentsManager.StorageError)) { Source = _recentDocuments });
        stack.Children.Add(recentError);
        stack.Children.Add(Header("清除数据"));
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

    private TextBlock Header(string text)
    {
        return new TextBlock { Text = text, Style = (Style)FindResource("SectionHeader") };
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

    private static UIElement SliderRow(string label, string binding, double min, double max, double tick)
    {
        var grid = new Grid { Margin = new Thickness(0, 6, 0, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(60) });
        var labelText = new TextBlock
        {
            Text = label,
            VerticalAlignment = VerticalAlignment.Center,
            FontSize = 13,
            Foreground = (System.Windows.Media.Brush)Application.Current.Resources["TextPrimaryBrush"]
        };
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
            FontSize = 12,
            Foreground = (System.Windows.Media.Brush)Application.Current.Resources["TextSecondaryBrush"]
        };
        valueText.SetBinding(
            TextBlock.TextProperty,
            new System.Windows.Data.Binding(binding)
            {
                StringFormat = "{0:0.##}"
            });
        Grid.SetColumn(valueText, 2);
        grid.Children.Add(valueText);
        return grid;
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
            FontSize = 13,
            Foreground = (System.Windows.Media.Brush)Application.Current.Resources["TextPrimaryBrush"]
        };
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

    private static (TextBlock Label, TextBox Box) LabeledTextBox(string label, double width)
    {
        var labelText = new TextBlock
        {
            Text = label,
            Style = (Style)Application.Current.FindResource("RowLabel")
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

    private void ApplyDarkTitleBar()
    {
        var dark = ThemeService.IsSystemDark();
        var handle = new WindowInteropHelper(this).Handle;
        var value = dark ? 1 : 0;
        _ = DwmSetWindowAttribute(handle, 20, ref value, sizeof(int));
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

    private sealed class HotKeyRecorder : Border
    {
        private readonly TextBlock _display = new()
        {
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center
        };

        public HotKeyRecorder(string title)
        {
            Child = new StackPanel
            {
                Children =
                {
                    new TextBlock
                    {
                        Text = title,
                        FontSize = 12,
                        Foreground = (System.Windows.Media.Brush)Application.Current.Resources["TextSecondaryBrush"],
                        HorizontalAlignment = HorizontalAlignment.Center
                    },
                    _display
                }
            };
            Background = (System.Windows.Media.Brush)Application.Current.Resources["InputBackgroundBrush"];
            CornerRadius = new CornerRadius(8);
            Padding = new Thickness(12, 8, 12, 8);
            Margin = new Thickness(0, 6, 0, 6);
            MinHeight = 54;
            Focusable = true;
            KeyDown += OnKeyDown;
            GotKeyboardFocus += (_, _) =>
            {
                Background = (System.Windows.Media.Brush)Application.Current.Resources["SelectionBrush"];
            };
            LostKeyboardFocus += (_, _) =>
            {
                Background = (System.Windows.Media.Brush)Application.Current.Resources["InputBackgroundBrush"];
            };
        }

        public event Action<HotKeyDefinition>? Changed;

        public void Bind(HotKeyDefinition definition)
        {
            _display.Text = definition.DisplayString;
        }

        private void OnKeyDown(object sender, KeyEventArgs e)
        {
            var modifiers = Keyboard.Modifiers;
            var hasModifier = modifiers != ModifierKeys.None;
            var isModifierKey = e.Key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt
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
                KeyInterop.VirtualKeyFromKey(e.Key),
                hotKeyModifiers);
            _display.Text = definition.DisplayString;
            Changed?.Invoke(definition);
            e.Handled = true;
        }
    }

    internal sealed record EnumOption(string Title, object Value);

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

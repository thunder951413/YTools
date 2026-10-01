using System.Windows;
using System.Windows.Input;

namespace YTools.UI;

public partial class LargeTypeWindow : Window
{
    public LargeTypeWindow()
    {
        InitializeComponent();
    }

    public void ShowText(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return;
        }

        DisplayText.Text = text;
        Show();
        Activate();
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            Hide();
        }
    }

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        Hide();
    }
}

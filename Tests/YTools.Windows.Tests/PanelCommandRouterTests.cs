using YTools.Core;

namespace YTools.Windows.Tests;

public class PanelCommandRouterTests
{
    private readonly PanelCommandRouter _router = new();

    [Fact]
    public void Enter_ActivatesSelected()
    {
        var command = _router.Command(
            new PanelKeyEvent(0x0D, PanelKeyModifiers.None),
            PanelInputMode.Launcher);

        Assert.Equal(PanelCommandKind.ActivateSelected, command?.Kind);
    }

    [Theory]
    [InlineData(0x30, 0)]
    [InlineData(0x35, 5)]
    [InlineData(0x39, 9)]
    public void CtrlNumber_ActivatesResult(int keyCode, int expectedIndex)
    {
        var command = _router.Command(
            new PanelKeyEvent(keyCode, PanelKeyModifiers.Command),
            PanelInputMode.Launcher);

        Assert.Equal(PanelCommandKind.ActivateResult, command?.Kind);
        Assert.Equal(expectedIndex, command?.Payload);
    }

    [Fact]
    public void AltUp_AddsSelectedToBuffer()
    {
        var command = _router.Command(
            new PanelKeyEvent(0x26, PanelKeyModifiers.Option),
            PanelInputMode.Launcher);

        Assert.Equal(PanelCommandKind.AddSelectedToBuffer, command?.Kind);
    }

    [Fact]
    public void CtrlComma_OpensSettings()
    {
        var command = _router.Command(
            new PanelKeyEvent(0xBC, PanelKeyModifiers.Command),
            PanelInputMode.Clipboard);

        Assert.Equal(PanelCommandKind.OpenSettings, command?.Kind);
    }

    [Fact]
    public void CtrlD_InClipboard_DeletesItem()
    {
        var command = _router.Command(
            new PanelKeyEvent(0x44, PanelKeyModifiers.Command),
            PanelInputMode.Clipboard);

        Assert.Equal(PanelCommandKind.DeleteClipboardItem, command?.Kind);
    }

    [Fact]
    public void CtrlD_InLauncher_ReturnsNull()
    {
        var command = _router.Command(
            new PanelKeyEvent(0x44, PanelKeyModifiers.Command),
            PanelInputMode.Launcher);

        Assert.Null(command);
    }

    [Fact]
    public void Escape_ReturnsEscapeInBothModes()
    {
        Assert.Equal(
            PanelCommandKind.Escape,
            _router.Command(new PanelKeyEvent(0x1B, PanelKeyModifiers.None), PanelInputMode.Launcher)?.Kind);
        Assert.Equal(
            PanelCommandKind.Escape,
            _router.Command(new PanelKeyEvent(0x1B, PanelKeyModifiers.None), PanelInputMode.Clipboard)?.Kind);
    }
}

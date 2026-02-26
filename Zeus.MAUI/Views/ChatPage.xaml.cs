using Zeus.MAUI.ViewModels;

namespace Zeus.MAUI.Views;

public partial class ChatPage : ContentPage
{
    private readonly ChatViewModel _viewModel;

    public ChatPage(ChatViewModel viewModel)
    {
        InitializeComponent();
        _viewModel = viewModel;
        BindingContext = _viewModel;
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
        _viewModel.Messages.CollectionChanged += ScrollToBottom;
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        _viewModel.Messages.CollectionChanged -= ScrollToBottom;
    }

    private void ScrollToBottom(object? sender, System.Collections.Specialized.NotifyCollectionChangedEventArgs e)
    {
        if (_viewModel.Messages.Count > 0)
        {
            MessagesCollectionView.ScrollTo(
                _viewModel.Messages[^1],
                animate: true);
        }
    }
}

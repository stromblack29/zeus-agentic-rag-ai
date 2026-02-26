using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Zeus.MAUI.Models;
using Zeus.MAUI.Services;

namespace Zeus.MAUI.ViewModels;

public partial class ChatViewModel : ObservableObject
{
    private readonly IBffChatService _chatService;
    private readonly string _sessionId = Guid.NewGuid().ToString();

    [ObservableProperty]
    private string _messageInput = string.Empty;

    [ObservableProperty]
    private bool _isBusy;

    [ObservableProperty]
    private string? _pendingImageBase64;

    [ObservableProperty]
    private string? _pendingImagePreview;

    public ObservableCollection<ChatMessage> Messages { get; } = new();

    public ChatViewModel(IBffChatService chatService)
    {
        _chatService = chatService;
    }

    [RelayCommand]
    private async Task SendMessageAsync()
    {
        var text = MessageInput?.Trim();
        if (string.IsNullOrEmpty(text) && PendingImageBase64 == null)
            return;

        var userMessage = new ChatMessage
        {
            Text   = string.IsNullOrEmpty(text) ? "[Image attached]" : text,
            IsUser = true,
        };
        Messages.Add(userMessage);

        MessageInput = string.Empty;
        var imageToSend = PendingImageBase64;
        PendingImageBase64   = null;
        PendingImagePreview  = null;

        IsBusy = true;
        try
        {
            var reply = await _chatService.SendMessageAsync(
                _sessionId,
                userMessage.Text,
                imageToSend);

            Messages.Add(reply);
        }
        catch (Exception ex)
        {
            Messages.Add(new ChatMessage
            {
                Text   = $"Error: {ex.Message}",
                IsUser = false,
            });
        }
        finally
        {
            IsBusy = false;
        }
    }

    [RelayCommand]
    private async Task PickImageAsync()
    {
        try
        {
            var result = await MediaPicker.Default.PickPhotoAsync(new MediaPickerOptions
            {
                Title = "Select car or policy image",
            });

            if (result == null) return;

            await using var stream = await result.OpenReadAsync();
            using var ms = new MemoryStream();
            await stream.CopyToAsync(ms);

            var bytes = ms.ToArray();
            PendingImageBase64  = Convert.ToBase64String(bytes);
            PendingImagePreview = result.FullPath;
        }
        catch (Exception ex)
        {
            await Shell.Current.DisplayAlert("Error", $"Could not pick image: {ex.Message}", "OK");
        }
    }
}

using Zeus.MAUI.Models;

namespace Zeus.MAUI.Services;

public interface IBffChatService
{
    Task<ChatMessage> SendMessageAsync(
        string sessionId,
        string message,
        string? imageBase64 = null,
        CancellationToken cancellationToken = default);
}

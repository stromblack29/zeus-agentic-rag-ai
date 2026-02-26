using System.Net.Http.Json;
using Zeus.MAUI.Models;

namespace Zeus.MAUI.Services;

public class BffChatService : IBffChatService
{
    private readonly HttpClient _httpClient;

    public BffChatService(HttpClient httpClient)
    {
        _httpClient = httpClient;
    }

    public async Task<ChatMessage> SendMessageAsync(
        string sessionId,
        string message,
        string? imageBase64 = null,
        CancellationToken cancellationToken = default)
    {
        var payload = new
        {
            sessionId    = sessionId,
            message      = message,
            imageBase64  = imageBase64
        };

        var response = await _httpClient.PostAsJsonAsync(
            "/api/chat",
            payload,
            cancellationToken);

        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<BffChatResponse>(
            cancellationToken: cancellationToken);

        return new ChatMessage
        {
            Text   = result?.Reply ?? "No response received.",
            IsUser = false,
        };
    }

    private sealed record BffChatResponse(string SessionId, string Reply);
}

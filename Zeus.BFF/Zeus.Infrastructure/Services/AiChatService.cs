using System.Net.Http.Json;
using Zeus.Application.DTOs;
using Zeus.Application.Interfaces;

namespace Zeus.Infrastructure.Services;

public class AiChatService : IAiChatService
{
    private readonly HttpClient _httpClient;

    public AiChatService(HttpClient httpClient)
    {
        _httpClient = httpClient;
    }

    public async Task<ChatResponseDto> SendMessageAsync(
        ChatRequestDto request,
        CancellationToken cancellationToken = default)
    {
        var payload = new
        {
            session_id  = request.SessionId,
            message     = request.Message,
            image_base64 = request.ImageBase64
        };

        var response = await _httpClient.PostAsJsonAsync(
            "/api/chat",
            payload,
            cancellationToken);

        response.EnsureSuccessStatusCode();

        var result = await response.Content.ReadFromJsonAsync<ChatResponseDto>(
            cancellationToken: cancellationToken);

        return result ?? throw new InvalidOperationException("Empty response from AI service.");
    }
}

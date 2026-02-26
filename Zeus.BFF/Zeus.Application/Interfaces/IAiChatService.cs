using Zeus.Application.DTOs;

namespace Zeus.Application.Interfaces;

public interface IAiChatService
{
    Task<ChatResponseDto> SendMessageAsync(ChatRequestDto request, CancellationToken cancellationToken = default);
}

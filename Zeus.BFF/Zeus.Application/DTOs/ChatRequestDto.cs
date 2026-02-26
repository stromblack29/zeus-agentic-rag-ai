namespace Zeus.Application.DTOs;

public class ChatRequestDto
{
    public string SessionId { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
    public string? ImageBase64 { get; set; }
}

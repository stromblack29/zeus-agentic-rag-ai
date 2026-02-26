namespace Zeus.MAUI.Models;

public class ChatMessage
{
    public string Text { get; set; } = string.Empty;
    public bool IsUser { get; set; }
    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.Now;
}

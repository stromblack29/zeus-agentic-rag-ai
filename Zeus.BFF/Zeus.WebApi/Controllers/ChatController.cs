using Microsoft.AspNetCore.Mvc;
using Zeus.Application.DTOs;
using Zeus.Application.Interfaces;

namespace Zeus.WebApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ChatController : ControllerBase
{
    private readonly IAiChatService _aiChatService;

    public ChatController(IAiChatService aiChatService)
    {
        _aiChatService = aiChatService;
    }

    [HttpPost]
    public async Task<ActionResult<ChatResponseDto>> Post(
        [FromBody] ChatRequestDto request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Message))
            return BadRequest("Message cannot be empty.");

        var response = await _aiChatService.SendMessageAsync(request, cancellationToken);
        return Ok(response);
    }
}

using CommunityToolkit.Maui;
using Microsoft.Extensions.Logging;
using Zeus.MAUI.Converters;
using Zeus.MAUI.Services;
using Zeus.MAUI.ViewModels;
using Zeus.MAUI.Views;

namespace Zeus.MAUI;

public static class MauiProgram
{
    public static MauiApp CreateMauiApp()
    {
        var builder = MauiApp.CreateBuilder();

        builder
            .UseMauiApp<App>()
            .UseMauiCommunityToolkit()
            .ConfigureFonts(fonts =>
            {
                fonts.AddFont("OpenSans-Regular.ttf", "OpenSansRegular");
                fonts.AddFont("OpenSans-Semibold.ttf", "OpenSansSemibold");
            });

        var bffBaseUrl = "http://localhost:5000";

        builder.Services.AddHttpClient<IBffChatService, BffChatService>(client =>
        {
            client.BaseAddress = new Uri(bffBaseUrl);
            client.Timeout = TimeSpan.FromSeconds(120);
        });

        builder.Services.AddTransient<ChatViewModel>();
        builder.Services.AddTransient<ChatPage>();

#if DEBUG
        builder.Logging.AddDebug();
#endif

        return builder.Build();
    }
}

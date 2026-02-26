using Zeus.MAUI.Views;

namespace Zeus.MAUI;

public partial class App : Application
{
    public App(ChatPage chatPage)
    {
        InitializeComponent();
        MainPage = new NavigationPage(chatPage)
        {
            BarBackgroundColor = Color.FromArgb("#0F172A"),
            BarTextColor = Colors.White,
        };
    }
}

import "./globals.css";
import { Public_Sans } from "next/font/google";
import { Toaster } from "@/components/ui/sonner";

const publicSans = Public_Sans({ subsets: ["latin"] });

export const metadata = {
  title: "Zeus Insurance AI",
  description: "AI-powered car insurance quotation assistant for Thailand",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <head>
        <link rel="shortcut icon" href="/images/favicon.ico" />
      </head>
      <body className={publicSans.className}>
        <div className="min-h-screen bg-gradient-to-br from-slate-900 via-blue-950 to-slate-900 flex flex-col">
          {/* Header */}
          <header className="border-b border-white/10 bg-black/20 backdrop-blur-sm px-4 py-3 flex items-center gap-3 flex-shrink-0">
            <div className="flex items-center gap-2">
              <div className="w-8 h-8 rounded-full bg-gradient-to-br from-yellow-400 to-orange-500 flex items-center justify-center text-sm font-bold text-black">
                ⚡
              </div>
              <div>
                <h1 className="text-white font-bold text-base leading-tight">Zeus Insurance AI</h1>
                <p className="text-blue-300 text-xs">AI Car Insurance Assistant · Thailand</p>
              </div>
            </div>
          </header>

          {/* Main content */}
          <main className="flex-1 flex flex-col min-h-0">
            {children}
          </main>
        </div>
        <Toaster />
      </body>
    </html>
  );
}

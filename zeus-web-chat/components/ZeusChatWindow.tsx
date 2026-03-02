"use client";

import { useState, useRef, useEffect, useCallback } from "react";
import { toast } from "sonner";
import { ZeusMessageBubble } from "./ZeusMessageBubble";
import { ModelSelector } from "./ModelSelector";
import { ImageUploadButton } from "./ImageUploadButton";
import { LoaderCircle, Send, ArrowDown } from "lucide-react";
import { Button } from "./ui/button";
import { getOrCreateSessionId } from "@/utils/session";

export type ChatMessage = {
  id: string;
  role: "user" | "assistant";
  content: string;
  imagePreview?: string;
  toolCalls?: string[];
};

const SUGGESTED_PROMPTS = [
  "ฉันต้องการประกันรถยนต์สำหรับ Honda Civic e:HEV RS 2024",
  "ประกันชั้น 1 ครอบคลุมน้ำท่วมหรือไม่?",
  "แนะนำแผนประกันสำหรับ Toyota Camry Hybrid",
  "ราคาเบี้ยประกันรถ Tesla Model 3 เท่าไร?",
];

export function ZeusChatWindow() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [llmModel, setLlmModel] = useState("gemini-2.5-flash");
  const [imageBase64, setImageBase64] = useState<string | null>(null);
  const [imagePreview, setImagePreview] = useState<string | null>(null);
  const [showScrollBtn, setShowScrollBtn] = useState(false);

  const bottomRef = useRef<HTMLDivElement>(null);
  const scrollAreaRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  const scrollToBottom = useCallback((smooth = true) => {
    bottomRef.current?.scrollIntoView({ behavior: smooth ? "smooth" : "auto" });
  }, []);

  useEffect(() => {
    if (messages.length > 0) scrollToBottom();
  }, [messages, scrollToBottom]);

  useEffect(() => {
    const el = scrollAreaRef.current;
    if (!el) return;
    const handleScroll = () => {
      const distFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
      setShowScrollBtn(distFromBottom > 150);
    };
    el.addEventListener("scroll", handleScroll);
    return () => el.removeEventListener("scroll", handleScroll);
  }, []);

  const clearImage = () => {
    setImageBase64(null);
    setImagePreview(null);
  };

  const sendMessage = async (text: string, img?: string | null) => {
    if (!text.trim() && !img) return;

    const sessionId = getOrCreateSessionId();
    const userMsg: ChatMessage = {
      id: Date.now().toString(),
      role: "user",
      content: text,
      imagePreview: img ?? imagePreview ?? undefined,
    };

    const aiMsgId = (Date.now() + 1).toString();
    const aiMsg: ChatMessage = { id: aiMsgId, role: "assistant", content: "" };

    setMessages((prev) => [...prev, userMsg, aiMsg]);
    setInput("");
    clearImage();
    setIsLoading(true);

    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          sessionId,
          message: text,
          imageBase64: img ?? imageBase64 ?? null,
          llmModel,
          stream: true,
        }),
      });

      if (!res.ok || !res.body) {
        const data = await res.json().catch(() => ({ error: "Request failed" }));
        throw new Error(data.error ?? "Request failed");
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buffer = "";
      let activeTools: string[] = [];

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";

        for (const line of lines) {
          if (!line.startsWith("data: ")) continue;
          const raw = line.slice(6).trim();
          if (!raw) continue;

          let event: Record<string, any>;
          try { event = JSON.parse(raw); } catch { continue; }

          if (event.token) {
            setMessages((prev) =>
              prev.map((m) =>
                m.id === aiMsgId
                  ? { ...m, content: m.content + event.token }
                  : m,
              ),
            );
          } else if (event.tool_start) {
            activeTools = [...activeTools, event.tool_start];
            setMessages((prev) =>
              prev.map((m) =>
                m.id === aiMsgId
                  ? { ...m, toolCalls: activeTools }
                  : m,
              ),
            );
          } else if (event.tool_end) {
            activeTools = activeTools.filter((t) => t !== event.tool_end);
            setMessages((prev) =>
              prev.map((m) =>
                m.id === aiMsgId
                  ? { ...m, toolCalls: activeTools.length ? activeTools : undefined }
                  : m,
              ),
            );
          } else if (event.error) {
            throw new Error(event.error);
          }
        }
      }
    } catch (e: any) {
      toast.error("Error", { description: e.message });
      setMessages((prev) => prev.filter((m) => m.id !== aiMsgId));
    } finally {
      setIsLoading(false);
      setTimeout(() => inputRef.current?.focus(), 50);
    }
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    sendMessage(input);
  };

  const handleSuggestedPrompt = (prompt: string) => {
    sendMessage(prompt);
  };

  return (
    <div className="flex flex-col h-full min-h-0">
      {/* Top bar: model selector */}
      <div className="flex items-center justify-between px-4 py-2 border-b border-white/10 bg-black/10 flex-shrink-0">
        <span className="text-blue-300 text-xs font-medium">LLM Model</span>
        <ModelSelector value={llmModel} onChange={setLlmModel} />
      </div>

      {/* Messages area */}
      <div
        ref={scrollAreaRef}
        className="flex-1 overflow-y-auto px-2 py-4 relative min-h-0"
      >
        {messages.length === 0 ? (
          <WelcomeScreen onPrompt={handleSuggestedPrompt} />
        ) : (
          <div className="max-w-3xl mx-auto space-y-1 pb-4">
            {messages.map((msg) => (
              <ZeusMessageBubble key={msg.id} message={msg} />
            ))}
            {isLoading && <TypingIndicator />}
            <div ref={bottomRef} />
          </div>
        )}

        {/* Scroll to bottom button */}
        {showScrollBtn && (
          <button
            onClick={() => scrollToBottom()}
            className="fixed bottom-24 right-6 bg-blue-600 hover:bg-blue-500 text-white rounded-full p-2 shadow-lg z-10 transition-all"
          >
            <ArrowDown className="w-4 h-4" />
          </button>
        )}
      </div>

      {/* Input area */}
      <div className="flex-shrink-0 px-2 pb-4 pt-2 border-t border-white/10 bg-black/10">
        <form
          onSubmit={handleSubmit}
          className="max-w-3xl mx-auto"
        >
          {/* Image preview strip */}
          {imagePreview && (
            <div className="mb-2 flex items-center gap-2">
              <div className="relative">
                <img
                  src={imagePreview}
                  alt="Attached"
                  className="h-16 w-16 object-cover rounded-lg border border-white/20"
                />
                <button
                  type="button"
                  onClick={clearImage}
                  className="absolute -top-1 -right-1 bg-red-500 text-white rounded-full w-4 h-4 flex items-center justify-center text-xs leading-none"
                >
                  ×
                </button>
              </div>
              <span className="text-xs text-blue-300">Image attached</span>
            </div>
          )}

          <div className="flex items-end gap-2 bg-white/5 border border-white/15 rounded-2xl px-3 py-2">
            <ImageUploadButton
              onImage={(b64, preview) => {
                setImageBase64(b64);
                setImagePreview(preview);
              }}
            />
            <input
              ref={inputRef}
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="ถามเกี่ยวกับประกันรถยนต์... (Thai or English)"
              disabled={isLoading}
              className="flex-1 bg-transparent text-white placeholder-white/40 outline-none text-sm py-1 resize-none"
              onKeyDown={(e) => {
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  handleSubmit(e as any);
                }
              }}
            />
            <Button
              type="submit"
              disabled={isLoading || (!input.trim() && !imageBase64)}
              size="sm"
              className="bg-blue-600 hover:bg-blue-500 text-white rounded-xl px-3 py-2 self-end flex-shrink-0"
            >
              {isLoading ? (
                <LoaderCircle className="w-4 h-4 animate-spin" />
              ) : (
                <Send className="w-4 h-4" />
              )}
            </Button>
          </div>
          <p className="text-xs text-white/25 text-center mt-2">
            Zeus AI · Powered by LangGraph + FastAPI
          </p>
        </form>
      </div>
    </div>
  );
}

function WelcomeScreen({ onPrompt }: { onPrompt: (p: string) => void }) {
  return (
    <div className="flex flex-col items-center justify-center h-full min-h-[60vh] px-4 text-center">
      <div className="w-16 h-16 rounded-full bg-gradient-to-br from-yellow-400 to-orange-500 flex items-center justify-center text-3xl mb-4 shadow-xl">
        ⚡
      </div>
      <h2 className="text-white text-2xl font-bold mb-2">Zeus Insurance AI</h2>
      <p className="text-blue-300 text-sm mb-8 max-w-md">
        ผู้ช่วย AI สำหรับประกันรถยนต์ในประเทศไทย ·
        สอบถามราคาเบี้ยประกัน เปรียบเทียบแผน และสร้างใบเสนอราคาได้ทันที
      </p>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 w-full max-w-xl">
        {SUGGESTED_PROMPTS.map((prompt) => (
          <button
            key={prompt}
            onClick={() => onPrompt(prompt)}
            className="text-left bg-white/5 hover:bg-white/10 border border-white/10 hover:border-blue-400/50 text-white/80 text-sm rounded-xl p-3 transition-all"
          >
            {prompt}
          </button>
        ))}
      </div>
    </div>
  );
}

function TypingIndicator() {
  return (
    <div className="flex items-start gap-3 mr-auto max-w-[80%] mb-4">
      <div className="w-8 h-8 rounded-full bg-gradient-to-br from-yellow-400 to-orange-500 flex items-center justify-center text-sm flex-shrink-0">
        ⚡
      </div>
      <div className="bg-white/10 border border-white/10 rounded-2xl rounded-tl-sm px-4 py-3">
        <div className="flex gap-1 items-center h-4">
          <span className="w-2 h-2 bg-blue-400 rounded-full animate-bounce [animation-delay:0ms]" />
          <span className="w-2 h-2 bg-blue-400 rounded-full animate-bounce [animation-delay:150ms]" />
          <span className="w-2 h-2 bg-blue-400 rounded-full animate-bounce [animation-delay:300ms]" />
        </div>
      </div>
    </div>
  );
}

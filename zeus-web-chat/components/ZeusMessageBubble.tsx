"use client";

import ReactMarkdown from "react-markdown";
import { ChatMessage } from "./ZeusChatWindow";
import { cn } from "@/utils/cn";

function QuotationCard({ content }: { content: string }) {
  try {
    const parsed = JSON.parse(content);
    if (!parsed.quotation && !parsed.order) return null;

    const q = parsed.quotation ?? parsed.order;
    const isOrder = !!parsed.order;

    return (
      <div className="mt-3 bg-gradient-to-br from-blue-900/60 to-slate-800/60 border border-blue-500/30 rounded-2xl p-4 text-sm space-y-2">
        <div className="flex items-center gap-2 mb-3">
          <span className="text-lg">{isOrder ? "📋" : "📄"}</span>
          <span className="text-blue-300 font-semibold">
            {isOrder ? "Order Confirmed" : "Quotation Created"}
          </span>
        </div>

        {q.quotation_number && (
          <div className="flex justify-between">
            <span className="text-white/50">Quotation No.</span>
            <span className="text-yellow-400 font-mono font-bold">{q.quotation_number}</span>
          </div>
        )}
        {q.order_number && (
          <div className="flex justify-between">
            <span className="text-white/50">Order No.</span>
            <span className="text-yellow-400 font-mono font-bold">{q.order_number}</span>
          </div>
        )}
        {q.vehicle && (
          <div className="flex justify-between">
            <span className="text-white/50">Vehicle</span>
            <span className="text-white text-right max-w-[60%]">{q.vehicle}</span>
          </div>
        )}
        {q.plan_name && (
          <div className="flex justify-between">
            <span className="text-white/50">Plan</span>
            <span className="text-white">{q.plan_type} · {q.plan_name}</span>
          </div>
        )}
        {q.annual_premium != null && (
          <div className="flex justify-between border-t border-white/10 pt-2 mt-2">
            <span className="text-white/50">Annual Premium</span>
            <span className="text-green-400 font-bold text-base">
              ฿{Number(q.annual_premium).toLocaleString()}
            </span>
          </div>
        )}
        {q.deductible != null && q.deductible > 0 && (
          <div className="flex justify-between">
            <span className="text-white/50">Deductible</span>
            <span className="text-orange-300">฿{Number(q.deductible).toLocaleString()}</span>
          </div>
        )}
        {q.total_amount != null && (
          <div className="flex justify-between border-t border-white/10 pt-2 mt-2">
            <span className="text-white/50">Total Amount</span>
            <span className="text-green-400 font-bold text-base">
              ฿{Number(q.total_amount).toLocaleString()}
            </span>
          </div>
        )}
        {q.valid_until && (
          <div className="flex justify-between">
            <span className="text-white/50">Valid Until</span>
            <span className="text-blue-300">{q.valid_until}</span>
          </div>
        )}
        {q.policy_number && (
          <div className="flex justify-between">
            <span className="text-white/50">Policy No.</span>
            <span className="text-purple-300 font-mono">{q.policy_number}</span>
          </div>
        )}
        {q.policy_status && (
          <div className="flex justify-between">
            <span className="text-white/50">Policy Status</span>
            <span className={cn(
              "font-semibold",
              q.policy_status === "active" ? "text-green-400" : "text-yellow-400"
            )}>
              {q.policy_status}
            </span>
          </div>
        )}
      </div>
    );
  } catch {
    return null;
  }
}

function tryExtractJson(content: string): { jsonStr: string | null; rest: string } {
  const match = content.match(/```json\s*([\s\S]*?)```/);
  if (match) {
    return { jsonStr: match[1].trim(), rest: content.replace(match[0], "").trim() };
  }
  const braceMatch = content.match(/(\{[\s\S]*"(quotation|order)"[\s\S]*\})/);
  if (braceMatch) {
    return { jsonStr: braceMatch[1].trim(), rest: content.replace(braceMatch[1], "").trim() };
  }
  return { jsonStr: null, rest: content };
}

const TOOL_LABELS: Record<string, string> = {
  search_quotation_details: "🔍 Searching car & plans…",
  search_policy_documents: "📄 Reading policy documents…",
  create_quotation: "📝 Creating quotation…",
  create_order: "🛒 Creating order…",
  update_order_payment: "💳 Updating payment…",
  get_order_status: "📋 Checking order status…",
};

export function ZeusMessageBubble({ message }: { message: ChatMessage }) {
  const isUser = message.role === "user";
  const isStreaming = !isUser && message.content === "" && !message.toolCalls?.length;

  const { jsonStr, rest } = isUser
    ? { jsonStr: null, rest: message.content }
    : tryExtractJson(message.content);

  return (
    <div className={cn("flex items-start gap-3 mb-4", isUser ? "flex-row-reverse" : "flex-row")}>
      {/* Avatar */}
      {!isUser && (
        <div className="w-8 h-8 rounded-full bg-gradient-to-br from-yellow-400 to-orange-500 flex items-center justify-center text-sm flex-shrink-0 mt-1">
          ⚡
        </div>
      )}

      <div className={cn("max-w-[80%] flex flex-col", isUser ? "items-end" : "items-start")}>
        {/* Image preview (user only) */}
        {message.imagePreview && (
          <img
            src={message.imagePreview}
            alt="Attached"
            className="mb-2 max-h-48 rounded-xl border border-white/20 object-cover"
          />
        )}

        {/* Active tool call pills */}
        {message.toolCalls && message.toolCalls.length > 0 && (
          <div className="flex flex-wrap gap-1 mb-2">
            {message.toolCalls.map((tool) => (
              <span
                key={tool}
                className="flex items-center gap-1 bg-blue-900/60 border border-blue-500/30 text-blue-300 text-xs rounded-full px-2 py-0.5"
              >
                <span className="w-1.5 h-1.5 rounded-full bg-blue-400 animate-pulse inline-block" />
                {TOOL_LABELS[tool] ?? tool}
              </span>
            ))}
          </div>
        )}

        {/* Bubble */}
        <div
          className={cn(
            "rounded-2xl px-4 py-3 text-sm leading-relaxed",
            isUser
              ? "bg-blue-600 text-white rounded-tr-sm"
              : "bg-white/10 border border-white/10 text-white/90 rounded-tl-sm",
          )}
        >
          {isUser ? (
            <span className="whitespace-pre-wrap">{rest}</span>
          ) : isStreaming ? (
            /* Initial loading dots before first token */
            <div className="flex gap-1 items-center h-4">
              <span className="w-2 h-2 bg-blue-400 rounded-full animate-bounce [animation-delay:0ms]" />
              <span className="w-2 h-2 bg-blue-400 rounded-full animate-bounce [animation-delay:150ms]" />
              <span className="w-2 h-2 bg-blue-400 rounded-full animate-bounce [animation-delay:300ms]" />
            </div>
          ) : (
            <>
            <ReactMarkdown
              components={{
                p: ({ children }) => <p className="mb-2 last:mb-0">{children}</p>,
                ul: ({ children }) => <ul className="list-disc pl-4 mb-2 space-y-1">{children}</ul>,
                ol: ({ children }) => <ol className="list-decimal pl-4 mb-2 space-y-1">{children}</ol>,
                li: ({ children }) => <li>{children}</li>,
                strong: ({ children }) => <strong className="text-yellow-300 font-semibold">{children}</strong>,
                code: ({ children }) => (
                  <code className="bg-black/30 text-blue-300 rounded px-1 py-0.5 text-xs font-mono">
                    {children}
                  </code>
                ),
                pre: ({ children }) => (
                  <pre className="bg-black/30 rounded-lg p-3 overflow-x-auto text-xs my-2">
                    {children}
                  </pre>
                ),
                h1: ({ children }) => <h1 className="text-lg font-bold text-yellow-300 mb-1">{children}</h1>,
                h2: ({ children }) => <h2 className="text-base font-bold text-yellow-300 mb-1">{children}</h2>,
                h3: ({ children }) => <h3 className="text-sm font-bold text-blue-300 mb-1">{children}</h3>,
                blockquote: ({ children }) => (
                  <blockquote className="border-l-2 border-blue-400 pl-3 text-white/60 italic my-2">
                    {children}
                  </blockquote>
                ),
                table: ({ children }) => (
                  <div className="overflow-x-auto my-2">
                    <table className="text-xs border-collapse w-full">{children}</table>
                  </div>
                ),
                th: ({ children }) => (
                  <th className="border border-white/20 bg-white/10 px-2 py-1 text-left text-blue-300">
                    {children}
                  </th>
                ),
                td: ({ children }) => (
                  <td className="border border-white/10 px-2 py-1">{children}</td>
                ),
              }}
            >
              {rest}
            </ReactMarkdown>
            </>
          )}
        </div>

        {/* Quotation / Order card */}
        {jsonStr && <QuotationCard content={jsonStr} />}
      </div>
    </div>
  );
}

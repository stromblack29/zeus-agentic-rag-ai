"use client";

const MODELS = [
  { value: "gemini-2.5-flash", label: "Gemini 2.5 Flash" },
  { value: "gemma-3-27b", label: "Gemma 3 27B" },
  { value: "ollama", label: "Ollama (Local)" },
  { value: "openrouter", label: "OpenRouter (Qwen 3)" },
];

export function ModelSelector({
  value,
  onChange,
}: {
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="bg-white/5 border border-white/15 text-white/80 text-xs rounded-lg px-2 py-1 outline-none cursor-pointer hover:border-blue-400/50 transition-colors"
    >
      {MODELS.map((m) => (
        <option key={m.value} value={m.value} className="bg-slate-900 text-white">
          {m.label}
        </option>
      ))}
    </select>
  );
}

"use client";

import { useRef } from "react";
import { Paperclip } from "lucide-react";

export function ImageUploadButton({
  onImage,
}: {
  onImage: (base64: string, preview: string) => void;
}) {
  const fileRef = useRef<HTMLInputElement>(null);

  const handleFile = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = () => {
      const result = reader.result as string;
      const base64 = result.split(",")[1];
      onImage(base64, result);
    };
    reader.readAsDataURL(file);
    e.target.value = "";
  };

  return (
    <>
      <input
        ref={fileRef}
        type="file"
        accept="image/*"
        className="hidden"
        onChange={handleFile}
      />
      <button
        type="button"
        onClick={() => fileRef.current?.click()}
        className="text-white/40 hover:text-white/70 transition-colors p-1 rounded"
        title="Attach image"
      >
        <Paperclip className="w-4 h-4" />
      </button>
    </>
  );
}

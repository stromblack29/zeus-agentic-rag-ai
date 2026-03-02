"use client";
import { Toaster as Sonner } from "sonner";

const Toaster = () => {
  return (
    <Sonner
      theme="dark"
      className="toaster group"
      toastOptions={{
        classNames: {
          toast: "group toast bg-slate-800 text-white border-white/10 shadow-lg px-4 py-3",
          description: "text-white/60 -mt-0.5",
        },
      }}
    />
  );
};

export { Toaster };

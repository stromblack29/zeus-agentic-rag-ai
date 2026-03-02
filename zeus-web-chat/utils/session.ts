export function getOrCreateSessionId(): string {
  if (typeof window === "undefined") return crypto.randomUUID();
  let sessionId = localStorage.getItem("zeus_session_id");
  if (!sessionId) {
    sessionId = crypto.randomUUID();
    localStorage.setItem("zeus_session_id", sessionId);
  }
  return sessionId;
}

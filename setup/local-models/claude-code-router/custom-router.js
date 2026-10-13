// Custom-Router fuer claude-code-router (ccr).
// Zweck: Der /lokal-Command erzwingt das lokale Modell. Er schreibt das
// Sentinel [[LOKAL]] in die Nachricht; dieser Router faengt es ab und leitet
// an das lokale Modell (Router.background). Ohne Sentinel wird null zurueckgegeben
// -> ccr nutzt die normalen Regeln aus Router (default/background/longContext ...).
//
// Signatur: module.exports = async (req, config) => "provider,model" | null
// Doku: https://github.com/musistudio/claude-code-router (Abschnitt Custom Router)

const LOCAL_SENTINEL = "[[LOKAL]]";
const FALLBACK_LOCAL_TARGET = "ollama,qwen3-coder:30b";
const DEFAULT_LONG_CONTEXT_THRESHOLD = 60000;

function textOf(message) {
  if (!message) return "";
  const content = message.content;
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => (part && typeof part.text === "string" ? part.text : ""))
      .join(" ");
  }
  return "";
}

// Nach einem Tool-Aufruf besteht die neueste user-Nachricht nur aus tool_result-Bloecken.
// Die zaehlen nicht als Nutzereingabe, sonst gaelte /lokal nur fuer den ersten Request.
function isToolResultOnly(message) {
  const content = message && message.content;
  return (
    Array.isArray(content) &&
    content.length > 0 &&
    content.every((part) => part && part.type === "tool_result")
  );
}

function lastUserPrompt(messages) {
  for (let i = messages.length - 1; i >= 0; i--) {
    const message = messages[i];
    if (message && message.role === "user" && !isToolResultOnly(message)) return message;
  }
  return null;
}

module.exports = async function router(req, config) {
  try {
    const messages = (req && req.body && req.body.messages) || [];
    if (!textOf(lastUserPrompt(messages)).includes(LOCAL_SENTINEL)) return null;

    // Zu langer Kontext: lokal wuerde Ollama den Anfang (Systemprompt) abschneiden.
    const router = (config && config.Router) || {};
    const threshold = router.longContextThreshold || DEFAULT_LONG_CONTEXT_THRESHOLD;
    if (typeof req.tokenCount === "number" && req.tokenCount > threshold) return null;

    return router.background || FALLBACK_LOCAL_TARGET;
  } catch (_err) {
    // Im Zweifel nicht erzwingen -> normale Router-Regeln greifen.
    return null;
  }
};

// Custom-Router fuer claude-code-router (ccr).
// Zweck: Der /lokal-Command erzwingt das lokale Modell. Er schreibt das
// Sentinel [[LOKAL]] in die Nachricht; dieser Router faengt es ab und leitet
// an Ollama/Qwen. Ohne Sentinel wird null zurueckgegeben -> ccr nutzt die
// normalen Regeln aus Router (default/background/longContext ...).
//
// Signatur: module.exports = async (req, config) => "provider,model" | null
// Doku: https://github.com/musistudio/claude-code-router (Abschnitt Custom Router)

const LOCAL_SENTINEL = "[[LOKAL]]";
const LOCAL_TARGET = "ollama,qwen3-coder:30b";

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

module.exports = async function router(req, _config) {
  try {
    const messages = (req && req.body && req.body.messages) || [];
    // Nur die letzte Nutzer-Nachricht pruefen: /lokal gilt fuer diesen Aufruf.
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i] && messages[i].role === "user") {
        if (textOf(messages[i]).includes(LOCAL_SENTINEL)) return LOCAL_TARGET;
        break;
      }
    }
  } catch (_err) {
    // Im Zweifel nicht erzwingen -> normale Router-Regeln greifen.
    return null;
  }
  return null;
};

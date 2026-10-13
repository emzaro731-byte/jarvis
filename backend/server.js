import express from "express";
import helmet from "helmet";

const app = express();
app.disable("x-powered-by");
app.use(helmet({ contentSecurityPolicy: false }));
app.use(express.json({ limit: "32kb" }));

const allowedOrigins = (process.env.ALLOWED_ORIGINS || "*").split(",").map(v => v.trim()).filter(Boolean);
app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (allowedOrigins.includes("*") || (origin && allowedOrigins.includes(origin))) {
    res.setHeader("Access-Control-Allow-Origin", origin || "*");
    res.setHeader("Vary", "Origin");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

const recent = new Map();
function rateLimit(req, res, next) {
  const ip = req.headers["x-forwarded-for"]?.split(",")[0]?.trim() || req.socket.remoteAddress || "unknown";
  const now = Date.now();
  const entry = recent.get(ip) || { start: now, count: 0 };
  if (now - entry.start > 60_000) { entry.start = now; entry.count = 0; }
  entry.count++;
  recent.set(ip, entry);
  if (entry.count > 30) return res.status(429).json({ error: "Too many requests. Try again in a minute." });
  next();
}

app.get("/health", (_req, res) => res.json({ ok: true, service: "jarvis-groq-proxy" }));

app.post("/api/chat", rateLimit, async (req, res) => {
  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) return res.status(503).json({ error: "Server is missing GROQ_API_KEY. Add it in Render Environment settings." });
  const { messages, temperature = 0.5, max_tokens = 700 } = req.body || {};
  if (!Array.isArray(messages) || messages.length < 1 || messages.length > 20) {
    return res.status(400).json({ error: "messages must be an array with 1–20 items." });
  }
  const safeMessages = [];
  for (const item of messages) {
    if (!item || !["system", "user", "assistant"].includes(item.role) || typeof item.content !== "string") {
      return res.status(400).json({ error: "Each message needs a valid role and text content." });
    }
    safeMessages.push({ role: item.role, content: item.content.slice(0, 8000) });
  }
  try {
    const upstream = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${apiKey}` },
      body: JSON.stringify({
        model: "openai/gpt-oss-120b",
        messages: safeMessages,
        temperature: Math.max(0, Math.min(1, Number(temperature) || 0.5)),
        max_tokens: Math.max(1, Math.min(1000, Number(max_tokens) || 700))
      }),
      signal: AbortSignal.timeout(45_000)
    });
    const data = await upstream.json().catch(() => ({}));
    if (!upstream.ok) {
      console.error("Groq upstream status:", upstream.status);
      return res.status(upstream.status === 429 ? 429 : 502).json({ error: data.error?.message || "Groq request failed." });
    }
    res.json(data);
  } catch (err) {
    console.error("Groq request error:", err.message);
    res.status(502).json({ error: "Could not reach Groq. Please try again." });
  }
});

const port = Number(process.env.PORT || 10000);
app.listen(port, "0.0.0.0", () => console.log(`JARVIS Groq proxy listening on ${port}`));

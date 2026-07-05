import express from "express";
import cors from "cors";
import bonjour from "bonjour";
import fs from "fs";
import path from "path";
import os from "os";
import { HermesApiClient } from "./hermes-api";
import { HermesConfig } from "./types";

const PORT = parseInt(process.env.PORT || "3847", 10);
const HERMES_URL = process.env.HERMES_URL || "http://localhost:8648";
const HERMES_PROFILE = process.env.HERMES_PROFILE || "default";

/** 自动发现 Hermes API token（优先 ENV → .model-run-token → 空） */
function resolveApiKey(): string {
  // 1. 显式设置的环境变量
  if (process.env.HERMES_API_KEY) return process.env.HERMES_API_KEY;
  // 2. Hermes profile 目录下的 JWT token
  const tokenPath = path.join(
    os.homedir(), ".hermes-web-ui", "profiles", HERMES_PROFILE, ".model-run-token"
  );
  try {
    return fs.readFileSync(tokenPath, "utf-8").trim();
  } catch {
    return "";
  }
}

const HERMES_API_KEY = resolveApiKey();

const config: HermesConfig = {
  baseUrl: HERMES_URL,
  apiKey: HERMES_API_KEY,
  profile: HERMES_PROFILE,
};

const api = new HermesApiClient(config);

const app = express();
app.use(cors());
app.use(express.json());

// === Health ===
app.get("/health", (_req, res) => {
  res.json({ ok: true, hermesUrl: HERMES_URL, profile: HERMES_PROFILE });
});

// === Chat ===
app.post("/api/chat", async (req, res) => {
  try {
    const { input, session_id, model, provider } = req.body;
    if (!input || typeof input !== "string") {
      res.status(400).json({ error: "input is required" });
      return;
    }

    const result = await api.chat({ input, session_id, model, provider });
    res.json(result);
  } catch (err: any) {
    console.error("Chat error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// === Sessions ===
app.get("/api/sessions", async (_req, res) => {
  try {
    const result = await api.listSessions();
    // Hermes API wraps in { sessions: [...] }, unwrap for the watch client
    const sessions = Array.isArray(result) ? result : (result as any).sessions || [];
    res.json(sessions);
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// === Start ===
app.listen(PORT, "0.0.0.0", () => {
  console.log(`WristHermes Bridge running on port ${PORT}`);
  console.log(`Hermes URL: ${HERMES_URL}`);

  // Bonjour 广播
  try {
    const bj = bonjour();
    bj.publish({
      name: "WristHermes",
      type: "http",
      port: PORT,
      txt: { hermes_url: HERMES_URL, version: "0.1.0" },
    });
    console.log("Bonjour service published: WristHermes._http._tcp.local");
  } catch (e) {
    console.warn("Bonjour not available:", e);
  }
});

import { HermesConfig, ChatRequest, ChatResponse, SessionInfo } from "./types";

export class HermesApiClient {
  private config: HermesConfig;

  constructor(config: HermesConfig) {
    this.config = config;
  }

  private headers(): Record<string, string> {
    const h: Record<string, string> = { "Content-Type": "application/json" };
    if (this.config.apiKey) h["Authorization"] = `Bearer ${this.config.apiKey}`;
    return h;
  }

  /** POST /api/chat-run/runs — 发送消息并等待完整回复 */
  async chat(req: ChatRequest): Promise<ChatResponse> {
    const body: Record<string, unknown> = {
      input: req.input,
      timeout_ms: req.timeout_ms ?? 300000,
    };
    if (req.session_id) body["session_id"] = req.session_id;
    if (req.model) body["model"] = req.model;
    if (req.provider) body["provider"] = req.provider;
    if (req.profile || this.config.profile) body["profile"] = req.profile || this.config.profile;

    const res = await fetch(`${this.config.baseUrl}/api/chat-run/runs`, {
      method: "POST",
      headers: this.headers(),
      body: JSON.stringify(body),
    });

    if (!res.ok) {
      const err = await res.text();
      throw new Error(`Hermes API error ${res.status}: ${err}`);
    }

    return res.json();
  }

  /** GET /api/hermes/sessions — 获取 session 列表 */
  async listSessions(limit = 20): Promise<SessionInfo[]> {
    const url = `${this.config.baseUrl}/api/hermes/sessions?limit=${limit}`;
    const res = await fetch(url, { headers: this.headers() });
    if (!res.ok) throw new Error(`Failed to list sessions: ${res.status}`);
    return res.json();
  }

  /** GET /api/hermes/sessions/{id} — 获取单个 session */
  async getSession(id: string): Promise<SessionInfo> {
    const res = await fetch(`${this.config.baseUrl}/api/hermes/sessions/${id}`, {
      headers: this.headers(),
    });
    if (!res.ok) throw new Error(`Failed to get session: ${res.status}`);
    return res.json();
  }
}

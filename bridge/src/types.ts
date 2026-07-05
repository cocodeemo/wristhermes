// === Hermes Web UI API 类型 ===

export interface HermesConfig {
  baseUrl: string;       // e.g. "http://localhost:8648"
  profile?: string;      // Hermes profile name
  apiKey?: string;       // API_SERVER_KEY
}

export interface ChatRequest {
  input: string;
  session_id?: string;
  model?: string;
  provider?: string;
  profile?: string;
  timeout_ms?: number;
}

export interface ChatResponse {
  ok: boolean;
  status: "completed" | "failed" | "cancelled";
  session_id: string;
  run_id: string;
  output: string;
  reasoning?: string;
}

export interface SessionInfo {
  id: string;
  title: string;
  source: string;
  created_at: string;
  updated_at: string;
}

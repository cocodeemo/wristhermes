# WristHermes MVP 实施计划

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** 把 Apple Watch 变成 Hermes Agent 的腕上终端——发 prompt、看流式回复。

**Architecture:** Apple Watch (SwiftUI) ← HTTP/Bonjour → Bridge Server (Node.js/Express) → Hermes Web UI API (POST /api/chat-run/runs) | Hermes CLI (fallback)

**Tech Stack:** Swift 5.9+ / SwiftUI (watchOS 10+) | Node.js 20+ / Express | Hermes Web UI v0.6.18

**Constraints:** 本地 WiFi 局域网，Bonjour/mDNS 自动发现，MVP 先非流式（等待完整回复），v0.2 加 SSE 流式。

---

## 项目结构

```
wristhermes/
├── bridge/                    # Node.js Bridge Server
│   ├── package.json
│   ├── src/
│   │   ├── index.ts           # Express 入口 + Bonjour 广播
│   │   ├── hermes-api.ts      # Hermes Web UI API 客户端
│   │   ├── hermes-cli.ts      # Hermes CLI 进程管理（fallback）
│   │   ├── session-manager.ts # Session 列表/切换管理
│   │   └── types.ts           # 共享类型定义
│   └── tsconfig.json
├── watch/                     # watchOS SwiftUI App
│   ├── WristHermes.xcodeproj/
│   ├── WristHermes/
│   │   ├── WristHermesApp.swift
│   │   ├── Views/
│   │   │   ├── ContentView.swift      # 主界面（对话列表）
│   │   │   ├── ChatView.swift         # 对话详情
│   │   │   ├── MessageBubble.swift    # 消息气泡
│   │   │   ├── InputView.swift        # 输入框（语音听写+文字）
│   │   │   ├── SessionListView.swift  # Session 列表/切换
│   │   │   └── SettingsView.swift     # 设置（Bridge 地址等）
│   │   ├── Services/
│   │   │   ├── BridgeClient.swift     # HTTP 客户端（连接 Bridge）
│   │   │   ├── BonjourBrowser.swift   # Bonjour 服务发现
│   │   │   └── SessionStore.swift     # 本地 Session 缓存
│   │   └── Models/
│   │       ├── Message.swift          # 消息模型
│   │       └── Session.swift          # Session 模型
│   └── WristHermes Watch App/
│       └── Assets.xcassets/
└── docs/
    └── plans/
        └── 2026-06-29-wristhermes-mvp.md
```

---

## Phase 1: Bridge Server（Node.js）

### Task 1.1: 初始化项目

**Files:**
- Create: `bridge/package.json`
- Create: `bridge/tsconfig.json`

```json
// bridge/package.json
{
  "name": "wristhermes-bridge",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "express": "^4.21.0",
    "bonjour": "^3.5.0",
    "cors": "^2.8.5"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/bonjour": "^3.5.13",
    "@types/cors": "^2.8.17",
    "typescript": "^5.5.0",
    "tsx": "^4.19.0"
  }
}
```

```json
// bridge/tsconfig.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
```

**Step 1:** `cd /mnt/d/wristhermes/bridge && npm install`
**Step 2:** Verify `npx tsc --noEmit` passes.

---

### Task 1.2: 类型定义

**Create:** `bridge/src/types.ts`

```typescript
// === Hermes API 类型 ===

export interface HermesConfig {
  baseUrl: string;      // e.g. "http://localhost:8648"
  profile?: string;     // Hermes profile name
  apiKey?: string;      // API_SERVER_KEY
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
```

---

### Task 1.3: Hermes Web UI API 客户端

**Create:** `bridge/src/hermes-api.ts`

```typescript
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
      timeout_ms: req.timeout_ms ?? 300000, // 5min default
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
```

**Step 1:** `npx tsc --noEmit` 确认类型正确。

---

### Task 1.4: Hermes CLI 进程管理（Fallback）

**Create:** `bridge/src/hermes-cli.ts`

```typescript
import { spawn, ChildProcess } from "child_process";
import { ChatRequest, ChatResponse } from "./types";

export class HermesCliRunner {
  private process: ChildProcess | null = null;

  /** 通过 hermes chat -q 执行单次查询 */
  async chat(req: ChatRequest): Promise<ChatResponse> {
    return new Promise((resolve, reject) => {
      const args = ["chat", "-q", req.input, "-Q"]; // -Q = quiet mode
      if (req.model) args.push("-m", req.model);
      if (req.session_id) args.push("-r", req.session_id);

      const child = spawn("hermes", args, {
        env: { ...process.env, HOME: process.env.HOME },
        timeout: req.timeout_ms ?? 300000,
      });

      let stdout = "";
      let stderr = "";

      child.stdout.on("data", (d: Buffer) => { stdout += d.toString(); });
      child.stderr.on("data", (d: Buffer) => { stderr += d.toString(); });

      child.on("close", (code) => {
        if (code !== 0) {
          reject(new Error(`Hermes CLI exited ${code}: ${stderr}`));
        } else {
          resolve({
            ok: true,
            status: "completed",
            session_id: req.session_id ?? "",
            run_id: "",
            output: stdout.trim(),
          });
        }
      });

      child.on("error", reject);
    });
  }

  /** 检查 hermes CLI 是否可用 */
  static async isAvailable(): Promise<boolean> {
    return new Promise((resolve) => {
      const child = spawn("hermes", ["--version"], { timeout: 5000 });
      child.on("close", (code) => resolve(code === 0));
      child.on("error", () => resolve(false));
    });
  }
}
```

---

### Task 1.5: Express 服务器 + Bonjour 广播

**Create:** `bridge/src/index.ts`

```typescript
import express from "express";
import cors from "cors";
import bonjour from "bonjour";
import { HermesApiClient } from "./hermes-api";
import { HermesCliRunner } from "./hermes-cli";
import { HermesConfig } from "./types";

const PORT = parseInt(process.env.PORT || "3847", 10);
const HERMES_URL = process.env.HERMES_URL || "http://localhost:8648";
const HERMES_API_KEY = process.env.HERMES_API_KEY || "";
const HERMES_PROFILE = process.env.HERMES_PROFILE || "default";

const config: HermesConfig = {
  baseUrl: HERMES_URL,
  apiKey: HERMES_API_KEY,
  profile: HERMES_PROFILE,
};

const api = new HermesApiClient(config);
const cli = new HermesCliRunner();
let useCli = false; // fallback flag

const app = express();
app.use(cors());
app.use(express.json());

// === Health ===
app.get("/health", (_req, res) => {
  res.json({ ok: true, mode: useCli ? "cli" : "api", hermesUrl: HERMES_URL });
});

// === Chat ===
app.post("/api/chat", async (req, res) => {
  try {
    const { input, session_id, model, provider } = req.body;
    if (!input || typeof input !== "string") {
      return res.status(400).json({ error: "input is required" });
    }

    let result;
    if (useCli) {
      result = await cli.chat({ input, session_id, model });
    } else {
      result = await api.chat({ input, session_id, model, provider });
    }

    res.json(result);
  } catch (err: any) {
    console.error("Chat error:", err.message);
    res.status(500).json({ error: err.message });
  }
});

// === Sessions ===
app.get("/api/sessions", async (_req, res) => {
  try {
    const sessions = await api.listSessions();
    res.json(sessions);
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// === Switch mode ===
app.post("/api/mode", (req, res) => {
  const { mode } = req.body;
  if (mode === "cli") {
    useCli = true;
    res.json({ mode: "cli" });
  } else if (mode === "api") {
    useCli = false;
    res.json({ mode: "api" });
  } else {
    res.status(400).json({ error: 'mode must be "cli" or "api"' });
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
    console.warn("Bonjour not available (non-macOS):", e);
  }
});
```

**Step 1:** `npx tsc --noEmit` 确认类型
**Step 2:** `npm run dev` 启动，确认 `curl http://localhost:3847/health` 返回 `{"ok":true}`

---

### Task 1.6: 配置 Bridge 连接 Hermes Web UI

Bridge 需要访问 Hermes Web UI API。在你的 WSL 环境里：

**创建 Bridge 启动配置：**

```bash
# bridge/.env（不提交 git）
HERMES_URL=http://localhost:8648
HERMES_API_KEY=      # 如果 Hermes Web UI 配了 API_SERVER_KEY，填这里
HERMES_PROFILE=default
PORT=3847
```

**逻辑：**
- Hermes Web UI 运行在 WSL 的 `localhost:8648`
- Bridge 跑在 WSL 上，通过 `localhost` 访问 Hermes Web UI
- watchOS App 通过局域网 IP 连 Bridge（`http://<WSL_IP>:3847`）

---

## Phase 2: watchOS App（SwiftUI）

### Task 2.1: 创建 Xcode 项目

在 macOS 上用 Xcode 创建：
- Template: watchOS → App
- Name: `WristHermes`
- Interface: SwiftUI
- Lifecycle: SwiftUI App
- Language: Swift
- 勾选 "Include Watch App"

项目放到 `watch/` 目录下。

---

### Task 2.2: 数据模型

**Create:** `watch/WristHermes/WristHermes/Models/Message.swift`

```swift
import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    enum MessageRole: String, Codable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
```

**Create:** `watch/WristHermes/WristHermes/Models/Session.swift`

```swift
import Foundation

struct ChatSession: Identifiable, Codable {
    let id: String
    var title: String
    let createdAt: Date
    var updatedAt: Date

    init(id: String, title: String = "New Chat", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
```

---

### Task 2.3: Bridge HTTP 客户端

**Create:** `watch/WristHermes/WristHermes/Services/BridgeClient.swift`

```swift
import Foundation

class BridgeClient: ObservableObject {
    private var baseURL: URL
    @Published var isConnected = false

    init(baseURL: URL = URL(string: "http://localhost:3847")!) {
        self.baseURL = baseURL
    }

    func updateBaseURL(_ url: URL) {
        self.baseURL = url
    }

    // POST /api/chat
    func sendMessage(_ input: String, sessionId: String? = nil) async throws -> ChatResponse {
        var body: [String: Any] = ["input": input]
        if let sid = sessionId { body["session_id"] = sid }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw BridgeError.serverError(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }

    // GET /api/sessions
    func listSessions() async throws -> [SessionInfo] {
        let request = URLRequest(url: baseURL.appendingPathComponent("api/sessions"))
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([SessionInfo].self, from: data)
    }

    // GET /health
    func checkHealth() async -> Bool {
        do {
            let request = URLRequest(url: baseURL.appendingPathComponent("health"))
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Response Types

struct ChatResponse: Codable {
    let ok: Bool
    let status: String
    let sessionId: String?
    let output: String?
    let reasoning: String?

    enum CodingKeys: String, CodingKey {
        case ok, status, output, reasoning
        case sessionId = "session_id"
    }
}

struct SessionInfo: Codable, Identifiable {
    let id: String
    let title: String?
    let source: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, source
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum BridgeError: Error {
    case serverError(status: Int)
    case notFound
}
```

---

### Task 2.4: Bonjour 服务发现

**Create:** `watch/WristHermes/WristHermes/Services/BonjourBrowser.swift`

```swift
import Network

class BonjourBrowser: ObservableObject {
    @Published var discoveredServices: [NWBrowser.Result] = []
    private var browser: NWBrowser?

    func startBrowsing() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        browser = NWBrowser(for: .bonjour(type: "_http._tcp", domain: "local"), using: parameters)

        browser?.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                self?.discoveredServices = results
                    .filter { result in
                        // 只保留 WristHermes 服务
                        result.endpoint.debugDescription.contains("WristHermes")
                    }
            }
        }

        browser?.start(queue: .main)
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
    }

    /// 从 Bonjour result 提取 IP:Port
    func resolveEndpoint(_ result: NWBrowser.Result) async -> URL? {
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(to: result.endpoint, using: .tcp)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case .hostPort(let host, let port) = connection.currentEndpoint {
                        var urlString = "http://\(host.debugDescription):\(port)"
                        // 清理 NWEndpoint debugDescription 的格式
                        urlString = urlString.replacingOccurrences(of: "%", with: "")
                        continuation.resume(returning: URL(string: urlString))
                    } else {
                        continuation.resume(returning: nil)
                    }
                    connection.cancel()
                case .failed:
                    continuation.resume(returning: nil)
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: .main)
        }
    }
}
```

---

### Task 2.5: 主界面

**Create:** `watch/WristHermes/WristHermes/Views/ContentView.swift`

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var bridgeClient = BridgeClient()
    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var currentSessionId: String? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 消息列表
                ScrollViewReader { proxy in
                    List {
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                // 输入区域
                InputView(
                    text: $inputText,
                    isLoading: isLoading,
                    onSend: sendMessage
                )
            }
            .navigationTitle("WristHermes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SessionListView(bridgeClient: bridgeClient, currentSessionId: $currentSessionId)) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
            }
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        let userMsg = Message(role: .user, content: text)
        messages.append(userMsg)
        inputText = ""
        isLoading = true

        Task {
            do {
                let response = try await bridgeClient.sendMessage(text, sessionId: currentSessionId)
                // 保存 session_id
                if let sid = response.sessionId, currentSessionId == nil {
                    currentSessionId = sid
                }
                let reply = response.output ?? "(empty response)"
                let assistantMsg = Message(role: .assistant, content: reply)
                await MainActor.run {
                    messages.append(assistantMsg)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    messages.append(Message(role: .assistant, content: "Error: \(error.localizedDescription)"))
                    isLoading = false
                }
            }
        }
    }
}
```

---

### Task 2.6: 消息气泡组件

**Create:** `watch/WristHermes/WristHermes/Views/MessageBubble.swift`

```swift
import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 20)
            }

            Text(message.content)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(message.role == .user ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if message.role == .assistant {
                Spacer(minLength: 20)
            }
        }
        .listRowBackground(Color.clear)
    }
}
```

---

### Task 2.7: 输入组件（支持语音听写）

**Create:** `watch/WristHermes/WristHermes/Views/InputView.swift`

```swift
import SwiftUI

struct InputView: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            // 语音听写按钮
            Button(action: {}) {
                Image(systemName: "mic.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            // 文本输入
            TextField("Message...", text: $text)
                .textFieldStyle(.plain)
                .font(.caption2)

            // 发送按钮
            Button(action: onSend) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundColor(text.isEmpty ? .gray : .blue)
                }
            }
            .disabled(text.isEmpty || isLoading)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }
}
```

---

### Task 2.8: Session 列表

**Create:** `watch/WristHermes/WristHermes/Views/SessionListView.swift`

```swift
import SwiftUI

struct SessionListView: View {
    @ObservedObject var bridgeClient: BridgeClient
    @Binding var currentSessionId: String?
    @State private var sessions: [SessionInfo] = []
    @State private var isLoading = false

    var body: some View {
        List {
            // 新建对话
            Button(action: { currentSessionId = nil }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.green)
                    Text("New Chat")
                }
            }

            // Session 列表
            ForEach(sessions) { session in
                Button(action: { currentSessionId = session.id }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title ?? "Untitled")
                                .font(.caption)
                                .lineLimit(1)
                            if let updated = session.updatedAt {
                                Text(formatDate(updated))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if session.id == currentSessionId {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .task {
            await loadSessions()
        }
    }

    private func loadSessions() async {
        isLoading = true
        do {
            sessions = try await bridgeClient.listSessions()
        } catch {
            print("Failed to load sessions: \(error)")
        }
        isLoading = false
    }

    private func formatDate(_ iso: String) -> String {
        // 简单截取日期部分
        String(iso.prefix(10))
    }
}
```

---

### Task 2.9: App 入口

**Update:** `watch/WristHermes/WristHermes/WristHermesApp.swift`

```swift
import SwiftUI

@main
struct WristHermesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

---

## Phase 3: 集成 & 测试

### Task 3.1: Bridge ↔ Hermes 端到端测试

**Step 1:** 启动 Hermes Web UI（已在运行，`http://localhost:8648`）
**Step 2:** 启动 Bridge：`cd bridge && npm run dev`
**Step 3:** 测试：

```bash
# 健康检查
curl http://localhost:3847/health

# 发送消息（新 session）
curl -X POST http://localhost:3847/api/chat \
  -H "Content-Type: application/json" \
  -d '{"input": "Hello, what time is it?"}'

# 获取 session 列表
curl http://localhost:3847/api/sessions

# 切换 CLI 模式
curl -X POST http://localhost:3847/api/mode \
  -H "Content-Type: application/json" \
  -d '{"mode": "cli"}'

# 切回 API 模式
curl -X POST http://localhost:3847/api/mode \
  -H "Content-Type: application/json" \
  -d '{"mode": "api"}'
```

---

### Task 3.2: watchOS App 在模拟器上测试

需要 macOS + Xcode：
1. 打开 `watch/WristHermes.xcodeproj`
2. 选择 "WristHermes Watch App" target
3. 在 Info.plist 添加 `NSAppTransportSecurity` → `NSAllowsArbitraryLoads = YES`（允许 HTTP 局域网连接）
4. 修改 `BridgeClient` 的 baseURL 为 Bridge 的局域网 IP（如 `http://192.168.1.x:3847`）
5. Run → watchOS Simulator

---

### Task 3.3: 配置 WSL Windows 防火墙

Mac 上的 watchOS 模拟器 / 真机需要通过局域网连到 WSL 的 Bridge：

```powershell
# 在 Windows 上执行（管理员 PowerShell）
# 允许 WSL 端口 3847 入站
netsh advfirewall firewall add rule name="WristHermes Bridge" dir=in action=allow protocol=TCP localport=3847

# 或者用 Windows 防火墙 GUI 添加
```

也可以用 `wslhost` 或端口转发：

```powershell
# 端口转发：Windows 3847 → WSL 3847
netsh interface portproxy add v4tov4 listenport=3847 listenaddress=0.0.0.0 connectport=3847 connectaddress=172.x.x.x
```

---

## 后续规划（v0.2+）

| 功能 | 优先级 | 说明 |
|------|--------|------|
| SSE 流式回复 | P0 | Bridge 转发 Hermes SSE → watchOS 逐字显示 |
| 语音听写集成 | P1 | watchOS `WKExtension` 原生语音识别，不需要按钮 |
| 快捷指令（Quick Actions） | P1 | "继续"、"修一下"、"重试" 等一键 pill |
| Diff 预览 | P2 | 腕上看 code diff（小屏挑战大） |
| Complication 入口 | P2 | 表盘复杂功能入口 |
| 多 Profile 切换 | P3 | 表上选 Hermes Profile |
| 消息历史缓存 | P3 | offline 也能看历史 |

---

## 环境依赖

| 需求 | 当前状态 | 备注 |
|------|----------|------|
| Node.js 20+ | ✅ v23.11.0 | WSL 已装 |
| npm | ✅ | 跨文件系统慢但能跑 |
| Hermes Web UI | ✅ v0.6.18 | systemd 已运行，端口 8648 |
| macOS + Xcode 16+ | ❓ | 需要 Mac 开发 watchOS App |
| Apple Watch (watchOS 10+) | ❓ | 真机测试 |

---

## 注意事项

1. **WSL 网络**：watchOS App 连到 WSL 的 Bridge 需要解决跨子网问题。最简单方案：Bridge 跑在 Windows 宿主机上（而不是 WSL 里），直接 `localhost:3847` 可访问 Hermes Web UI（如果 Hermes Web UI 绑定 0.0.0.0:8648）
2. **Hermes Web UI API** 目前是同步等待模式（POST + 等待完成），非流式。流式需要 Socket.IO 或 SSE，待 v0.2
3. **Bonjour** 库在 Windows/WSL 上不可用，macOS/Linux 上 OK。Bridge 跑在 Mac 上时 Bonjour 正常工作
4. **API_SERVER_KEY**：如果 Hermes Web UI 配了 API key，Bridge 需要传 `Authorization: Bearer <key>`

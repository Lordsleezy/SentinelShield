import { spawn, ChildProcessWithoutNullStreams } from "child_process";
import fs from "fs";
import path from "path";
import { app } from "electron";
import { appendLog } from "./logger";

type Pending = {
  resolve: (value: unknown) => void;
  reject: (reason?: unknown) => void;
  timer: ReturnType<typeof setTimeout>;
};

type SidecarMessage = {
  id?: string;
  type?: string;
  event?: string;
  ok?: boolean;
  data?: unknown;
  error?: string;
};

export type SidecarStatus = {
  alive: boolean;
  ready: boolean;
  lastPingMs: number | null;
  restartCount: number;
};

const SLOW_COMMANDS = new Set(["scan", "cleaner_preview", "cleaner_run", "network_scan"]);
const DEFAULT_TIMEOUT_MS = 90_000;
const SLOW_TIMEOUT_MS = 600_000;

export class SidecarClient {
  private proc: ChildProcessWithoutNullStreams | null = null;
  private pending = new Map<string, Pending>();
  private progressCallbacks = new Map<string, (data: unknown) => void>();
  private eventHandler: ((event: string, data: unknown) => void) | null = null;
  private statusHandler: ((status: SidecarStatus) => void) | null = null;
  private buffer = "";
  private restartCount = 0;
  private lastRestart = 0;
  private dataDir = "";
  private appRoot = "";
  private ready = false;
  private lastPingMs: number | null = null;
  private pingTimer: ReturnType<typeof setInterval> | null = null;

  start(dataDir: string): void {
    this.dataDir = dataDir;
    this.appRoot = app.isPackaged
      ? process.resourcesPath
      : path.resolve(app.getAppPath());
    this.spawnProcess();
    this.startPingLoop();
  }

  onEvent(handler: (event: string, data: unknown) => void): void {
    this.eventHandler = handler;
  }

  onStatus(handler: (status: SidecarStatus) => void): void {
    this.statusHandler = handler;
  }

  getStatus(): SidecarStatus {
    return {
      alive: Boolean(this.proc && !this.proc.killed),
      ready: this.ready,
      lastPingMs: this.lastPingMs,
      restartCount: this.restartCount,
    };
  }

  private emitStatus(): void {
    this.statusHandler?.(this.getStatus());
  }

  private sidecarPath(): string {
    if (app.isPackaged) {
      return path.join(process.resourcesPath, "sentinel_shield_core.exe");
    }
    const candidates = [
      path.resolve(
        app.getAppPath(),
        "src/sidecar/target/x86_64-pc-windows-msvc/release/sentinel_shield_core.exe"
      ),
      path.resolve(
        app.getAppPath(),
        "src/sidecar/target/release/sentinel_shield_core.exe"
      ),
    ];
    for (const candidate of candidates) {
      if (fs.existsSync(candidate)) {
        return candidate;
      }
    }
    return candidates[0];
  }

  private timeoutFor(cmd: string): number {
    return SLOW_COMMANDS.has(cmd) ? SLOW_TIMEOUT_MS : DEFAULT_TIMEOUT_MS;
  }

  private spawnProcess(): void {
    const exe = this.sidecarPath();
    this.ready = false;
    this.emitStatus();
    appendLog(`Starting sidecar: ${exe}`);

    if (!fs.existsSync(exe)) {
      appendLog(`Sidecar binary missing: ${exe}`);
    }

    this.proc = spawn(exe, [], {
      env: {
        ...process.env,
        SENTINEL_DATA_DIR: this.dataDir,
        SENTINEL_APP_ROOT: this.appRoot,
        SENTINEL_RULES_DIR: path.join(this.appRoot, "rules"),
      },
      stdio: ["pipe", "pipe", "pipe"],
      windowsHide: true,
    });

    this.proc.stdout.on("data", (chunk: Buffer) => {
      this.onData(chunk.toString("utf8"));
    });

    this.proc.stderr.on("data", (chunk: Buffer) => {
      appendLog(`sidecar stderr: ${chunk.toString("utf8")}`);
    });

    this.proc.on("exit", (code) => {
      appendLog(`Sidecar exited with code ${code}`);
      this.ready = false;
      this.emitStatus();
      this.rejectAll(new Error("Sidecar stopped"));
      this.maybeRestart();
    });

    this.proc.on("error", (err) => {
      appendLog(`Sidecar error: ${err.message}`);
      this.ready = false;
      this.emitStatus();
    });

    setTimeout(() => {
      void this.ping().catch(() => undefined);
    }, 1500);
  }

  private startPingLoop(): void {
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
    }
    this.pingTimer = setInterval(() => {
      void this.ping().catch(() => undefined);
    }, 30_000);
  }

  async ping(): Promise<boolean> {
    try {
      const started = Date.now();
      await this.request("ping");
      this.lastPingMs = Date.now() - started;
      this.ready = true;
      this.emitStatus();
      return true;
    } catch {
      this.ready = false;
      this.emitStatus();
      return false;
    }
  }

  private maybeRestart(): void {
    const now = Date.now();
    if (now - this.lastRestart > 60_000) {
      this.restartCount = 0;
    }
    if (this.restartCount >= 3) {
      appendLog("Sidecar restart limit reached");
      return;
    }
    this.restartCount += 1;
    this.lastRestart = now;
    this.emitStatus();
    setTimeout(() => this.spawnProcess(), 1000);
  }

  private rejectAll(reason: Error): void {
    for (const [, pending] of this.pending) {
      clearTimeout(pending.timer);
      pending.reject(reason);
    }
    this.pending.clear();
    this.progressCallbacks.clear();
  }

  private onData(chunk: string): void {
    this.buffer += chunk;
    const lines = this.buffer.split("\n");
    this.buffer = lines.pop() ?? "";
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) {
        continue;
      }
      try {
        const msg = JSON.parse(trimmed) as SidecarMessage;
        if (msg.type === "progress" && msg.id) {
          const onProgress = this.progressCallbacks.get(msg.id);
          onProgress?.(msg.data ?? {});
          continue;
        }
        if (msg.type === "event" && msg.event) {
          this.eventHandler?.(msg.event, msg.data ?? {});
          continue;
        }
        if (!msg.id) {
          appendLog(`Sidecar message without id: ${trimmed.slice(0, 200)}`);
          continue;
        }
        const pending = this.pending.get(msg.id);
        if (!pending) {
          continue;
        }
        clearTimeout(pending.timer);
        this.pending.delete(msg.id);
        this.progressCallbacks.delete(msg.id);
        if (msg.ok) {
          pending.resolve(msg.data ?? {});
        } else {
          appendLog(`Sidecar error response (${msg.id}): ${msg.error ?? "unknown"}`);
          pending.reject(new Error(msg.error ?? "Something didn't work."));
        }
      } catch {
        appendLog(`Invalid sidecar JSON: ${trimmed.slice(0, 200)}`);
      }
    }
  }

  request(
    cmd: string,
    params: Record<string, unknown> = {},
    onProgress?: (data: unknown) => void
  ): Promise<unknown> {
    if (!this.proc?.stdin.writable) {
      return Promise.reject(new Error("Sidecar is not ready."));
    }
    const id = crypto.randomUUID();
    if (onProgress) {
      this.progressCallbacks.set(id, onProgress);
    }
    const timeoutMs = this.timeoutFor(cmd);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        this.progressCallbacks.delete(id);
        appendLog(`Sidecar request timed out (${cmd}, ${timeoutMs}ms)`);
        reject(new Error(`Request timed out: ${cmd}`));
      }, timeoutMs);

      this.pending.set(id, { resolve, reject, timer });
      const payload = JSON.stringify({ id, cmd, params }) + "\n";
      this.proc!.stdin.write(payload, (err) => {
        if (err) {
          clearTimeout(timer);
          this.pending.delete(id);
          this.progressCallbacks.delete(id);
          appendLog(`Sidecar write failed (${cmd}): ${err.message}`);
          reject(err);
        }
      });
    });
  }

  async runDiagnostics(): Promise<Record<string, string>> {
    const commands = [
      "ping",
      "memory_status",
      "cleaner_preview",
      "optimizer_list",
      "network_scan",
      "threat_history_list",
      "realtime_status",
    ] as const;

    const results: Record<string, string> = {};
    for (const cmd of commands) {
      const started = Date.now();
      try {
        const data = await this.request(cmd, cmd === "threat_history_list" ? { limit: 5 } : {});
        const ms = Date.now() - started;
        const preview = JSON.stringify(data).slice(0, 180);
        results[cmd] = `ok ${ms}ms ${preview}`;
        appendLog(`Diagnostic ${cmd}: ok (${ms}ms)`);
      } catch (error) {
        results[cmd] = `fail ${String(error)}`;
        appendLog(`Diagnostic ${cmd}: fail ${String(error)}`);
      }
    }
    return results;
  }

  stop(): void {
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
    this.proc?.kill();
    this.proc = null;
    this.ready = false;
    this.emitStatus();
  }
}

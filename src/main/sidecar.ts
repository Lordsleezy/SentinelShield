import { spawn, ChildProcessWithoutNullStreams } from "child_process";
import fs from "fs";
import path from "path";
import { app } from "electron";
import { appendLog } from "./logger";

type Pending = {
  resolve: (value: unknown) => void;
  reject: (reason?: unknown) => void;
};

export class SidecarClient {
  private proc: ChildProcessWithoutNullStreams | null = null;
  private pending = new Map<string, Pending>();
  private buffer = "";
  private restartCount = 0;
  private lastRestart = 0;
  private dataDir = "";
  private appRoot = "";

  start(dataDir: string): void {
    this.dataDir = dataDir;
    this.appRoot = app.isPackaged
      ? process.resourcesPath
      : path.resolve(app.getAppPath());
    this.spawnProcess();
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

  private spawnProcess(): void {
    const exe = this.sidecarPath();
    appendLog(`Starting sidecar: ${exe}`);

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
      this.rejectAll(new Error("Sidecar stopped"));
      this.maybeRestart();
    });

    this.proc.on("error", (err) => {
      appendLog(`Sidecar error: ${err.message}`);
    });
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
    setTimeout(() => this.spawnProcess(), 1000);
  }

  private rejectAll(reason: Error): void {
    for (const [, pending] of this.pending) {
      pending.reject(reason);
    }
    this.pending.clear();
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
        const msg = JSON.parse(trimmed) as {
          id?: string;
          ok?: boolean;
          data?: unknown;
          error?: string;
        };
        if (!msg.id) {
          continue;
        }
        const pending = this.pending.get(msg.id);
        if (!pending) {
          continue;
        }
        this.pending.delete(msg.id);
        if (msg.ok) {
          pending.resolve(msg.data ?? {});
        } else {
          appendLog(`Sidecar error response: ${msg.error ?? "unknown"}`);
          pending.reject(new Error(msg.error ?? "Something didn't work."));
        }
      } catch {
        appendLog(`Invalid sidecar JSON: ${trimmed}`);
      }
    }
  }

  request(cmd: string, params: Record<string, unknown> = {}): Promise<unknown> {
    if (!this.proc?.stdin.writable) {
      return Promise.reject(new Error("Sidecar is not ready."));
    }
    const id = crypto.randomUUID();
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      const payload = JSON.stringify({ id, cmd, params }) + "\n";
      this.proc!.stdin.write(payload, (err) => {
        if (err) {
          this.pending.delete(id);
          appendLog(`Sidecar write failed: ${err.message}`);
          reject(err);
        }
      });
    });
  }

  stop(): void {
    this.proc?.kill();
    this.proc = null;
  }
}

import fs from "fs";
import path from "path";
import { app } from "electron";

let logPath = "";

export function initLogger(dataDir: string): void {
  const logsDir = path.join(dataDir, "logs");
  fs.mkdirSync(logsDir, { recursive: true });
  logPath = path.join(logsDir, "shield.log");
}

export function appendLog(message: string): void {
  if (!logPath) {
    return;
  }
  const line = `[${new Date().toISOString()}] [ELECTRON] ${message}\n`;
  fs.appendFileSync(logPath, line, "utf8");
}

export function openLogInNotepad(): void {
  if (!logPath || !fs.existsSync(logPath)) {
    appendLog("Log file not found when user requested View Log");
    return;
  }
  const { spawn } = require("child_process") as typeof import("child_process");
  spawn("notepad.exe", [logPath], { detached: true, stdio: "ignore" }).unref();
}

export function getLogPath(): string {
  return logPath;
}

export function getDataDir(): string {
  return path.join(app.getPath("userData"), "SentinelShield");
}

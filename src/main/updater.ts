import { BrowserWindow } from "electron";
import { autoUpdater } from "electron-updater";
import { appendLog } from "./logger";

export type UpdateStatus =
  | { state: "idle" }
  | { state: "checking" }
  | { state: "downloading"; percent: number }
  | { state: "ready"; version: string }
  | { state: "error" };

let status: UpdateStatus = { state: "idle" };
let getMainWindow: () => BrowserWindow | null = () => null;

function sendStatus(): void {
  const win = getMainWindow();
  if (win && !win.isDestroyed()) {
    win.webContents.send("shield:update", status);
  }
}

export function getUpdateStatus(): UpdateStatus {
  return status;
}

export function restartToUpdate(): void {
  appendLog("User chose to restart and install update");
  autoUpdater.quitAndInstall(false, true);
}

export function initAutoUpdater(windowGetter: () => BrowserWindow | null): void {
  getMainWindow = windowGetter;

  if (process.env.NODE_ENV === "development") {
    appendLog("Auto-updater disabled in development");
    return;
  }

  autoUpdater.autoDownload = true;
  autoUpdater.autoInstallOnAppQuit = true;
  autoUpdater.allowDowngrade = false;

  autoUpdater.on("error", (error) => {
    appendLog(`Updater error: ${error.message}`);
    status = { state: "error" };
    sendStatus();
  });

  autoUpdater.on("checking-for-update", () => {
    status = { state: "checking" };
    sendStatus();
  });

  autoUpdater.on("update-available", (info) => {
    appendLog(`Update available: ${info.version}`);
    status = { state: "downloading", percent: 0 };
    sendStatus();
  });

  autoUpdater.on("update-not-available", () => {
    status = { state: "idle" };
    sendStatus();
  });

  autoUpdater.on("download-progress", (progress) => {
    status = { state: "downloading", percent: progress.percent };
    sendStatus();
  });

  autoUpdater.on("update-downloaded", (info) => {
    appendLog(`Update downloaded: ${info.version}`);
    status = { state: "ready", version: info.version };
    sendStatus();
  });

  setTimeout(() => {
    appendLog("Checking for app updates…");
    void autoUpdater.checkForUpdates().catch((error) => {
      appendLog(`Update check failed: ${String(error)}`);
    });
  }, 5000);
}

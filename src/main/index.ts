import { app, BrowserWindow, ipcMain } from "electron";
import path from "path";
import { SidecarClient } from "./sidecar";
import { appendLog, getDataDir, initLogger, openLogInNotepad } from "./logger";

const sidecar = new SidecarClient();
let mainWindow: BrowserWindow | null = null;

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 780,
    minWidth: 900,
    minHeight: 650,
    backgroundColor: "#141414",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
    autoHideMenuBar: true,
    title: "Sentinel Shield",
  });

  if (process.env.NODE_ENV === "development") {
    mainWindow.loadURL("http://localhost:5173");
  } else {
    mainWindow.loadFile(path.join(__dirname, "../renderer/index.html"));
  }

  mainWindow.on("closed", () => {
    mainWindow = null;
  });
}

app.whenReady().then(() => {
  const dataDir = getDataDir();
  initLogger(dataDir);
  appendLog("Sentinel Shield starting");
  sidecar.start(dataDir);
  createWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on("window-all-closed", () => {
  sidecar.stop();
  if (process.platform !== "darwin") {
    app.quit();
  }
});

ipcMain.handle(
  "shield:request",
  async (event, cmd: string, params: Record<string, unknown>) => {
    try {
      const onProgress =
        cmd === "scan"
          ? (progress: unknown) => {
              event.sender.send("shield:progress", progress);
            }
          : undefined;
      return await sidecar.request(cmd, params, onProgress);
    } catch (error) {
      appendLog(`IPC request failed (${cmd}): ${String(error)}`);
      throw error;
    }
  }
);

ipcMain.handle("shield:isAdmin", async () => {
  try {
    const result = (await sidecar.request("is_admin")) as { is_admin?: boolean };
    return Boolean(result.is_admin);
  } catch {
    return false;
  }
});

ipcMain.handle("shield:openLog", () => {
  openLogInNotepad();
});

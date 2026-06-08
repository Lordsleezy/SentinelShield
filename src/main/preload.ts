import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("shield", {
  request: (cmd: string, params?: Record<string, unknown>) =>
    ipcRenderer.invoke("shield:request", cmd, params ?? {}),
  isAdmin: () => ipcRenderer.invoke("shield:isAdmin") as Promise<boolean>,
  openLog: () => ipcRenderer.invoke("shield:openLog") as Promise<void>,
});

export {};

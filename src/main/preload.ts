import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("shield", {
  request: (cmd: string, params?: Record<string, unknown>) =>
    ipcRenderer.invoke("shield:request", cmd, params ?? {}),
  isAdmin: () => ipcRenderer.invoke("shield:isAdmin") as Promise<boolean>,
  openLog: () => ipcRenderer.invoke("shield:openLog") as Promise<void>,
  openSentinelCare: () => ipcRenderer.invoke("shield:openSentinelCare") as Promise<void>,
  onProgress: (callback: (data: unknown) => void) => {
    const handler = (_event: unknown, data: unknown) => callback(data);
    ipcRenderer.on("shield:progress", handler);
    return () => {
      ipcRenderer.removeListener("shield:progress", handler);
    };
  },
  onEvent: (callback: (payload: { event: string; data: unknown }) => void) => {
    const handler = (_event: unknown, payload: { event: string; data: unknown }) =>
      callback(payload);
    ipcRenderer.on("shield:event", handler);
    return () => {
      ipcRenderer.removeListener("shield:event", handler);
    };
  },
});

export {};

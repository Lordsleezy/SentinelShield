import { contextBridge, ipcRenderer } from "electron";

contextBridge.exposeInMainWorld("shield", {
  request: (cmd: string, params?: Record<string, unknown>) =>
    ipcRenderer.invoke("shield:request", cmd, params ?? {}),
  isAdmin: () => ipcRenderer.invoke("shield:isAdmin") as Promise<boolean>,
  openLog: () => ipcRenderer.invoke("shield:openLog") as Promise<void>,
  openSentinelCare: () => ipcRenderer.invoke("shield:openSentinelCare") as Promise<void>,
  openSentinelMarket: () => ipcRenderer.invoke("shield:openSentinelMarket") as Promise<void>,
  getSidecarStatus: () =>
    ipcRenderer.invoke("shield:getSidecarStatus") as Promise<{
      alive: boolean;
      ready: boolean;
      lastPingMs: number | null;
      restartCount: number;
    }>,
  onSidecarStatus: (callback: (status: unknown) => void) => {
    const handler = (_event: unknown, status: unknown) => callback(status);
    ipcRenderer.on("shield:sidecarStatus", handler);
    return () => {
      ipcRenderer.removeListener("shield:sidecarStatus", handler);
    };
  },
  getUpdateStatus: () =>
    ipcRenderer.invoke("shield:getUpdateStatus") as Promise<{
      state: "idle" | "checking" | "downloading" | "ready" | "error";
      percent?: number;
      version?: string;
    }>,
  restartToUpdate: () => ipcRenderer.invoke("shield:restartToUpdate") as Promise<void>,
  onUpdate: (callback: (status: unknown) => void) => {
    const handler = (_event: unknown, status: unknown) => callback(status);
    ipcRenderer.on("shield:update", handler);
    return () => {
      ipcRenderer.removeListener("shield:update", handler);
    };
  },
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

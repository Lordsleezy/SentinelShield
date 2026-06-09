import type { ScanProgress, ShieldEvent } from "./api";

export {};

declare global {
  interface Window {
    shield: {
      request: (cmd: string, params?: Record<string, unknown>) => Promise<unknown>;
      isAdmin: () => Promise<boolean>;
      openLog: () => Promise<void>;
      openSentinelCare: () => Promise<void>;
      getUpdateStatus: () => Promise<import("./api").UpdateStatus>;
      restartToUpdate: () => Promise<void>;
      onUpdate: (callback: (status: import("./api").UpdateStatus) => void) => () => void;
      onProgress: (callback: (data: ScanProgress) => void) => () => void;
      onEvent: (callback: (payload: ShieldEvent) => void) => () => void;
    };
  }
}

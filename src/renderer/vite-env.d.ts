import type { ScanProgress } from "./api";

export {};

declare global {
  interface Window {
    shield: {
      request: (cmd: string, params?: Record<string, unknown>) => Promise<unknown>;
      isAdmin: () => Promise<boolean>;
      openLog: () => Promise<void>;
      onProgress: (callback: (data: ScanProgress) => void) => () => void;
    };
  }
}

const GENERIC_ERROR = "Something didn't work. No changes were made.";

export type ScanProgress = {
  current_file: string;
  files_scanned: number;
  files_total: number;
  eta_seconds: number;
};

export type ShieldEvent = {
  event: string;
  data: Record<string, unknown>;
};

export async function shieldRequest<T>(
  cmd: string,
  params: Record<string, unknown> = {},
  onProgress?: (progress: ScanProgress) => void
): Promise<T> {
  let unsubscribe: (() => void) | undefined;
  if (onProgress && cmd === "scan") {
    unsubscribe = window.shield.onProgress((data) => onProgress(data as ScanProgress));
  }
  try {
    return (await window.shield.request(cmd, params)) as T;
  } catch {
    throw new Error(GENERIC_ERROR);
  } finally {
    unsubscribe?.();
  }
}

export function subscribeEvents(
  callback: (payload: ShieldEvent) => void
): () => void {
  return window.shield.onEvent(callback);
}

export async function checkAdmin(): Promise<boolean> {
  try {
    return await window.shield.isAdmin();
  } catch {
    return false;
  }
}

export function openLog(): void {
  void window.shield.openLog();
}

export function openSentinelCare(): void {
  void window.shield.openSentinelCare();
}

export type UpdateStatus =
  | { state: "idle" }
  | { state: "checking" }
  | { state: "downloading"; percent: number }
  | { state: "ready"; version: string }
  | { state: "error" };

export async function getUpdateStatus(): Promise<UpdateStatus> {
  return (await window.shield.getUpdateStatus()) as UpdateStatus;
}

export function restartToUpdate(): void {
  void window.shield.restartToUpdate();
}

export function subscribeUpdate(callback: (status: UpdateStatus) => void): () => void {
  return window.shield.onUpdate((status) => callback(status as UpdateStatus));
}

export { GENERIC_ERROR };

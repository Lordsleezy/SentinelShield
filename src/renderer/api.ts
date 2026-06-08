const GENERIC_ERROR = "Something didn't work. No changes were made.";

export type ScanProgress = {
  current_file: string;
  files_scanned: number;
  files_total: number;
  eta_seconds: number;
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

export { GENERIC_ERROR };

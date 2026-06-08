const GENERIC_ERROR = "Something didn't work. No changes were made.";

export async function shieldRequest<T>(
  cmd: string,
  params: Record<string, unknown> = {}
): Promise<T> {
  try {
    return (await window.shield.request(cmd, params)) as T;
  } catch {
    throw new Error(GENERIC_ERROR);
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

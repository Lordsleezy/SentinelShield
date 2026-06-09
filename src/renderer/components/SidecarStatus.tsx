import { useEffect, useState } from "react";
import { getSidecarStatus, subscribeSidecarStatus, type SidecarStatusInfo } from "../api";

function label(status: SidecarStatusInfo): string {
  if (!status.alive) return "Protection engine offline";
  if (!status.ready) return "Protection engine starting…";
  if (status.lastPingMs !== null && status.lastPingMs > 2000) {
    return `Protection engine slow (${status.lastPingMs}ms)`;
  }
  return "Protection engine ready";
}

export function SidecarStatusIndicator() {
  const [status, setStatus] = useState<SidecarStatusInfo>({
    alive: false,
    ready: false,
    lastPingMs: null,
    restartCount: 0,
  });

  useEffect(() => {
    getSidecarStatus().then(setStatus).catch(() => undefined);
    return subscribeSidecarStatus(setStatus);
  }, []);

  const tone = !status.alive || !status.ready ? "warn" : "ok";

  return (
    <div className={`sidecar-status sidecar-status-${tone}`} role="status" title={label(status)}>
      <span className="sidecar-status-dot" aria-hidden="true" />
      <span>{label(status)}</span>
    </div>
  );
}

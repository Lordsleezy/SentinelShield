import { useEffect, useState } from "react";
import { getUpdateStatus, restartToUpdate, subscribeUpdate, type UpdateStatus } from "../api";

export function UpdateBanner() {
  const [status, setStatus] = useState<UpdateStatus>({ state: "idle" });
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    getUpdateStatus().then(setStatus).catch(() => undefined);
    return subscribeUpdate(setStatus);
  }, []);

  if (dismissed || status.state !== "ready") {
    return null;
  }

  return (
    <div className="update-banner" role="status">
      <span>
        Update available — restart to install
        {status.version ? ` (v${status.version})` : ""}
      </span>
      <div className="update-banner-actions">
        <button type="button" className="update-restart-btn" onClick={restartToUpdate}>
          Restart now
        </button>
        <button type="button" className="banner-dismiss" onClick={() => setDismissed(true)}>
          Later
        </button>
      </div>
    </div>
  );
}

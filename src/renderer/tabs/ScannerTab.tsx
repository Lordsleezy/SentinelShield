import { useState } from "react";
import { GENERIC_ERROR, openLog, shieldRequest, type ScanProgress } from "../api";

type ScanItem = {
  path: string;
  friendly_name: string;
  reason: string;
  recommendation: string;
};

type ScanResult = {
  message: string;
  threat_count: number;
  items: ScanItem[];
};

function formatEta(seconds: number): string {
  if (seconds <= 0) {
    return "Almost done";
  }
  if (seconds < 60) {
    return `About ${seconds} seconds left`;
  }
  const minutes = Math.ceil(seconds / 60);
  return `About ${minutes} minute${minutes === 1 ? "" : "s"} left`;
}

export function ScannerTab() {
  const [working, setWorking] = useState(false);
  const [status, setStatus] = useState("Tap the button when you're ready to scan.");
  const [result, setResult] = useState<ScanResult | null>(null);
  const [showDetails, setShowDetails] = useState(false);
  const [failed, setFailed] = useState(false);
  const [quarantinedPaths, setQuarantinedPaths] = useState<Set<string>>(new Set());
  const [quarantiningPath, setQuarantiningPath] = useState<string | null>(null);
  const [progress, setProgress] = useState<ScanProgress | null>(null);

  async function runScan() {
    setWorking(true);
    setFailed(false);
    setResult(null);
    setShowDetails(false);
    setQuarantinedPaths(new Set());
    setProgress(null);
    setStatus("Working...");

    try {
      const data = await shieldRequest<ScanResult>(
        "scan",
        {},
        (update) => setProgress(update)
      );
      setResult(data);
      setStatus(data.message);
      if (data.items.length > 0) {
        setShowDetails(true);
      }
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
      setProgress(null);
    }
  }

  async function quarantineItem(item: ScanItem) {
    setQuarantiningPath(item.path);
    setFailed(false);
    try {
      await shieldRequest<{ message: string }>("quarantine", { path: item.path });
      setQuarantinedPaths((prev) => new Set(prev).add(item.path));
      setStatus(`Moved ${item.friendly_name} to quarantine.`);
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setQuarantiningPath(null);
    }
  }

  const progressPct =
    progress && progress.files_total > 0
      ? Math.min(100, Math.round((progress.files_scanned / progress.files_total) * 100))
      : 0;

  return (
    <section className="tab-panel" aria-label="Scanner">
      <h2>Virus Scanner</h2>
      <p className="tab-desc">
        We'll check your Downloads, Desktop, Documents, and temporary folders for anything suspicious.
        Nothing is moved until you review the results and tap Quarantine on a specific file.
      </p>

      <button
        type="button"
        className="primary-btn"
        disabled={working}
        onClick={runScan}
      >
        Scan My Computer
      </button>

      {working && (
        <div className="scan-progress" aria-live="polite">
          <div className="working">
            <div className="spinner" aria-hidden="true" />
            <span>Scanning...</span>
          </div>
          {progress && (
            <>
              <div
                className="progress-bar"
                role="progressbar"
                aria-valuenow={progressPct}
                aria-valuemin={0}
                aria-valuemax={100}
              >
                <div className="progress-fill" style={{ width: `${progressPct}%` }} />
              </div>
              <p className="progress-stats">
                {progress.files_scanned.toLocaleString()} of{" "}
                {progress.files_total.toLocaleString()} files scanned
              </p>
              <p className="progress-file">
                Current: <span>{progress.current_file}</span>
              </p>
              <p className="progress-eta">{formatEta(progress.eta_seconds)}</p>
            </>
          )}
        </div>
      )}

      {!working && (
        <p className="status-line" aria-live="polite">{status}</p>
      )}

      {failed && (
        <div className="error-actions">
          <button type="button" className="link-btn" onClick={openLog}>
            View Log
          </button>
        </div>
      )}

      {result && result.items.length > 0 && (
        <div className="result-card">
          <p>{result.message}</p>
          <button
            type="button"
            className="details-toggle"
            onClick={() => setShowDetails((v) => !v)}
          >
            {showDetails ? "Hide details" : "See what we found"}
          </button>
          {showDetails && (
            <div className="details-list">
              {result.items.map((item) => {
                const done = quarantinedPaths.has(item.path);
                const busy = quarantiningPath === item.path;
                return (
                  <div className="detail-item scan-item" key={item.path}>
                    <strong>{item.friendly_name}</strong>
                    <span>{item.reason}</span>
                    <span>{item.recommendation}</span>
                    {done ? (
                      <span className="quarantine-done">Moved to quarantine</span>
                    ) : (
                      <button
                        type="button"
                        className="secondary-btn quarantine-btn"
                        disabled={busy || working}
                        onClick={() => quarantineItem(item)}
                      >
                        {busy ? "Moving..." : "Quarantine This File"}
                      </button>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}
    </section>
  );
}

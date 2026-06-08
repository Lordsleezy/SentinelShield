import { useEffect, useState } from "react";
import { GENERIC_ERROR, openLog, shieldRequest, subscribeEvents } from "../api";

type ThreatRecord = {
  id: string;
  timestamp: string;
  source: string;
  path: string;
  friendly_name: string;
  reason: string;
  action: string;
};

export function HistoryTab() {
  const [working, setWorking] = useState(false);
  const [failed, setFailed] = useState(false);
  const [status, setStatus] = useState("Loading threat history...");
  const [records, setRecords] = useState<ThreatRecord[]>([]);

  useEffect(() => {
    loadHistory();
    const unsub = subscribeEvents(({ event }) => {
      if (event === "threat_detected" || event === "scheduled_scan_complete") {
        void loadHistory();
      }
    });
    return unsub;
  }, []);

  async function loadHistory() {
    setWorking(true);
    setFailed(false);
    try {
      const data = await shieldRequest<{ records: ThreatRecord[]; count: number }>(
        "threat_history_list",
        { limit: 200 }
      );
      setRecords(data.records);
      setStatus(
        data.count === 0
          ? "No threats recorded yet."
          : `Showing ${data.count} recorded detection(s).`
      );
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  async function clearHistory() {
    setWorking(true);
    setFailed(false);
    try {
      const data = await shieldRequest<{ message: string }>("threat_history_clear");
      setRecords([]);
      setStatus(data.message);
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  function formatSource(source: string): string {
    switch (source) {
      case "realtime": return "Real-time protection";
      case "scheduled": return "Scheduled scan";
      case "manual": return "Manual scan";
      default: return source;
    }
  }

  return (
    <section className="tab-panel" aria-label="Threat History">
      <h2>Threat History</h2>
      <p className="tab-desc">
        A permanent log of everything we've detected — from real-time alerts, scheduled scans, and manual scans.
      </p>

      <div className="button-row">
        <button type="button" className="secondary-btn" disabled={working} onClick={loadHistory}>
          Refresh
        </button>
        <button type="button" className="secondary-btn" disabled={working || records.length === 0} onClick={clearHistory}>
          Clear History
        </button>
      </div>

      {working ? (
        <div className="working" aria-live="polite">
          <div className="spinner" aria-hidden="true" />
          <span>Working...</span>
        </div>
      ) : (
        <p className="status-line" aria-live="polite">{status}</p>
      )}

      {failed && (
        <div className="error-actions">
          <button type="button" className="link-btn" onClick={openLog}>View Log</button>
        </div>
      )}

      {records.length > 0 && (
        <div className="details-list history-list">
          {records.map((record) => (
            <div className="detail-item history-item" key={record.id}>
              <strong>{record.friendly_name}</strong>
              <span>{record.reason}</span>
              <span>{formatSource(record.source)} — {record.action}</span>
              <span className="history-time">{record.timestamp}</span>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

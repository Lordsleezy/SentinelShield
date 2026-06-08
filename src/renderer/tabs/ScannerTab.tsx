import { useState } from "react";
import { GENERIC_ERROR, openLog, shieldRequest } from "../api";

type ScanItem = {
  friendly_name: string;
  reason: string;
  recommendation: string;
};

type ScanResult = {
  message: string;
  threat_count: number;
  items: ScanItem[];
};

export function ScannerTab() {
  const [working, setWorking] = useState(false);
  const [status, setStatus] = useState("Tap the button when you're ready to scan.");
  const [result, setResult] = useState<ScanResult | null>(null);
  const [showDetails, setShowDetails] = useState(false);
  const [failed, setFailed] = useState(false);

  async function runScan() {
    setWorking(true);
    setFailed(false);
    setResult(null);
    setShowDetails(false);
    setStatus("Working...");

    try {
      const data = await shieldRequest<ScanResult>("scan");
      setResult(data);
      setStatus(data.message);
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  return (
    <section className="tab-panel" aria-label="Scanner">
      <h2>Virus Scanner</h2>
      <p className="tab-desc">
        We'll check your Downloads, Desktop, Documents, and temporary folders for anything suspicious.
      </p>

      <button
        type="button"
        className="primary-btn"
        disabled={working}
        onClick={runScan}
      >
        Scan My Computer
      </button>

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
              {result.items.map((item) => (
                <div className="detail-item" key={item.friendly_name + item.reason}>
                  <strong>{item.friendly_name}</strong>
                  <span>{item.reason}</span>
                  <span>{item.recommendation}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </section>
  );
}

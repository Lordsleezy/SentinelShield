import { useState } from "react";
import { GENERIC_ERROR, openLog, shieldRequest } from "../api";

type NetworkDevice = {
  ip: string;
  mac: string;
  label: string;
  known: boolean;
  flags: string[];
};

type TrafficWarning = {
  description: string;
  severity: string;
};

type NetworkResult = {
  message: string;
  ssid: string;
  local_ip: string;
  devices: NetworkDevice[];
  rogue_count: number;
  traffic_warnings: TrafficWarning[];
};

export function NetworkTab() {
  const [working, setWorking] = useState(false);
  const [failed, setFailed] = useState(false);
  const [status, setStatus] = useState("Tap the button to check devices on your Wi-Fi.");
  const [result, setResult] = useState<NetworkResult | null>(null);
  const [showDetails, setShowDetails] = useState(false);

  async function runScan() {
    setWorking(true);
    setFailed(false);
    setResult(null);
    setStatus("Working...");

    try {
      const data = await shieldRequest<NetworkResult>("network_scan");
      setResult(data);
      setStatus(data.message);
      setShowDetails(true);
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  return (
    <section className="tab-panel" aria-label="Network">
      <h2>Network Scanner</h2>
      <p className="tab-desc">
        We'll check devices on your Wi-Fi and look for suspicious network activity. This works best when you're connected to Wi-Fi.
      </p>

      <button type="button" className="primary-btn" disabled={working} onClick={runScan}>
        Scan My Network
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
          <button type="button" className="link-btn" onClick={openLog}>View Log</button>
        </div>
      )}

      {result && (
        <div className="result-card">
          <p><strong>Wi-Fi:</strong> {result.ssid}</p>
          <p><strong>Your IP:</strong> {result.local_ip}</p>
          <p>{result.message}</p>
          <button
            type="button"
            className="details-toggle"
            onClick={() => setShowDetails((v) => !v)}
          >
            {showDetails ? "Hide details" : "See devices and traffic"}
          </button>
          {showDetails && (
            <div className="details-list">
              {result.devices.map((device) => (
                <div className="detail-item" key={device.ip + device.mac}>
                  <strong>{device.label}</strong>
                  <span>{device.ip} — {device.mac}</span>
                  {!device.known && device.flags.map((f) => <span key={f}>{f}</span>)}
                </div>
              ))}
              {result.traffic_warnings.map((w) => (
                <div className="detail-item" key={w.description}>
                  <strong>Traffic warning</strong>
                  <span>{w.description}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </section>
  );
}

import { useState } from "react";
import { EscalateCareButton } from "./components/EscalateCareButton";
import { GENERIC_ERROR, shieldRequest, type ScanProgress } from "./api";

type ScanResult = {
  message: string;
  threat_count: number;
};

export function SeniorMode({ onSwitchToStandard }: { onSwitchToStandard: () => void }) {
  const [working, setWorking] = useState(false);
  const [status, setStatus] = useState("Tap the big button when you're ready.");
  const [threatCount, setThreatCount] = useState(0);
  const [failed, setFailed] = useState(false);

  async function runScan() {
    setWorking(true);
    setFailed(false);
    setThreatCount(0);
    setStatus("We're checking your computer now. This may take a minute.");

    try {
      const data = await shieldRequest<ScanResult>(
        "scan",
        {},
        (progress: ScanProgress) => {
          setStatus(`Checking file ${progress.files_scanned} of ${progress.files_total}...`);
        }
      );
      setThreatCount(data.threat_count);
      setStatus(data.message);
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  return (
    <div className="senior-mode">
      <header className="senior-header">
        <h1>Sentinel Shield</h1>
        <p>We keep your computer safe.</p>
        <button type="button" className="senior-switch" onClick={onSwitchToStandard}>
          Switch to full mode
        </button>
      </header>

      <main className="senior-main">
        <button
          type="button"
          className="senior-scan-btn"
          disabled={working}
          onClick={runScan}
        >
          {working ? "Scanning..." : "Scan Now"}
        </button>

        <p className="senior-status" aria-live="polite">{status}</p>

        {(failed || threatCount > 0) && (
          <div className="senior-help">
            <p>
              {failed
                ? "We couldn't fix this on our own. Our care team can help."
                : "We found something we can't remove automatically. Our care team can help."}
            </p>
            <EscalateCareButton className="senior-care-btn" />
          </div>
        )}
      </main>
    </div>
  );
}

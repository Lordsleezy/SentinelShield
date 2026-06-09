import { useEffect, useState } from "react";
import { ShopMarketButton } from "../components/ShopMarketButton";
import { GENERIC_ERROR, openLog, shieldRequest } from "../api";

type MemoryStatus = {
  status_line: string;
  used_friendly: string;
  free_friendly: string;
  total_friendly: string;
  recommend_hardware_upgrade?: boolean;
  hardware_message?: string | null;
};

type MemoryFreeResult = {
  message: string;
  before_pct: number;
  after_pct: number;
  freed_friendly: string;
  recommend_hardware_upgrade?: boolean;
  hardware_message?: string | null;
};

export function MemoryTab() {
  const [working, setWorking] = useState(false);
  const [status, setStatus] = useState("Checking your memory...");
  const [result, setResult] = useState<MemoryFreeResult | null>(null);
  const [failed, setFailed] = useState(false);
  const [showMarket, setShowMarket] = useState(false);
  const [hardwareMessage, setHardwareMessage] = useState<string | null>(null);

  useEffect(() => {
    shieldRequest<MemoryStatus>("memory_status")
      .then((data) => {
        setStatus(data.status_line);
        setShowMarket(Boolean(data.recommend_hardware_upgrade));
        setHardwareMessage(data.hardware_message ?? null);
      })
      .catch(() => setStatus("Ready when you are."));
  }, []);

  async function freeMemory() {
    setWorking(true);
    setFailed(false);
    setResult(null);
    setStatus("Working...");

    try {
      const data = await shieldRequest<MemoryFreeResult>("memory_free");
      setResult(data);
      setStatus(data.message);
      setShowMarket(Boolean(data.recommend_hardware_upgrade));
      setHardwareMessage(data.hardware_message ?? null);
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  return (
    <section className="tab-panel" aria-label="Memory">
      <h2>Memory Optimizer</h2>
      <p className="tab-desc">
        Free up memory so your programs run more smoothly. One tap — no charts, no numbers to worry about.
      </p>

      <button type="button" className="primary-btn" disabled={working} onClick={freeMemory}>
        Free Up Memory
      </button>

      {working ? (
        <div className="working" aria-live="polite">
          <div className="spinner" aria-hidden="true" />
          <span>Working...</span>
        </div>
      ) : (
        <p className="status-line" aria-live="polite">{status}</p>
      )}

      {showMarket && (
        <div className="hardware-card">
          <p>{hardwareMessage ?? "A hardware upgrade or replacement may help your computer run better."}</p>
          <ShopMarketButton />
        </div>
      )}

      {failed && (
        <div className="error-actions">
          <button type="button" className="link-btn" onClick={openLog}>
            View Log
          </button>
        </div>
      )}

      {result && (
        <div className="result-card">
          <p>{result.message}</p>
        </div>
      )}
    </section>
  );
}

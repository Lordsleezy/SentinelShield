import { useEffect, useState } from "react";
import { checkAdmin, subscribeEvents } from "./api";
import { EscalateCareButton } from "./components/EscalateCareButton";
import { SidecarStatusIndicator } from "./components/SidecarStatus";
import { UpdateBanner } from "./components/UpdateBanner";
import { SeniorMode } from "./SeniorMode";
import { ScannerTab } from "./tabs/ScannerTab";
import { ProtectionTab } from "./tabs/ProtectionTab";
import { NetworkTab } from "./tabs/NetworkTab";
import { HistoryTab } from "./tabs/HistoryTab";
import { CleanerTab } from "./tabs/CleanerTab";
import { MemoryTab } from "./tabs/MemoryTab";
import { OptimizerTab } from "./tabs/OptimizerTab";

type Tab = "scanner" | "protection" | "network" | "history" | "cleaner" | "memory" | "optimizer";

const tabs: { id: Tab; label: string }[] = [
  { id: "scanner", label: "Scanner" },
  { id: "protection", label: "Protection" },
  { id: "network", label: "Network" },
  { id: "history", label: "History" },
  { id: "cleaner", label: "Cleaner" },
  { id: "memory", label: "Memory" },
  { id: "optimizer", label: "Optimizer" },
];

function loadSeniorMode(): boolean {
  try {
    return localStorage.getItem("seniorMode") === "true";
  } catch {
    return false;
  }
}

export function App() {
  const [seniorMode, setSeniorMode] = useState(loadSeniorMode);
  const [tab, setTab] = useState<Tab>("scanner");
  const [isAdmin, setIsAdmin] = useState(true);
  const [bannerDismissed, setBannerDismissed] = useState(false);
  const [globalAlert, setGlobalAlert] = useState<string | null>(null);
  const [showCareEscalation, setShowCareEscalation] = useState(false);

  useEffect(() => {
    checkAdmin().then(setIsAdmin).catch(() => setIsAdmin(false));
  }, []);

  useEffect(() => {
    try {
      localStorage.setItem("seniorMode", String(seniorMode));
    } catch {
      /* ignore */
    }
    document.documentElement.classList.toggle("senior-mode-active", seniorMode);
  }, [seniorMode]);

  useEffect(() => {
    const unsub = subscribeEvents(({ event, data }) => {
      if (event === "threat_detected") {
        setGlobalAlert(String(data.message ?? "We detected something suspicious."));
        setShowCareEscalation(true);
      }
    });
    return unsub;
  }, []);

  if (seniorMode) {
    return <SeniorMode onSwitchToStandard={() => setSeniorMode(false)} />;
  }

  return (
    <div className="app">
      <header className="header">
        <div>
          <h1>Sentinel Shield</h1>
          <p className="tagline">We keep your computer safe and tidy.</p>
        </div>
        <div className="header-actions">
          <SidecarStatusIndicator />
          <button
            type="button"
            className="senior-toggle"
            onClick={() => setSeniorMode(true)}
          >
            Simple mode
          </button>
        </div>
      </header>

      <UpdateBanner />

      {globalAlert && (
        <div className="threat-banner" role="alert">
          <div className="threat-banner-content">
            <span>{globalAlert}</span>
            {showCareEscalation && <EscalateCareButton />}
          </div>
          <button type="button" className="banner-dismiss" onClick={() => setGlobalAlert(null)}>
            Dismiss
          </button>
        </div>
      )}

      {!isAdmin && !bannerDismissed && (
        <div className="admin-banner" role="status">
          <span>
            Some features need admin access. Restart as Administrator to unlock them.
          </span>
          <button type="button" className="banner-dismiss" onClick={() => setBannerDismissed(true)}>
            Dismiss
          </button>
        </div>
      )}

      <nav className="tabs" role="tablist" aria-label="Main sections">
        {tabs.map((t) => (
          <button
            key={t.id}
            role="tab"
            aria-selected={tab === t.id}
            className={tab === t.id ? "tab active" : "tab"}
            onClick={() => setTab(t.id)}
          >
            {t.label}
          </button>
        ))}
      </nav>

      <main className="content">
        {tab === "scanner" && <ScannerTab />}
        {tab === "protection" && <ProtectionTab />}
        {tab === "network" && <NetworkTab />}
        {tab === "history" && <HistoryTab />}
        {tab === "cleaner" && <CleanerTab isAdmin={isAdmin} />}
        {tab === "memory" && <MemoryTab />}
        {tab === "optimizer" && <OptimizerTab isAdmin={isAdmin} />}
      </main>
    </div>
  );
}

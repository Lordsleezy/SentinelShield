import { useEffect, useState } from "react";
import { checkAdmin } from "./api";
import { ScannerTab } from "./tabs/ScannerTab";
import { CleanerTab } from "./tabs/CleanerTab";
import { MemoryTab } from "./tabs/MemoryTab";
import { OptimizerTab } from "./tabs/OptimizerTab";

type Tab = "scanner" | "cleaner" | "memory" | "optimizer";

const tabs: { id: Tab; label: string }[] = [
  { id: "scanner", label: "Scanner" },
  { id: "cleaner", label: "Cleaner" },
  { id: "memory", label: "Memory" },
  { id: "optimizer", label: "Optimizer" },
];

export function App() {
  const [tab, setTab] = useState<Tab>("scanner");
  const [isAdmin, setIsAdmin] = useState(true);
  const [bannerDismissed, setBannerDismissed] = useState(false);

  useEffect(() => {
    checkAdmin().then(setIsAdmin).catch(() => setIsAdmin(false));
  }, []);

  return (
    <div className="app">
      <header className="header">
        <div>
          <h1>Sentinel Shield</h1>
          <p className="tagline">We keep your computer safe and tidy.</p>
        </div>
      </header>

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
        {tab === "cleaner" && <CleanerTab isAdmin={isAdmin} />}
        {tab === "memory" && <MemoryTab />}
        {tab === "optimizer" && <OptimizerTab isAdmin={isAdmin} />}
      </main>
    </div>
  );
}

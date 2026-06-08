import { useState } from "react";
import { GENERIC_ERROR, openLog, shieldRequest } from "../api";

type Category = {
  id: string;
  label: string;
  size_friendly: string;
  requires_admin: boolean;
  locked?: boolean;
};

type PreviewResult = {
  categories: Category[];
  total_size_friendly: string;
};

type CleanResult = {
  message: string;
  freed_friendly: string;
  skipped: { label: string; reason: string }[];
  notes?: string[];
};

export function CleanerTab({ isAdmin }: { isAdmin: boolean }) {
  const [working, setWorking] = useState(false);
  const [preview, setPreview] = useState<PreviewResult | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [status, setStatus] = useState("See what we can clean before removing anything.");
  const [result, setResult] = useState<CleanResult | null>(null);
  const [failed, setFailed] = useState(false);
  const [showDetails, setShowDetails] = useState(false);

  async function loadPreview() {
    setWorking(true);
    setFailed(false);
    setResult(null);
    setStatus("Working...");

    try {
      const data = await shieldRequest<PreviewResult>("cleaner_preview");
      setPreview(data);
      setSelected(new Set(data.categories.filter((c) => !c.locked).map((c) => c.id)));
      setStatus(`We found ${data.total_size_friendly} of junk you can remove. Choose what to clean.`);
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  async function runClean() {
    if (selected.size === 0) {
      setStatus("Please choose at least one item to clean.");
      return;
    }
    setWorking(true);
    setFailed(false);
    setStatus("Working...");

    try {
      const data = await shieldRequest<CleanResult>("cleaner_run", {
        selected_ids: Array.from(selected),
      });
      setResult(data);
      setStatus(data.message);
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  function toggle(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }

  return (
    <section className="tab-panel" aria-label="Cleaner">
      <h2>Device Cleaner</h2>
      <p className="tab-desc">
        We'll show you what's taking up space first. Nothing is deleted until you tap Clean Now.
      </p>

      {!preview ? (
        <button type="button" className="primary-btn" disabled={working} onClick={loadPreview}>
          See What We Can Clean
        </button>
      ) : (
        <>
          <div className="checklist">
            {preview.categories.map((cat) => (
              <div
                key={cat.id}
                className={cat.locked ? "check-item locked" : "check-item"}
              >
                <input
                  type="checkbox"
                  id={cat.id}
                  checked={selected.has(cat.id)}
                  disabled={cat.locked}
                  onChange={() => toggle(cat.id)}
                />
                <label htmlFor={cat.id}>
                  <span className="label-row">
                    <strong>{cat.label}</strong>
                    {cat.requires_admin && !isAdmin && (
                      <span className="lock-icon" title="Needs admin access">🔒</span>
                    )}
                  </span>
                  <span className="plain size-tag">About {cat.size_friendly}</span>
                </label>
              </div>
            ))}
          </div>
          <button type="button" className="primary-btn" disabled={working} onClick={runClean}>
            Clean Now
          </button>
        </>
      )}

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

      {result && (
        <div className="result-card">
          <p>{result.message}</p>
          {result.notes && result.notes.length > 0 && (
            <ul className="notes-list">
              {result.notes.map((note) => (
                <li key={note}>{note}</li>
              ))}
            </ul>
          )}
          {result.skipped.length > 0 && (
            <>
              <button
                type="button"
                className="details-toggle"
                onClick={() => setShowDetails((v) => !v)}
              >
                {showDetails ? "Hide details" : "See what we changed"}
              </button>
              {showDetails && (
                <div className="details-list">
                  {result.skipped.map((s) => (
                    <div className="detail-item" key={s.label}>
                      <strong>{s.label}</strong>
                      <span>{s.reason}</span>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      )}
    </section>
  );
}

import { useEffect, useState, type Dispatch, type SetStateAction } from "react";
import { GENERIC_ERROR, openLog, shieldRequest } from "../api";

type OptimizerItem = {
  id: string;
  label: string;
  plain: string;
  section: string;
  locked?: boolean;
};

type StartupItem = {
  id: string;
  name: string;
  friendly_name: string;
  path: string;
  source: string;
  recommended_action: string;
};

type TaskItem = {
  id: string;
  name: string;
  friendly_name: string;
  plain_description: string;
};

type UndoChange = {
  change_id: string;
  description: string;
};

type ApplyResult = {
  message: string;
  applied: { label: string }[];
  skipped: { label: string; reason: string }[];
};

const SECTIONS = [
  { id: "bloat", title: "Bloat Remover" },
  { id: "performance", title: "Performance" },
  { id: "startup", title: "Startup" },
  { id: "tasks", title: "Scheduled Tasks" },
] as const;

export function OptimizerTab({ isAdmin }: { isAdmin: boolean }) {
  const [openSection, setOpenSection] = useState<string>("bloat");
  const [working, setWorking] = useState(false);
  const [status, setStatus] = useState("Choose what you'd like to change. Nothing happens until you confirm.");
  const [failed, setFailed] = useState(false);
  const [showDetails, setShowDetails] = useState(false);
  const [lastResult, setLastResult] = useState<ApplyResult | null>(null);

  const [optimizerItems, setOptimizerItems] = useState<OptimizerItem[]>([]);
  const [startupItems, setStartupItems] = useState<StartupItem[]>([]);
  const [taskItems, setTaskItems] = useState<TaskItem[]>([]);
  const [undoChanges, setUndoChanges] = useState<UndoChange[]>([]);

  const [selectedOptimizer, setSelectedOptimizer] = useState<Set<string>>(new Set());
  const [selectedStartup, setSelectedStartup] = useState<Set<string>>(new Set());
  const [selectedTasks, setSelectedTasks] = useState<Set<string>>(new Set());

  useEffect(() => {
    loadAll();
  }, []);

  async function loadAll() {
    try {
      const [opt, startup, tasks, undo] = await Promise.all([
        shieldRequest<{ items: OptimizerItem[] }>("optimizer_list"),
        shieldRequest<{ items: StartupItem[] }>("startup_list"),
        shieldRequest<{ items: TaskItem[] }>("tasks_list"),
        shieldRequest<{ changes: UndoChange[] }>("undo_list"),
      ]);
      setOptimizerItems(opt.items);
      setStartupItems(startup.items);
      setTaskItems(tasks.items);
      setUndoChanges(undo.changes);
    } catch {
      setStatus(GENERIC_ERROR);
      setFailed(true);
    }
  }

  function toggleSet(setter: Dispatch<SetStateAction<Set<string>>>, id: string) {
    setter((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }

  async function applyOptimizer() {
    if (selectedOptimizer.size === 0) {
      setStatus("Please choose at least one item.");
      return;
    }
    setWorking(true);
    setFailed(false);
    setStatus("Working...");
    try {
      const data = await shieldRequest<ApplyResult>("optimizer_apply", {
        selected_ids: Array.from(selectedOptimizer),
      });
      setLastResult(data);
      setStatus(data.message);
      await loadAll();
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  async function disableStartup() {
    const entries = startupItems.filter((i) => selectedStartup.has(i.id));
    if (entries.length === 0) {
      setStatus("Please choose at least one startup item.");
      return;
    }
    setWorking(true);
    setFailed(false);
    setStatus("Working...");
    try {
      const data = await shieldRequest<{ message: string; disabled: { friendly_name: string }[] }>(
        "startup_disable",
        { entries }
      );
      setStatus(data.message);
      setLastResult({
        message: data.message,
        applied: data.disabled.map((d) => ({ label: d.friendly_name })),
        skipped: [],
      });
      await loadAll();
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  async function disableTasks() {
    const tasks = taskItems.filter((t) => selectedTasks.has(t.id));
    if (tasks.length === 0) {
      setStatus("Please choose at least one scheduled task.");
      return;
    }
    setWorking(true);
    setFailed(false);
    setStatus("Working...");
    try {
      const data = await shieldRequest<{ message: string; disabled: { friendly_name: string }[] }>(
        "tasks_disable",
        { tasks }
      );
      setStatus(data.message);
      setLastResult({
        message: data.message,
        applied: data.disabled.map((d) => ({ label: d.friendly_name })),
        skipped: [],
      });
      await loadAll();
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  async function undoLast() {
    if (undoChanges.length === 0) {
      setStatus("There is nothing to undo right now.");
      return;
    }
    setWorking(true);
    setFailed(false);
    setStatus("Working...");
    try {
      const change = undoChanges[0];
      const data = await shieldRequest<{ message: string }>("undo_apply", {
        change_id: change.change_id,
      });
      setStatus(data.message);
      await loadAll();
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  const bloatItems = optimizerItems.filter((i) => i.section === "bloat");
  const perfItems = optimizerItems.filter((i) => i.section === "performance");

  return (
    <section className="tab-panel" aria-label="Optimizer">
      <h2>System Optimizer</h2>
      <p className="tab-desc">
        Remove apps you don't use, speed things up, and tidy startup programs. You choose — we never change anything without your OK.
      </p>

      {SECTIONS.map((section) => (
        <div className="section-block" key={section.id}>
          <button
            type="button"
            className="accordion-header"
            aria-expanded={openSection === section.id}
            onClick={() => setOpenSection(openSection === section.id ? "" : section.id)}
          >
            {section.title} {openSection === section.id ? "▾" : "▸"}
          </button>

          {openSection === section.id && (
            <div className="accordion-body">
              {section.id === "bloat" && (
                <>
                  <div className="checklist">
                    {bloatItems.map((item) => (
                      <div key={item.id} className={item.locked ? "check-item locked" : "check-item"}>
                        <input
                          type="checkbox"
                          id={`opt-${item.id}`}
                          checked={selectedOptimizer.has(item.id)}
                          disabled={item.locked}
                          onChange={() => toggleSet(setSelectedOptimizer, item.id)}
                        />
                        <label htmlFor={`opt-${item.id}`}>
                          <span className="label-row">
                            <strong>{item.label}</strong>
                            {item.locked && <span className="lock-icon">🔒</span>}
                          </span>
                          <span className="plain">{item.plain}</span>
                        </label>
                      </div>
                    ))}
                  </div>
                  <button type="button" className="primary-btn" disabled={working} onClick={applyOptimizer}>
                    Apply Selected Changes
                  </button>
                </>
              )}

              {section.id === "performance" && (
                <>
                  <div className="checklist">
                    {perfItems.map((item) => (
                      <div key={item.id} className={item.locked ? "check-item locked" : "check-item"}>
                        <input
                          type="checkbox"
                          id={`perf-${item.id}`}
                          checked={selectedOptimizer.has(item.id)}
                          disabled={item.locked}
                          onChange={() => toggleSet(setSelectedOptimizer, item.id)}
                        />
                        <label htmlFor={`perf-${item.id}`}>
                          <span className="label-row">
                            <strong>{item.label}</strong>
                            {item.locked && <span className="lock-icon">🔒</span>}
                          </span>
                          <span className="plain">{item.plain}</span>
                        </label>
                      </div>
                    ))}
                  </div>
                  <button type="button" className="primary-btn" disabled={working} onClick={applyOptimizer}>
                    Apply Selected Changes
                  </button>
                </>
              )}

              {section.id === "startup" && (
                <>
                  <div className="checklist">
                    {startupItems.map((item) => (
                      <div key={item.id} className="check-item">
                        <input
                          type="checkbox"
                          id={`startup-${item.id}`}
                          checked={selectedStartup.has(item.id)}
                          onChange={() => toggleSet(setSelectedStartup, item.id)}
                        />
                        <label htmlFor={`startup-${item.id}`}>
                          <strong>{item.friendly_name}</strong>
                          <span className="plain">
                            Runs when your computer starts — recommended: {item.recommended_action}
                          </span>
                        </label>
                      </div>
                    ))}
                    {startupItems.length === 0 && (
                      <p className="tab-desc">No startup items found.</p>
                    )}
                  </div>
                  <button type="button" className="primary-btn" disabled={working} onClick={disableStartup}>
                    Disable Selected Startup Items
                  </button>
                </>
              )}

              {section.id === "tasks" && (
                <>
                  <div className="checklist">
                    {taskItems.map((item) => (
                      <div key={item.id} className="check-item">
                        <input
                          type="checkbox"
                          id={`task-${item.id}`}
                          checked={selectedTasks.has(item.id)}
                          onChange={() => toggleSet(setSelectedTasks, item.id)}
                        />
                        <label htmlFor={`task-${item.id}`}>
                          <strong>{item.friendly_name}</strong>
                          <span className="plain">{item.plain_description}</span>
                        </label>
                      </div>
                    ))}
                    {taskItems.length === 0 && (
                      <p className="tab-desc">No scheduled tasks found in the monitored folders.</p>
                    )}
                  </div>
                  <button type="button" className="primary-btn" disabled={working} onClick={disableTasks}>
                    Disable Selected Tasks
                  </button>
                </>
              )}
            </div>
          )}
        </div>
      ))}

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

      {undoChanges.length > 0 && (
        <button type="button" className="secondary-btn" disabled={working} onClick={undoLast}>
          Undo Last Changes
        </button>
      )}

      {lastResult && lastResult.applied.length > 0 && (
        <div className="result-card">
          <p>{lastResult.message}</p>
          <button
            type="button"
            className="details-toggle"
            onClick={() => setShowDetails((v) => !v)}
          >
            {showDetails ? "Hide details" : "See what we changed"}
          </button>
          {showDetails && (
            <div className="details-list">
              {lastResult.applied.map((a) => (
                <div className="detail-item" key={a.label}>
                  <strong>{a.label}</strong>
                </div>
              ))}
              {lastResult.skipped.map((s) => (
                <div className="detail-item" key={s.label}>
                  <strong>{s.label}</strong>
                  <span>{s.reason}</span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {!isAdmin && (
        <p className="tab-desc">Some items above need admin access and are marked with a lock.</p>
      )}
    </section>
  );
}

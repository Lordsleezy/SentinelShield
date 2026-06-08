import { useEffect, useState } from "react";
import { EscalateCareButton } from "../components/EscalateCareButton";
import { GENERIC_ERROR, openLog, shieldRequest, subscribeEvents } from "../api";

type ScheduleSettings = {
  enabled: boolean;
  hour: number;
  minute: number;
  days: number[];
};

const DAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

type Alert = {
  id: string;
  message: string;
  friendly_name?: string;
  source?: string;
};

export function ProtectionTab() {
  const [working, setWorking] = useState(false);
  const [failed, setFailed] = useState(false);
  const [status, setStatus] = useState("Turn on real-time protection to watch for threats as they appear.");
  const [realtimeActive, setRealtimeActive] = useState(false);
  const [schedule, setSchedule] = useState<ScheduleSettings>({
    enabled: false,
    hour: 2,
    minute: 0,
    days: [0, 1, 2, 3, 4, 5, 6],
  });
  const [alerts, setAlerts] = useState<Alert[]>([]);

  useEffect(() => {
    loadStatus();
    const unsub = subscribeEvents(({ event, data }) => {
      if (event === "threat_detected" || event === "scheduled_scan_complete") {
        const message = String(data.message ?? "Something was detected.");
        setAlerts((prev) => [
          { id: crypto.randomUUID(), message, friendly_name: data.friendly_name as string, source: data.source as string },
          ...prev,
        ].slice(0, 10));
        if (event === "threat_detected") {
          setStatus(message);
        }
      }
      if (event === "realtime_started") {
        setRealtimeActive(true);
      }
    });
    return unsub;
  }, []);

  async function loadStatus() {
    try {
      const [rt, sched] = await Promise.all([
        shieldRequest<{ active: boolean }>("realtime_status"),
        shieldRequest<{ schedule: ScheduleSettings }>("schedule_get"),
      ]);
      setRealtimeActive(rt.active);
      setSchedule(sched.schedule);
    } catch {
      setFailed(true);
    }
  }

  async function toggleRealtime() {
    setWorking(true);
    setFailed(false);
    try {
      if (realtimeActive) {
        const data = await shieldRequest<{ message: string; active: boolean }>("realtime_stop");
        setRealtimeActive(data.active);
        setStatus(data.message);
      } else {
        const data = await shieldRequest<{ message: string; active: boolean }>("realtime_start");
        setRealtimeActive(data.active);
        setStatus(data.message);
      }
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  async function saveSchedule() {
    setWorking(true);
    setFailed(false);
    try {
      const data = await shieldRequest<{ message: string }>("schedule_set", { schedule });
      setStatus(data.message);
    } catch {
      setFailed(true);
      setStatus(GENERIC_ERROR);
    } finally {
      setWorking(false);
    }
  }

  function toggleDay(day: number) {
    setSchedule((prev) => {
      const days = new Set(prev.days);
      if (days.has(day)) {
        days.delete(day);
      } else {
        days.add(day);
      }
      return { ...prev, days: Array.from(days).sort() };
    });
  }

  return (
    <section className="tab-panel" aria-label="Protection">
      <h2>Real-Time Protection</h2>
      <p className="tab-desc">
        We watch your Downloads, Desktop, and Documents folders. If something suspicious appears, you'll get an alert right away.
      </p>

      <button
        type="button"
        className={realtimeActive ? "secondary-btn" : "primary-btn"}
        disabled={working}
        onClick={toggleRealtime}
      >
        {realtimeActive ? "Turn Off Real-Time Protection" : "Turn On Real-Time Protection"}
      </button>

      <p className={`status-pill ${realtimeActive ? "active" : ""}`}>
        {realtimeActive ? "Protection is ON" : "Protection is OFF"}
      </p>

      <h2 className="section-heading">Scheduled Scans</h2>
      <p className="tab-desc">
        Pick a time and we'll scan quietly in the background. We'll log anything we find — nothing is moved automatically.
      </p>

      <div className="check-item">
        <input
          type="checkbox"
          id="schedule-enabled"
          checked={schedule.enabled}
          onChange={(e) => setSchedule((s) => ({ ...s, enabled: e.target.checked }))}
        />
        <label htmlFor="schedule-enabled">
          <strong>Enable scheduled scans</strong>
        </label>
      </div>

      <div className="schedule-time">
        <label>
          Hour (0–23)
          <input
            type="number"
            min={0}
            max={23}
            value={schedule.hour}
            onChange={(e) => setSchedule((s) => ({ ...s, hour: Number(e.target.value) }))}
          />
        </label>
        <label>
          Minute (0–59)
          <input
            type="number"
            min={0}
            max={59}
            value={schedule.minute}
            onChange={(e) => setSchedule((s) => ({ ...s, minute: Number(e.target.value) }))}
          />
        </label>
      </div>

      <div className="day-picker">
        {DAY_LABELS.map((label, index) => (
          <button
            key={label}
            type="button"
            className={schedule.days.includes(index) ? "day-btn active" : "day-btn"}
            onClick={() => toggleDay(index)}
          >
            {label}
          </button>
        ))}
      </div>

      <button type="button" className="primary-btn" disabled={working} onClick={saveSchedule}>
        Save Schedule
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

      {alerts.length > 0 && (
        <div className="result-card">
          <h3 className="section-heading">Recent Alerts</h3>
          <div className="details-list">
            {alerts.map((alert) => (
              <div className="detail-item" key={alert.id}>
                <strong>{alert.friendly_name ?? "Alert"}</strong>
                <span>{alert.message}</span>
                {alert.source && <span>Source: {alert.source}</span>}
                <EscalateCareButton />
              </div>
            ))}
          </div>
        </div>
      )}
    </section>
  );
}

import { openSentinelCare } from "../api";

export function EscalateCareButton({ className }: { className?: string }) {
  return (
    <button
      type="button"
      className={className ? `care-btn ${className}` : "care-btn"}
      onClick={openSentinelCare}
    >
      Escalate to Sentinel Care
    </button>
  );
}

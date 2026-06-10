import { useEffect, useState } from "react";

interface ActivationGateProps {
  onActivated: () => void;
}

interface ValidationResult {
  valid: boolean;
  reason?: string;
  already_activated?: boolean;
  first_activation?: boolean;
  activated_at?: string;
}

const VALIDATION_ENDPOINT = "https://sentinelprime.org/.netlify/functions/validate-product";
const PRODUCT = "shield";
const STORAGE_KEY = "sentinel_shield_activated";
const ACTIVATION_DATA_KEY = "sentinel_shield_activation";

export function ActivationGate({ onActivated }: ActivationGateProps) {
  const [email, setEmail] = useState("");
  const [code, setCode] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isActivated, setIsActivated] = useState(false);

  useEffect(() => {
    // Check if already activated
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      const activationData = localStorage.getItem(ACTIVATION_DATA_KEY);
      if (stored === "true" && activationData) {
        const data = JSON.parse(activationData);
        if (data.email && data.code) {
          setEmail(data.email);
          setIsActivated(true);
          onActivated();
        }
      }
    } catch {
      // Ignore storage errors
    }
  }, [onActivated]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(VALIDATION_ENDPOINT, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email: email.trim(),
          code: code.trim().toUpperCase(),
          product: PRODUCT,
          machine_id: getMachineId()
        })
      });

      const result: ValidationResult = await response.json();

      if (result.valid) {
        // Store activation locally
        localStorage.setItem(STORAGE_KEY, "true");
        localStorage.setItem(
          ACTIVATION_DATA_KEY,
          JSON.stringify({
            email: email.trim().toLowerCase(),
            code: code.trim().toUpperCase(),
            activated_at: result.activated_at || new Date().toISOString()
          })
        );
        setIsActivated(true);
        onActivated();
      } else {
        setError(result.reason || "Invalid or already used activation code. Contact customerservice@sentinelprime.org");
      }
    } catch (err) {
      setError("Unable to connect to activation service. Please check your internet connection and try again.");
    } finally {
      setLoading(false);
    }
  };

  // Generate a simple machine ID for tracking
  function getMachineId(): string {
    try {
      let machineId = localStorage.getItem("sentinel_machine_id");
      if (!machineId) {
        machineId = `shield_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`;
        localStorage.setItem("sentinel_machine_id", machineId);
      }
      return machineId;
    } catch {
      return `shield_${Date.now()}`;
    }
  }

  if (isActivated) {
    return null;
  }

  return (
    <div className="activation-overlay">
      <div className="activation-modal">
        <div className="activation-header">
          <h1>Sentinel Shield</h1>
          <p>Activate your software to get started</p>
        </div>

        <form onSubmit={handleSubmit} className="activation-form">
          <div className="form-group">
            <label htmlFor="email">Email Address</label>
            <input
              type="email"
              id="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="Enter the email used for purchase"
              required
              disabled={loading}
            />
          </div>

          <div className="form-group">
            <label htmlFor="code">Activation Code</label>
            <input
              type="text"
              id="code"
              value={code}
              onChange={(e) => setCode(e.target.value.toUpperCase())}
              placeholder="XXXX-XXXX-XXXX-XXXX"
              required
              disabled={loading}
              pattern="[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}"
              title="Format: XXXX-XXXX-XXXX-XXXX"
            />
          </div>

          {error && (
            <div className="activation-error">
              {error}
            </div>
          )}

          <button
            type="submit"
            className="activation-submit"
            disabled={loading || !email || !code}
          >
            {loading ? "Activating..." : "Activate"}
          </button>
        </form>

        <div className="activation-footer">
          <p>Need help? Contact <a href="mailto:customerservice@sentinelprime.org">customerservice@sentinelprime.org</a></p>
          <p className="activation-hint">
            Your activation code was sent to your email after purchase.
          </p>
        </div>
      </div>

      <style>{`
        .activation-overlay {
          position: fixed;
          top: 0;
          left: 0;
          right: 0;
          bottom: 0;
          background: linear-gradient(135deg, #0a0a0f 0%, #1a1a2e 100%);
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 10000;
          padding: 20px;
        }

        .activation-modal {
          background: #151520;
          border: 1px solid #2a2a3e;
          border-radius: 12px;
          padding: 40px;
          width: 100%;
          max-width: 420px;
          box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
        }

        .activation-header {
          text-align: center;
          margin-bottom: 32px;
        }

        .activation-header h1 {
          color: #00d4ff;
          margin: 0 0 8px 0;
          font-size: 28px;
        }

        .activation-header p {
          color: #9aa3ad;
          margin: 0;
          font-size: 14px;
        }

        .activation-form {
          display: flex;
          flex-direction: column;
          gap: 20px;
        }

        .form-group {
          display: flex;
          flex-direction: column;
          gap: 6px;
        }

        .form-group label {
          color: #e0e0e0;
          font-size: 13px;
          font-weight: 500;
        }

        .form-group input {
          background: #0f0f18;
          border: 1px solid #2a2a3e;
          border-radius: 8px;
          padding: 12px 16px;
          color: #fff;
          font-size: 15px;
          font-family: monospace;
          transition: border-color 0.2s;
        }

        .form-group input:focus {
          outline: none;
          border-color: #00d4ff;
        }

        .form-group input:disabled {
          opacity: 0.6;
          cursor: not-allowed;
        }

        .activation-error {
          background: rgba(255, 77, 77, 0.1);
          border: 1px solid rgba(255, 77, 77, 0.3);
          border-radius: 8px;
          padding: 12px;
          color: #ff6b6b;
          font-size: 13px;
          text-align: center;
        }

        .activation-submit {
          background: linear-gradient(135deg, #00d4ff 0%, #0099cc 100%);
          border: none;
          border-radius: 8px;
          padding: 14px 24px;
          color: #000;
          font-size: 15px;
          font-weight: 600;
          cursor: pointer;
          transition: transform 0.2s, box-shadow 0.2s;
        }

        .activation-submit:hover:not(:disabled) {
          transform: translateY(-1px);
          box-shadow: 0 4px 20px rgba(0, 212, 255, 0.4);
        }

        .activation-submit:disabled {
          opacity: 0.6;
          cursor: not-allowed;
        }

        .activation-footer {
          margin-top: 24px;
          text-align: center;
        }

        .activation-footer p {
          color: #9aa3ad;
          font-size: 12px;
          margin: 8px 0;
        }

        .activation-footer a {
          color: #00d4ff;
          text-decoration: none;
        }

        .activation-footer a:hover {
          text-decoration: underline;
        }

        .activation-hint {
          color: #666 !important;
          font-size: 11px !important;
        }
      `}</style>
    </div>
  );
}

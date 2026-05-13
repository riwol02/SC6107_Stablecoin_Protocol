import React, { useState, useCallback } from "react";
import { useProtocol } from "./hooks/useProtocol";
import "./index.css";

// ─── Utility ─────────────────────────────────────────────────────────────────
const fmt = (n, decimals = 2) =>
  Number(n).toLocaleString("en-US", { maximumFractionDigits: decimals });

// ─── Sub-components ───────────────────────────────────────────────────────────

function HealthBadge({ value }) {
  const isInf = value === "∞";
  const num = parseFloat(value);
  const color = isInf || num >= 2 ? "#22c55e" : num >= 1.2 ? "#f59e0b" : "#ef4444";
  return (
    <span style={{ color, fontWeight: 600, fontSize: 18 }}>
      {isInf ? "∞ (safe)" : `${value}`}
    </span>
  );
}

function StatCard({ label, value, sub, accent }) {
  return (
    <div style={{
      background: "var(--bg2)",
      border: "0.5px solid var(--border)",
      borderRadius: 12,
      padding: "16px 20px",
    }}>
      <div style={{ fontSize: 12, color: "var(--text2)", marginBottom: 4 }}>{label}</div>
      <div style={{ fontSize: 22, fontWeight: 500, color: accent || "var(--text1)" }}>{value}</div>
      {sub && <div style={{ fontSize: 12, color: "var(--text3)", marginTop: 2 }}>{sub}</div>}
    </div>
  );
}

function TxButton({ onClick, disabled, loading, children, variant = "primary" }) {
  const isDisabled = disabled || loading;
  const bg = variant === "danger" ? "#ef4444" : "#6366f1";
  const borderColor = isDisabled ? "var(--border)" : variant === "danger" ? "#dc2626" : "#4f46e5";
  return (
    <button
      onClick={onClick}
      disabled={isDisabled}
      style={{
        background: isDisabled ? "var(--bg2)" : bg,
        border: `0.5px solid ${borderColor}`,
        color: isDisabled ? "var(--text3)" : "#fff",
        borderRadius: 8,
        padding: "10px 20px",
        fontWeight: 500,
        fontSize: 14,
        cursor: isDisabled ? "not-allowed" : "pointer",
        transition: "opacity 0.15s",
        width: "100%",
      }}
    >
      {loading ? "Confirming…" : children}
    </button>
  );
}

function FormGroup({ label, children }) {
  return (
    <div style={{ marginBottom: 12 }}>
      <label style={{ fontSize: 12, color: "var(--text2)", display: "block", marginBottom: 4 }}>
        {label}
      </label>
      {children}
    </div>
  );
}

function Input({ value, onChange, placeholder, type = "number" }) {
  return (
    <input
      type={type}
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      style={{
        width: "100%",
        background: "var(--bg1)",
        border: "0.5px solid var(--border)",
        borderRadius: 8,
        padding: "8px 12px",
        fontSize: 14,
        color: "var(--text1)",
        boxSizing: "border-box",
      }}
    />
  );
}

function TokenSelect({ value, onChange, tokens }) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      style={{
        width: "100%",
        background: "var(--bg1)",
        border: "0.5px solid var(--border)",
        borderRadius: 8,
        padding: "8px 12px",
        fontSize: 14,
        color: "var(--text1)",
      }}
    >
      {tokens.map((t) => (
        <option key={t.symbol} value={t.symbol}>
          {t.icon} {t.symbol}
        </option>
      ))}
    </select>
  );
}

// ─── Panel: Deposit & Mint ────────────────────────────────────────────────────
function DepositMintPanel({ protocol }) {
  const [token, setToken] = useState("WETH");
  const [collateral, setCollateral] = useState("");
  const [dscAmount, setDscAmount] = useState("");
  const [result, setResult] = useState(null);

  const handleSubmit = useCallback(async () => {
    if (!collateral || !dscAmount) return;
    const res = await protocol.depositAndMint(token, collateral, dscAmount);
    setResult(res);
    if (res.success) { setCollateral(""); setDscAmount(""); }
  }, [protocol, token, collateral, dscAmount]);

  return (
    <div>
      <h3 style={{ margin: "0 0 16px", fontSize: 16, fontWeight: 500 }}>Deposit & Mint DSC</h3>
      <FormGroup label="Collateral Token">
        <TokenSelect value={token} onChange={setToken} tokens={protocol.supportedTokens} />
      </FormGroup>
      <FormGroup label="Collateral Amount">
        <Input value={collateral} onChange={setCollateral} placeholder="e.g. 1.5" />
      </FormGroup>
      <FormGroup label="DSC to Mint">
        <Input value={dscAmount} onChange={setDscAmount} placeholder="e.g. 1000" />
      </FormGroup>
      <TxButton onClick={handleSubmit} loading={protocol.txPending} disabled={!collateral || !dscAmount}>
        Deposit & Mint
      </TxButton>
      {result && (
        <div style={{
          marginTop: 10,
          padding: "8px 12px",
          background: result.success ? "#dcfce7" : "#fee2e2",
          borderRadius: 8,
          fontSize: 13,
          color: result.success ? "#15803d" : "#b91c1c",
        }}>
          {result.success ? `Success! Tx: ${result.hash?.slice(0, 10)}…` : result.error}
        </div>
      )}
    </div>
  );
}

// ─── Panel: Redeem & Burn ─────────────────────────────────────────────────────
function RedeemBurnPanel({ protocol }) {
  const [token, setToken] = useState("WETH");
  const [collateral, setCollateral] = useState("");
  const [dscAmount, setDscAmount] = useState("");
  const [result, setResult] = useState(null);

  const handleSubmit = useCallback(async () => {
    if (!collateral || !dscAmount) return;
    const res = await protocol.redeemAndBurn(token, collateral, dscAmount);
    setResult(res);
    if (res.success) { setCollateral(""); setDscAmount(""); }
  }, [protocol, token, collateral, dscAmount]);

  return (
    <div>
      <h3 style={{ margin: "0 0 16px", fontSize: 16, fontWeight: 500 }}>Redeem Collateral & Burn DSC</h3>
      <FormGroup label="Collateral Token">
        <TokenSelect value={token} onChange={setToken} tokens={protocol.supportedTokens} />
      </FormGroup>
      <FormGroup label="Collateral to Redeem">
        <Input value={collateral} onChange={setCollateral} placeholder="e.g. 0.5" />
      </FormGroup>
      <FormGroup label="DSC to Burn">
        <Input value={dscAmount} onChange={setDscAmount} placeholder="e.g. 500" />
      </FormGroup>
      <TxButton onClick={handleSubmit} loading={protocol.txPending} disabled={!collateral || !dscAmount}>
        Redeem & Burn
      </TxButton>
      {result && (
        <div style={{
          marginTop: 10,
          padding: "8px 12px",
          background: result.success ? "#dcfce7" : "#fee2e2",
          borderRadius: 8,
          fontSize: 13,
          color: result.success ? "#15803d" : "#b91c1c",
        }}>
          {result.success ? `Success! Tx: ${result.hash?.slice(0, 10)}…` : result.error}
        </div>
      )}
    </div>
  );
}

// ─── Panel: Liquidate ─────────────────────────────────────────────────────────
function LiquidatePanel({ protocol }) {
  const [token, setToken] = useState("WETH");
  const [userAddr, setUserAddr] = useState("");
  const [debtAmount, setDebtAmount] = useState("");
  const [result, setResult] = useState(null);

  const handleSubmit = useCallback(async () => {
    if (!userAddr || !debtAmount) return;
    const res = await protocol.liquidate(token, userAddr, debtAmount);
    setResult(res);
    if (res.success) { setUserAddr(""); setDebtAmount(""); }
  }, [protocol, token, userAddr, debtAmount]);

  return (
    <div>
      <h3 style={{ margin: "0 0 8px", fontSize: 16, fontWeight: 500 }}>Liquidate Position</h3>
      <p style={{ fontSize: 12, color: "var(--text2)", margin: "0 0 14px" }}>
        Repay DSC debt of an undercollateralized user and receive their collateral + 10% bonus.
      </p>
      <FormGroup label="Collateral Token to Seize">
        <TokenSelect value={token} onChange={setToken} tokens={protocol.supportedTokens} />
      </FormGroup>
      <FormGroup label="User Address">
        <Input value={userAddr} onChange={setUserAddr} placeholder="0x…" type="text" />
      </FormGroup>
      <FormGroup label="DSC Debt to Cover">
        <Input value={debtAmount} onChange={setDebtAmount} placeholder="e.g. 1000" />
      </FormGroup>
      <TxButton onClick={handleSubmit} loading={protocol.txPending} disabled={!userAddr || !debtAmount} variant="danger">
        Liquidate
      </TxButton>
      {result && (
        <div style={{
          marginTop: 10,
          padding: "8px 12px",
          background: result.success ? "#dcfce7" : "#fee2e2",
          borderRadius: 8,
          fontSize: 13,
          color: result.success ? "#15803d" : "#b91c1c",
        }}>
          {result.success ? `Liquidated! Tx: ${result.hash?.slice(0, 10)}…` : result.error}
        </div>
      )}
    </div>
  );
}

// ─── Health Factor Visualizer ─────────────────────────────────────────────────
function HealthGauge({ value }) {
  const isInf = value === "∞";
  const num = isInf ? 6 : Math.min(parseFloat(value) || 0, 6);
  const pct = Math.min(num / 6, 1);
  const color = isInf || num >= 2 ? "#22c55e" : num >= 1.2 ? "#f59e0b" : "#ef4444";
  const width = `${Math.round(pct * 100)}%`;

  return (
    <div style={{ marginTop: 8 }}>
      <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12, color: "var(--text2)", marginBottom: 4 }}>
        <span>0 (liquidatable)</span>
        <span>6+ (safe)</span>
      </div>
      <div style={{ height: 12, background: "var(--bg2)", borderRadius: 6, overflow: "hidden" }}>
        <div style={{ height: "100%", width, background: color, borderRadius: 6, transition: "width 0.4s" }} />
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 6 }}>
        <div style={{ width: 8, height: 8, borderRadius: "50%", background: color }} />
        <span style={{ fontSize: 13, color }}>
          {isInf ? "No debt — infinitely safe" : num < 1 ? "LIQUIDATABLE" : num < 1.5 ? "Risky" : "Healthy"}
        </span>
      </div>
    </div>
  );
}

// ─── Main App ─────────────────────────────────────────────────────────────────
export default function App() {
  const protocol = useProtocol();
  const [activePanel, setActivePanel] = useState("deposit");
  const { accountInfo } = protocol;

  const panels = [
    { id: "deposit", label: "Deposit & Mint" },
    { id: "redeem", label: "Redeem & Burn" },
    { id: "liquidate", label: "Liquidate" },
  ];

  return (
    <div style={{ minHeight: "100vh", background: "var(--bg0)", color: "var(--text1)", fontFamily: "system-ui, sans-serif" }}>
      {/* Header */}
      <div style={{ borderBottom: "0.5px solid var(--border)", padding: "0 24px", display: "flex", alignItems: "center", gap: 16, height: 56 }}>
        <div style={{ fontWeight: 600, fontSize: 16, letterSpacing: -0.3 }}>
          DSC Protocol
        </div>
        <div style={{ fontSize: 12, color: "var(--text3)", background: "var(--bg2)", padding: "2px 10px", borderRadius: 99 }}>
          Sepolia Testnet
        </div>
        <div style={{ flex: 1 }} />
        {protocol.isConnected ? (
          <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
            <div style={{ width: 8, height: 8, borderRadius: "50%", background: "#22c55e" }} />
            <span style={{ fontSize: 13, color: "var(--text2)", fontFamily: "monospace" }}>
              {protocol.address.slice(0, 6)}…{protocol.address.slice(-4)}
            </span>
          </div>
        ) : (
          <button
            onClick={protocol.connect}
            disabled={protocol.loading}
            style={{
              background: "#6366f1",
              color: "#fff",
              border: "none",
              borderRadius: 8,
              padding: "8px 16px",
              fontWeight: 500,
              fontSize: 13,
              cursor: "pointer",
            }}
          >
            {protocol.loading ? "Connecting…" : "Connect Wallet"}
          </button>
        )}
      </div>

      {/* Error banner */}
      {protocol.error && (
        <div style={{ background: "#fee2e2", color: "#b91c1c", padding: "10px 24px", fontSize: 13 }}>
          {protocol.error}
        </div>
      )}

      {!protocol.isConnected ? (
        /* Landing */
        <div style={{ maxWidth: 480, margin: "120px auto", textAlign: "center", padding: "0 24px" }}>
          <div style={{ fontSize: 40, marginBottom: 16 }}>🏛</div>
          <h1 style={{ fontWeight: 600, fontSize: 24, margin: "0 0 12px" }}>Decentralized Stable Coin</h1>
          <p style={{ color: "var(--text2)", fontSize: 15, lineHeight: 1.6, margin: "0 0 32px" }}>
            Deposit WETH or WBTC as collateral and mint DSC, a USD-pegged stablecoin.
            Over-collateralized at 150% with on-chain Chainlink price feeds.
          </p>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr 1fr", gap: 12, marginBottom: 32 }}>
            {[["150%", "Collateral ratio"], ["10%", "Liquidation bonus"], ["0%", "Stability fee"]].map(([v, l]) => (
              <div key={l} style={{ background: "var(--bg2)", borderRadius: 10, padding: "12px 8px", border: "0.5px solid var(--border)" }}>
                <div style={{ fontWeight: 600, fontSize: 18, color: "#6366f1" }}>{v}</div>
                <div style={{ fontSize: 11, color: "var(--text2)", marginTop: 2 }}>{l}</div>
              </div>
            ))}
          </div>
          <button
            onClick={protocol.connect}
            style={{ background: "#6366f1", color: "#fff", border: "none", borderRadius: 10, padding: "14px 40px", fontWeight: 600, fontSize: 15, cursor: "pointer" }}
          >
            Connect Wallet
          </button>
        </div>
      ) : (
        <div style={{ maxWidth: 1100, margin: "0 auto", padding: "24px 24px" }}>
          {/* Stats row */}
          <div style={{ display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 12, marginBottom: 24 }}>
            <StatCard label="DSC Minted" value={`$${fmt(accountInfo.dscMinted)}`} sub="USD" />
            <StatCard label="Collateral Value" value={`$${fmt(accountInfo.collateralValueUsd)}`} sub="USD" />
            <StatCard
              label="Health Factor"
              value={<HealthBadge value={accountInfo.healthFactor} />}
            />
            <StatCard label="DSC Balance" value={fmt(accountInfo.dscBalance)} sub="in wallet" />
          </div>

          {/* Health gauge */}
          <div style={{ background: "var(--bg2)", border: "0.5px solid var(--border)", borderRadius: 12, padding: "16px 20px", marginBottom: 24 }}>
            <div style={{ fontSize: 13, fontWeight: 500, marginBottom: 4 }}>Position Health</div>
            <HealthGauge value={accountInfo.healthFactor} />
          </div>

          {/* Collateral breakdown */}
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12, marginBottom: 24 }}>
            <div style={{ background: "var(--bg2)", border: "0.5px solid var(--border)", borderRadius: 12, padding: "16px 20px" }}>
              <div style={{ fontSize: 12, color: "var(--text2)", marginBottom: 8 }}>Ξ WETH Position</div>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13 }}>
                <span style={{ color: "var(--text2)" }}>Wallet</span>
                <span>{fmt(accountInfo.wethBalance, 4)} WETH</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13, marginTop: 4 }}>
                <span style={{ color: "var(--text2)" }}>Deposited</span>
                <span>{fmt(accountInfo.wethCollateral, 4)} WETH</span>
              </div>
            </div>
            <div style={{ background: "var(--bg2)", border: "0.5px solid var(--border)", borderRadius: 12, padding: "16px 20px" }}>
              <div style={{ fontSize: 12, color: "var(--text2)", marginBottom: 8 }}>₿ WBTC Position</div>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13 }}>
                <span style={{ color: "var(--text2)" }}>Wallet</span>
                <span>{fmt(accountInfo.wbtcBalance, 6)} WBTC</span>
              </div>
              <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13, marginTop: 4 }}>
                <span style={{ color: "var(--text2)" }}>Deposited</span>
                <span>{fmt(accountInfo.wbtcCollateral, 6)} WBTC</span>
              </div>
            </div>
          </div>

          {/* Action panels */}
          <div style={{ display: "grid", gridTemplateColumns: "220px 1fr", gap: 16 }}>
            {/* Nav */}
            <div style={{ background: "var(--bg2)", border: "0.5px solid var(--border)", borderRadius: 12, padding: 8, alignSelf: "start" }}>
              {panels.map((p) => (
                <button
                  key={p.id}
                  onClick={() => setActivePanel(p.id)}
                  style={{
                    width: "100%",
                    textAlign: "left",
                    background: activePanel === p.id ? "var(--bg0)" : "transparent",
                    border: activePanel === p.id ? "0.5px solid var(--border)" : "none",
                    borderRadius: 8,
                    padding: "10px 14px",
                    fontSize: 13,
                    fontWeight: activePanel === p.id ? 500 : 400,
                    color: activePanel === p.id ? "var(--text1)" : "var(--text2)",
                    cursor: "pointer",
                    marginBottom: 2,
                  }}
                >
                  {p.label}
                </button>
              ))}
            </div>

            {/* Panel content */}
            <div style={{ background: "var(--bg2)", border: "0.5px solid var(--border)", borderRadius: 12, padding: "20px 24px" }}>
              {activePanel === "deposit" && <DepositMintPanel protocol={protocol} />}
              {activePanel === "redeem" && <RedeemBurnPanel protocol={protocol} />}
              {activePanel === "liquidate" && <LiquidatePanel protocol={protocol} />}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

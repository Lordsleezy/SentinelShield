import { openSentinelMarket } from "../api";

export function ShopMarketButton({ className }: { className?: string }) {
  return (
    <button
      type="button"
      className={className ? `market-btn ${className}` : "market-btn"}
      onClick={openSentinelMarket}
    >
      Shop at Sentinel Market
    </button>
  );
}

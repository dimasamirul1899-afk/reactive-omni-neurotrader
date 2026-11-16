#!/usr/bin/env bash
# Drive the NeuroTrader loop on testnet: report a price series to the oracle
# on Base Sepolia, which emits PriceUpdate events -> Lasna reactive contract
# runs the model -> callbacks land on the TradeExecutor (Base Sepolia).
# Usage: bash scripts/drive.sh [up|down|flat] [steps]
# Requires deployments.json (from scripts/deploy.sh) and a funded deployer.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"

MODE="${1:-up}"
STEPS="${2:-12}"
BASE_SEPOLIA_RPC="https://sepolia.base.org"
PK=$(python3 -c "import json; print(json.load(open('.secrets/deployer.json'))['data'][0]['private_key'])")
ORACLE=$(python3 -c "import json; print(json.load(open('deployments.json'))['baseSepolia']['oracle'])")
REACTIVE=$(python3 -c "import json; print(json.load(open('deployments.json'))['lasna']['reactive'])")
EXECUTOR=$(python3 -c "import json; print(json.load(open('deployments.json'))['baseSepolia']['executor'])")

# Prices in USD x 1e8. Start $3000, step +/-0.5%.
python3 - "$MODE" "$STEPS" > /tmp/prices.txt <<'EOF'
import sys
mode, steps = sys.argv[1], int(sys.argv[2])
p = 3000_00000000
for i in range(steps):
    print(p)
    if mode == "up":
        p = p * 1005 // 1000
    elif mode == "down":
        p = p * 995 // 1000
    else:
        p = p + (1000000 if i % 2 == 0 else -1000000)
EOF

echo "oracle: $ORACLE  reactive: $REACTIVE  executor: $EXECUTOR"
echo "driving $STEPS price reports ($MODE)..."
while read -r price; do
    TX=$(cast send "$ORACLE" --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PK" "reportPrice(uint256)" "$price" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['transactionHash'])")
    echo "  price $price -> $TX"
    sleep 2
done < /tmp/prices.txt

echo "Waiting 60s for reactive txs + callbacks to land, then reading state..."
sleep 60
echo "== reactive (Lasna):"
cast call "$REACTIVE" "decisions()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
cast call "$REACTIVE" "callbacksSent()(uint256)" --rpc-url https://lasna-rpc.rnk.dev/
cast call "$REACTIVE" "lastAction()(uint8)" --rpc-url https://lasna-rpc.rnk.dev/
echo "== executor (Base Sepolia):"
cast call "$EXECUTOR" "tradeCount()(uint256)" --rpc-url "$BASE_SEPOLIA_RPC"
cast call "$EXECUTOR" "position()(uint8)" --rpc-url "$BASE_SEPOLIA_RPC"
cast call "$EXECUTOR" "realizedPnl()(int256)" --rpc-url "$BASE_SEPOLIA_RPC"
echo "Check the loop on explorers:"
echo "  Lasna reactive txs: https://lasna.reactscan.net/address/$REACTIVE"
echo "  Base executor txs:  https://sepolia.basescan.org/address/$EXECUTOR"

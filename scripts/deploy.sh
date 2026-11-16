#!/usr/bin/env bash
# Deploy NeuroTrader to testnet (run ON the VPS, which has working RPC access).
# Requires: funded deployer key at .secrets/deployer.json (Base Sepolia ETH).
#   1. Get Base Sepolia ETH from a faucet (e.g. Alchemy):
#        https://www.alchemy.com/faucets/base-sepolia
#      for address $DEPLOYER (printed at the end of this script's step 0).
#   2. Run: bash scripts/deploy.sh
# Steps: oracle (Base Sepolia) -> lREACT via Lasna faucet contract ->
#   reactive (Lasna, funded) -> executor (Base Sepolia, funded) ->
#   wire setExecutor (Lasna). Addresses are saved to deployments.json.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.foundry/bin:$PATH"

BASE_SEPOLIA_RPC="https://sepolia.base.org"
LASNA_RPC="https://lasna-rpc.rnk.dev"
BASE_PROXY="0x476F44b11F5C942c58f4c8E3d0300E5710743585"
LASNA_FAUCET="0x2afaFD298b23b62760711756088F75B7409f5967" # Base Sepolia -> lREACT, 1 ETH = 100 lREACT

PK=$(python3 -c "import json; print(json.load(open('.secrets/deployer.json'))['data'][0]['private_key'])")
ADDR=$(python3 -c "import json; print(json.load(open('.secrets/deployer.json'))['data'][0]['address'])")

echo "== deployer: $ADDR"
echo "== Base Sepolia balance: $(cast balance "$ADDR" --rpc-url "$BASE_SEPOLIA_RPC")"
echo "== Lasna balance: $(cast balance "$ADDR" --rpc-url "$LASNA_RPC")"

echo "== [1/5] deploy PriceOracle on Base Sepolia"
ORACLE=$(forge create src/PriceOracle.sol:PriceOracle --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PK" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['deployedTo'])")
echo "   oracle: $ORACLE"

echo "== [2/5] swap 0.1 Base Sepolia ETH -> 10 lREACT (Lasna faucet contract)"
cast send "$LASNA_FAUCET" --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PK" "request(address)" "$ADDR" --value 0.1ether --json | python3 -c "import json,sys; print('   tx:', json.load(sys.stdin)['transactionHash'])"
sleep 10
echo "== Lasna balance now: $(cast balance "$ADDR" --rpc-url "$LASNA_RPC")"

echo "== [3/5] deploy NeuroTraderReactive on Lasna (funded with 1 lREACT)"
REACTIVE=$(forge create src/NeuroTraderReactive.sol:NeuroTraderReactive --rpc-url "$LASNA_RPC" --private-key "$PK" --constructor-args 84532 "$ORACLE" 84532 --value 1ether --json | python3 -c "import json,sys; print(json.load(sys.stdin)['deployedTo'])")
echo "   reactive: $REACTIVE"

echo "== [4/5] deploy TradeExecutor on Base Sepolia (funded with 0.01 ETH)"
EXECUTOR=$(forge create src/TradeExecutor.sol:TradeExecutor --rpc-url "$BASE_SEPOLIA_RPC" --private-key "$PK" --constructor-args "$BASE_PROXY" "$REACTIVE" "$ORACLE" --value 0.01ether --json | python3 -c "import json,sys; print(json.load(sys.stdin)['deployedTo'])")
echo "   executor: $EXECUTOR"

echo "== [5/5] wire executor into reactive contract (Lasna)"
cast send "$REACTIVE" --rpc-url "$LASNA_RPC" --private-key "$PK" "setExecutor(address)" "$EXECUTOR" --json | python3 -c "import json,sys; print('   tx:', json.load(sys.stdin)['transactionHash'])"

python3 - "$ORACLE" "$REACTIVE" "$EXECUTOR" "$ADDR" <<'EOF'
import json, sys
d = {
    "deployer": sys.argv[4],
    "baseSepolia": {"chainId": 84532, "rpc": "https://sepolia.base.org",
                    "explorer": "https://sepolia.basescan.org",
                    "oracle": sys.argv[1], "executor": sys.argv[3],
                    "callbackProxy": "0x476F44b11F5C942c58f4c8E3d0300E5710743585"},
    "lasna": {"chainId": 5318007, "rpc": "https://lasna-rpc.rnk.dev",
              "explorer": "https://lasna.reactscan.net",
              "reactive": sys.argv[2],
              "system": "0x8888888888888888888888888888888888888888"},
}
open("deployments.json", "w").write(json.dumps(d, indent=2))
print("wrote deployments.json")
EOF
echo "DONE. Addresses saved to deployments.json"

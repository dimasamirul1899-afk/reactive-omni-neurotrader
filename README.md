# NeuroTrader — Reactive Meets AI

A tiny neural network that lives inside a Reactive contract and trades on what it sees.
Entry for the **Reactive Omni Buildathon** (DoraHacks) — track **Reactive Meets AI**, deadline **5 Dec 2026**.
Prize pool $5,500 in REACT (AI track: $1,000 first place).

## The idea

Reactive contracts watch events on other chains and react on their own — no bot to keep running.
This entry puts the **AI inside the running system**: a frozen 3 → 4 → 1 MLP executes in `react()`
on every price event, deterministically, on-chain. No off-chain component, no paid API.

- **PriceOracle** (Base Sepolia) emits `PriceUpdate` events.
- **NeuroTraderReactive** (Reactive Lasna) subscribes, keeps an 8-price window, runs the model,
  and on a confident signal requests a callback.
- **TradeExecutor** (Base Sepolia) receives the callback and runs a paper long/flat portfolio,
  banking realized PnL — the auditable on-chain record of every model decision.

Demo (same fixed-point math as the contract, in your browser): open `web/index.html`.

## The model

- 3 → 4 → 1 MLP, activation `φ(x) = x / (1 + |x|)`, fixed-point 1e18.
- Features from the last 8 prices: 1-step return ×10, 5-step return ×10, window volatility ×10.
- Decision: score ≥ +0.25 → BUY, ≤ −0.25 → SELL, else HOLD. Cooldown 3 updates, no repeated same-side trades.
- Trained offline on synthetic momentum-regime price paths (pure Python, seed 1337).
  Fresh synthetic data (seed 999, 25,200 windows): **77.3% accuracy** at |score| ≥ 0.25 (vs 50% random),
  48.8% coverage; raw sign accuracy 71.2%.
- Full model card: [MODEL.md](MODEL.md). Training + weights: `model/`.

## Contracts

| Contract | Chain | Address |
|---|---|---|
| PriceOracle | Base Sepolia (84532) | TBD — see Deployment |
| NeuroTraderReactive | Lasna (5318007) | TBD — see Deployment |
| TradeExecutor | Base Sepolia (84532) | TBD — see Deployment |

Explorers: [lasna.reactscan.net](https://lasna.reactscan.net/) · [sepolia.basescan.org](https://sepolia.basescan.org/)

## Tests

```bash
git clone --recursive https://github.com/dimasamirul1899-afk/reactive-omni-neurotrader.git
cd reactive-omni-neurotrader
forge test   # 23 tests, all passing
```

Tests cover: exact fixed-point vectors (verified bit-exact against the Python integer
reference in `model/ref_vectors.py`), the full react → decision → callback-payload loop
with a mocked system contract, and the executor's auth guards + paper PnL math.

## Deployment

Deploys run from the VPS (`~/neurotrader`), because the build VM's egress proxy blocks
JSON-RPC POSTs. The deployer is a throwaway keypair whose address is recorded in
`deployments.json` once deployed.

**Funding (the one manual step):** the deployer needs Base Sepolia ETH (testnet, free).
Get it from the Alchemy Base Sepolia faucet — https://www.alchemy.com/faucets/base-sepolia —
and send it to the deployer address in `deployments.json` (or printed by `scripts/deploy.sh`).
~0.2 ETH is plenty (deploys + funding + 0.1 ETH swapped for lREACT via the Lasna faucet
contract, 1 ETH = 100 lREACT).

```bash
bash scripts/deploy.sh   # oracle -> lREACT -> reactive -> executor -> wire setExecutor
bash scripts/drive.sh up 12    # report 12 rising prices, watch the loop fire
```

## Submission (DoraHacks)

1. Register on [DoraHacks](https://dorahacks.io/) and pick the **Reactive Meets AI** track.
2. Submit: this repo link, the three deployed contract addresses, transaction hashes showing
   the full loop (oracle `PriceUpdate` → Lasna reactive tx → Base Sepolia callback), and a
   demo video under 3 minutes (walkthrough of `web/index.html` + the explorer links).
3. Repos must be public and open-source (MIT) by submission time.

## Why this track

Set It and Forget It pays more ($2,000) but is crowded with stop-loss clones — the Reactive
demo repo literally ships stop-order examples. Reactive Meets AI is the open question the
organizers pose ("we don't know yet what the most interesting combination looks like"), and
an on-chain model deciding what the reactive contract does next is the most literal, verifiable
answer to it: the AI is part of the running system, not just the tool that wrote the code.

## License

MIT.

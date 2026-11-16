# Model card — NeuroTrader MLP

## What it is

A 3 → 4 → 1 multilayer perceptron that runs **fully on-chain** inside
`NeuroTraderReactive.react()`. It reads price events and outputs a trading signal.
It is the AI in the "Reactive Meets AI" track: the model is part of the running
system, not just the tool that wrote the code.

## Architecture

- Inputs (3): from the last 8 prices (p0 = newest, USD × 1e8):
  - f1 = 10 × (p0 − p1) / p1 — 1-step return
  - f2 = 10 × (p0 − p4) / p4 — 5-step return
  - f3 = 10 × (max − min) / mean over the window — volatility
- Hidden layer: 4 units, activation `φ(x) = x / (1 + |x|)`
- Output: 1 unit, same activation → score in (−1, 1)
- Decision: score ≥ +0.25 → BUY, ≤ −0.25 → SELL, else HOLD
- All arithmetic is integer fixed-point, scale 1e18, trunc-toward-zero division —
  identical in Python (`model/ref_vectors.py`), Solidity (`src/NeuroNet.sol`),
  and the demo page (`web/index.html`, BigInt).

## Training

- `model/train_model.py` — pure Python stdlib, seed 1337.
- Data: synthetic price paths (120 episodes × 220 steps) in four regimes —
  momentum up (+0.4%/step), momentum down (−0.4%/step), mean-reversion, chop —
  plus Gaussian noise. 25,200 windows of 8 prices.
- Label: sign of the 3-step-ahead return, deadband 0.2%.
- Optimizer: full-batch gradient descent, 300 epochs, lr 0.08, MSE loss.
- Weights frozen after training; exported as int256 (×1e18) in
  `model/model-weights.json` and embedded as constants in `src/NeuroNet.sol`.

## Evaluation

Fresh synthetic data (seed 999, 25,200 windows, quantized weights):

| Threshold | Accuracy | Coverage |
|---|---|---|
| \|score\| ≥ 0.20 | 76.3% | 63.9% |
| \|score\| ≥ 0.25 | **77.3%** | **48.8%** |
| \|score\| ≥ 0.30 | 78.1% | 32.5% |
| \|score\| ≥ 0.35 | 77.4% | 17.0% |

Raw sign accuracy (no threshold): 71.2%. Random baseline: 50%.
Threshold 0.25 was chosen as the best accuracy/coverage balance, and verified
against the contract's exact integer math: a +0.5%/step uptrend scores +0.343
(BUY), a −0.5%/step downtrend scores −0.279 (SELL), a flat series scores −0.118
(HOLD) — see `test/NeuroNet.t.sol`.

## Limitations (honest)

- Trained on **synthetic** data, not real market data. It learns momentum
  persistence in the regimes it was shown; real markets regime-shift, and the
  model has no concept of that.
- The price feed in the demo is a **stand-in oracle** anyone can report to.
  In production it would be Chainlink / Uniswap TWAP; the reactive contract
  subscribes by event signature, so swapping the feed is a constructor change.
- The executor runs a **paper** portfolio (no real funds move). It is the
  auditable record of decisions and the hook where a real strategy plugs in.
- This is a hackathon demo model, not financial advice.

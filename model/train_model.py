#!/usr/bin/env python3
"""Train the tiny 3->4->1 MLP for NeuroTrader (Reactive Omni Buildathon).

Pure stdlib. Trains offline on synthetic price paths with momentum regimes,
then exports frozen int256 weights (1e18 fixed point) for the on-chain
inference in src/NeuroNet.sol. The Solidity code mirrors this math exactly:
same features, same activation phi(x) = x / (1 + |x|), same x10 feature scale.

Features (from the last 8 prices, p0 = newest):
  f1 = 10 * (p0 - p1) / p1            (short return, 1 step)
  f2 = 10 * (p0 - p4) / p4            (medium return, 5 steps)
  f3 = 10 * (max(p0..p7) - min(p0..p7)) / mean(p0..p7)  (volatility)
Label: sign of the 3-step-ahead return, deadband 0.2%.
"""
import json
import math
import random

SCALE = 10**18
FEATURE_SCALE = 10.0  # returns are multiplied by 10 before the net


def phi(x: float) -> float:
    return x / (1.0 + abs(x))


def phi_d(x: float) -> float:
    return 1.0 / (1.0 + abs(x)) ** 2


def make_paths(rng: random.Random, n_episodes: int = 120, steps: int = 220):
    """Synthetic price paths with four regimes."""
    paths = []
    for _ in range(n_episodes):
        regime = rng.choice(["up", "down", "revert", "chop"])
        price = 3000.0
        mean = 3000.0
        series = [price]
        for _ in range(steps):
            if regime == "up":
                drift = 0.004
                vol = 0.005
            elif regime == "down":
                drift = -0.004
                vol = 0.005
            elif regime == "revert":
                drift = -0.02 * (price - mean) / mean
                vol = 0.006
            else:
                drift = 0.0
                vol = 0.010
            price *= 1.0 + drift + rng.gauss(0.0, vol)
            series.append(price)
        paths.append(series)
    return paths


def features(prices):
    """prices: list of 8, newest first. Returns (f1, f2, f3) floats."""
    p0, p1, p4 = prices[0], prices[1], prices[4]
    f1 = FEATURE_SCALE * (p0 - p1) / p1
    f2 = FEATURE_SCALE * (p0 - p4) / p4
    lo, hi = min(prices), max(prices)
    mean = sum(prices) / len(prices)
    f3 = FEATURE_SCALE * (hi - lo) / mean
    return (f1, f2, f3)


def build_dataset(rng):
    paths = make_paths(rng)
    X, y = [], []
    for series in paths:
        for t in range(8, len(series) - 3):
            window = [series[t - 1 - k] for k in range(8)]  # newest first
            nxt = (series[t + 2] - series[t - 1]) / series[t - 1]
            if nxt > 0.002:
                label = 1.0
            elif nxt < -0.002:
                label = -1.0
            else:
                label = 0.0
            X.append(features(window))
            y.append(label)
    return X, y


class Net:
    def __init__(self, rng):
        self.w1 = [[rng.uniform(-0.8, 0.8) for _ in range(3)] for _ in range(4)]
        self.b1 = [rng.uniform(-0.3, 0.3) for _ in range(4)]
        self.w2 = [rng.uniform(-0.8, 0.8) for _ in range(4)]
        self.b2 = rng.uniform(-0.3, 0.3)

    def forward(self, x):
        h_pre = [sum(self.w1[j][i] * x[i] for i in range(3)) + self.b1[j] for j in range(4)]
        h = [phi(v) for v in h_pre]
        o_pre = sum(self.w2[j] * h[j] for j in range(4)) + self.b2
        return phi(o_pre), h, h_pre, o_pre

    def train(self, X, y, epochs=300, lr=0.08):
        n = len(X)
        for ep in range(epochs):
            g_w1 = [[0.0] * 3 for _ in range(4)]
            g_b1 = [0.0] * 4
            g_w2 = [0.0] * 4
            g_b2 = 0.0
            loss = 0.0
            for x, t in zip(X, y):
                o, h, h_pre, o_pre = self.forward(x)
                err = o - t
                loss += err * err
                d_o = 2.0 * err * phi_d(o_pre) / n
                for j in range(4):
                    g_w2[j] += d_o * h[j]
                g_b2 += d_o
                for j in range(4):
                    d_h = d_o * self.w2[j] * phi_d(h_pre[j])
                    for i in range(3):
                        g_w1[j][i] += d_h * x[i]
                    g_b1[j] += d_h
            for j in range(4):
                for i in range(3):
                    self.w1[j][i] -= lr * g_w1[j][i]
                self.b1[j] -= lr * g_b1[j]
                self.w2[j] -= lr * g_w2[j]
            self.b2 -= lr * g_b2
            if ep % 50 == 0 or ep == epochs - 1:
                print(f"epoch {ep}: mse {loss / n:.4f}")

    def accuracy(self, X, y, threshold=0.35):
        """Sign accuracy on samples where |score| >= threshold, plus coverage."""
        correct = total = covered = 0
        for x, t in zip(X, y):
            o, _, _, _ = self.forward(x)
            if abs(o) >= threshold:
                covered += 1
                if (o > 0) == (t > 0) and t != 0:
                    correct += 1
                total += 1 if t != 0 else 0
        raw_correct = sum(1 for x, t in zip(X, y) if (self.forward(x)[0] > 0) == (t > 0) and t != 0)
        raw_total = sum(1 for t in y if t != 0)
        return {
            "thresholded_accuracy": (correct / total if total else 0.0),
            "thresholded_samples": total,
            "coverage": covered / len(X),
            "raw_sign_accuracy": raw_correct / raw_total if raw_total else 0.0,
        }


def q(v: float) -> int:
    return int(round(v * SCALE))


def main():
    rng = random.Random(1337)
    X, y = build_dataset(rng)
    print(f"dataset: {len(X)} windows")
    split = int(len(X) * 0.8)
    Xtr, ytr, Xte, yte = X[:split], y[:split], X[split:], y[split:]
    net = Net(rng)
    net.train(Xtr, ytr)
    print("train:", net.accuracy(Xtr, ytr))
    print("test: ", net.accuracy(Xte, yte))
    export = {
        "architecture": "3 -> 4 -> 1 MLP, activation phi(x) = x / (1 + |x|), features x10",
        "feature_scale": FEATURE_SCALE,
        "w1": [[q(v) for v in row] for row in net.w1],
        "b1": [q(v) for v in net.b1],
        "w2": [q(v) for v in net.w2],
        "b2": q(net.b2),
        "test_accuracy": net.accuracy(Xte, yte),
        "train_accuracy": net.accuracy(Xtr, ytr),
    }
    with open("model-weights.json", "w") as f:
        json.dump(export, f, indent=2)
    print("wrote model-weights.json")
    print("w1:", net.w1)
    print("b1:", net.b1)
    print("w2:", net.w2)
    print("b2:", net.b2)


if __name__ == "__main__":
    main()

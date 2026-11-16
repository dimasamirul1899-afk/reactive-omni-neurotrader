#!/usr/bin/env python3
"""Integer reference for NeuroNet.sol — same math, trunc-toward-zero division.
Generates exact test vectors for the Foundry tests."""
import json

SCALE = 10**18


def tdiv(a, b):
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def phi(x):
    return tdiv(x * SCALE, SCALE + abs(x))


with open("model-weights.json") as f:
    m = json.load(f)

W1 = m["w1"]
B1 = m["b1"]
W2 = m["w2"]
B2 = m["b2"]


def features(prices):
    p0, p1, p4 = prices[0], prices[1], prices[4]
    f1 = tdiv((p0 - p1) * 10 * SCALE, p1)
    f2 = tdiv((p0 - p4) * 10 * SCALE, p4)
    lo, hi = min(prices), max(prices)
    mean = sum(prices) // 8
    f3 = tdiv((hi - lo) * 10 * SCALE, mean)
    return [f1, f2, f3]


def predict(f):
    h = []
    for j in range(4):
        pre = tdiv(W1[j][0] * f[0] + W1[j][1] * f[1] + W1[j][2] * f[2], SCALE) + B1[j]
        h.append(phi(pre))
    pre = tdiv(W2[0] * h[0] + W2[1] * h[1] + W2[2] * h[2] + W2[3] * h[3], SCALE) + B2
    return phi(pre), h


def decide(score):
    if score >= 350_000_000_000_000_000:
        return 1
    if score <= -350_000_000_000_000_000:
        return 2
    return 0


# Windows: prices in USD x 1e8, newest first.
up = []
p = 3000_00000000
for i in range(8):
    up.append(p)
    p = p * 1005 // 1000
up = list(reversed(up))  # newest first = highest

down = []
p = 3000_00000000
for i in range(8):
    down.append(p)
    p = p * 995 // 1000
down = list(reversed(down))

flat = [3000_00000000 + ((i * 37) % 5 - 2) * 1000000 for i in range(8)]
flat = list(reversed(flat))

for name, w in [("UP", up), ("DOWN", down), ("FLAT", flat)]:
    f = features(w)
    score, h = predict(f)
    print(f"{name} window: {w}")
    print(f"{name} features: {f}")
    print(f"{name} hidden: {h}")
    print(f"{name} score: {score}  decision: {decide(score)}")
    print()

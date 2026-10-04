"""Train the net every bot starts from: an imitation of the hand-written bot.

    doom botdata <wad> 70 botdata.bin
    python harness/trainbot.py botdata.bin fixtures/bot0.net

botdata.bin is the script's decisions: 38 signed bytes each, 32 senses then 6
decisions. The net is bot.mach's: 32 inputs, 24 hidden units clipped to
0..127, 6 outputs clipped to -127..127, weights in 64ths as signed bytes and
biases as signed bytes. It is trained in floating point with the same
clipping, rounded to bytes, and then judged as the game will run it, in
integers, on decisions it was not trained on.
"""
import sys

import numpy as np

INPUTS, HIDDEN, OUTPUTS = 32, 24, 6
NAMES = ["forward", "side", "turn", "fire", "use", "switch"]


def integer_forward(q1, b1, q2, b2, x):
    """Exactly bot.forward: sums in 64ths, shifted down (floor), clipped."""
    hidden = np.clip((x @ q1.T + b1 * 64) >> 6, 0, 127)
    return np.clip((hidden @ q2.T + b2 * 64) >> 6, -127, 127)


def main():
    data = np.fromfile(sys.argv[1], dtype=np.int8).reshape(-1, 38)
    rng = np.random.default_rng(1)
    rng.shuffle(data)
    held = len(data) // 10
    test, train = data[:held], data[held:]
    x = train[:, :32].astype(np.float32)
    y = train[:, 32:].astype(np.float32)

    w1 = rng.normal(0, 0.05, (HIDDEN, INPUTS)).astype(np.float32)
    b1 = np.full(HIDDEN, 10, dtype=np.float32)
    w2 = rng.normal(0, 0.05, (OUTPUTS, HIDDEN)).astype(np.float32)
    b2 = np.zeros(OUTPUTS, dtype=np.float32)
    params = [w1, b1, w2, b2]
    # Adam
    m = [np.zeros_like(p) for p in params]
    v = [np.zeros_like(p) for p in params]
    rates = [0.002, 0.2, 0.002, 0.2]
    step = 0
    batch = 512
    epochs = 40
    for epoch in range(epochs):
        order = rng.permutation(len(x))
        total = 0.0
        for start in range(0, len(x) - batch + 1, batch):
            idx = order[start:start + batch]
            xb, yb = x[idx], y[idx]
            pre = xb @ w1.T + b1
            h = np.clip(pre, 0, 127)
            raw = h @ w2.T + b2
            out = np.clip(raw, -127, 127)
            err = (out - yb) / 127
            total += float((err ** 2).mean())
            # back through the clips: no gradient where clipped
            g_raw = err * ((raw > -127) & (raw < 127)) / batch
            g_w2 = g_raw.T @ h
            g_b2 = g_raw.sum(0)
            g_h = g_raw @ w2
            g_pre = g_h * ((pre > 0) & (pre < 127))
            g_w1 = g_pre.T @ xb
            g_b1 = g_pre.sum(0)
            step += 1
            decay = 0.5 ** (epoch / 10)
            for p, g, mi, vi, rate in zip(params, [g_w1, g_b1, g_w2, g_b2], m, v, rates):
                mi *= 0.9
                mi += 0.1 * g
                vi *= 0.999
                vi += 0.001 * g * g
                p -= rate * decay * (mi / (1 - 0.9 ** step)) / (np.sqrt(vi / (1 - 0.999 ** step)) + 1e-8)
            # what a byte can hold: weights in 64ths, biases whole
            np.clip(w1, -2, 127 / 64, out=w1)
            np.clip(w2, -2, 127 / 64, out=w2)
            np.clip(b1, -128, 127, out=b1)
            np.clip(b2, -128, 127, out=b2)
        if epoch % 5 == 4 or epoch == epochs - 1:
            print("epoch %2d  loss %.4f" % (epoch + 1, total / (len(x) // batch)))

    q1 = np.clip(np.rint(w1 * 64), -128, 127).astype(np.int32)
    q2 = np.clip(np.rint(w2 * 64), -128, 127).astype(np.int32)
    c1 = np.clip(np.rint(b1), -128, 127).astype(np.int32)
    c2 = np.clip(np.rint(b2), -128, 127).astype(np.int32)

    tx = test[:, :32].astype(np.int32)
    ty = test[:, 32:].astype(np.int32)
    out = integer_forward(q1, c1, q2, c2, tx)
    print("as the game runs it, on %d held-out decisions:" % len(tx))
    for k, name in enumerate(NAMES):
        if k < 3:
            print("  %-8s mean error %5.1f of 127" % (name, np.abs(out[:, k] - ty[:, k]).mean()))
        else:
            agree = ((out[:, k] > 0) == (ty[:, k] > 0)).mean()
            pressed = (ty[:, k] > 0).mean()
            caught = ((out[:, k] > 0) & (ty[:, k] > 0)).sum() / max(1, (ty[:, k] > 0).sum())
            print("  %-8s agrees %5.1f%%  (pressed %4.1f%% of the time; %5.1f%% of presses caught)"
                  % (name, 100 * agree, 100 * pressed, 100 * caught))

    # the file: input weights by hidden unit, hidden biases, output weights
    # by output, output biases, as bot.forward reads them
    net = np.concatenate([q1.reshape(-1), c1, q2.reshape(-1), c2]).astype(np.int8)
    assert len(net) == INPUTS * HIDDEN + HIDDEN + HIDDEN * OUTPUTS + OUTPUTS
    net.tofile(sys.argv[2])
    print("wrote %s, %d bytes" % (sys.argv[2], len(net)))


main()

#!/usr/bin/env python3
"""Resample attack clips so the 180° arm snap is spread over 5 intervals,
windup is larger, and the final hold is 0.35 s. Shenyan and 药行打手.
Does not touch mesh or other animations. Writes in place after a backup.
"""
import json, math, shutil, struct, pathlib, copy

ROOT = pathlib.Path("/workspace/godogen-shanhe-fe/assets/glb")
TARGETS = ["shenyan.glb", "yaoxing_dashou.glb"]
BACKUP = pathlib.Path("/tmp/glb_backup_attack_resample")
FPS = 24
# New timeline (seconds)
WINDUP_END = 0.32
STRIKE_END = 0.56   # 5 intervals of 0.048 s for the snap
FOLLOW_END = 0.95
HOLD = 0.35
TOTAL = FOLLOW_END + HOLD  # 1.30
# Old clip: windup 0-0.333, snap 0.333-0.375, follow 0.375-0.916, hold 0.916-1.208
OLD_WINDUP = 0.333
OLD_SNAP = 0.375
OLD_FOLLOW = 0.9167

def load_glb(path):
    data = path.read_bytes()
    chunk_len = int.from_bytes(data[12:16], "little")
    js = json.loads(data[20:20 + chunk_len])
    bin_start = 20 + chunk_len
    blob = bytearray(data[bin_start + 8: bin_start + 8 + int.from_bytes(data[bin_start:bin_start+4], "little")])
    return js, blob

def acc_values(js, blob, acc_i):
    acc = js["accessors"][acc_i]
    bv = js["bufferViews"][acc["bufferView"]]
    off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    n, typ, ct = acc["count"], acc["type"], acc["componentType"]
    fmt = {5126: "f", 5123: "H", 5125: "I"}[ct]
    comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[typ]
    stride = bv.get("byteStride") or comps * struct.calcsize(fmt)
    out = []
    for i in range(n):
        vals = struct.unpack_from(fmt * comps, blob, off + i * stride)
        out.append(vals[0] if comps == 1 else vals)
    return out, acc

def qdot(a, b):
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2] + a[3]*b[3]

def qnorm(q):
    n = math.sqrt(qdot(q, q)) or 1.0
    return tuple(c / n for c in q)

def slerp(q0, q1, t):
    q0, q1 = qnorm(q0), qnorm(q1)
    dot = qdot(q0, q1)
    if dot < 0:
        q1 = tuple(-c for c in q1)
        dot = -dot
    if dot > 0.9995:
        return qnorm(tuple(q0[i] + t * (q1[i] - q0[i]) for i in range(4)))
    # allow t slightly outside [0,1] for windup in the opposite direction
    theta = math.acos(max(-1.0, min(1.0, dot)))
    if abs(theta) < 1e-6:
        return q0
    s0 = math.sin((1 - t) * theta) / math.sin(theta)
    s1 = math.sin(t * theta) / math.sin(theta)
    return qnorm(tuple(s0 * q0[i] + s1 * q1[i] for i in range(4)))

def lerp(a, b, t):
    if isinstance(a, (int, float)):
        return a + t * (b - a)
    return tuple(a[i] + t * (b[i] - a[i]) for i in range(len(a)))

def sample_channel(times, values, t, is_quat):
    if t <= times[0]:
        return values[0]
    if t >= times[-1]:
        return values[-1]
    for i in range(1, len(times)):
        if t <= times[i]:
            u = (t - times[i-1]) / (times[i] - times[i-1] or 1e-8)
            if is_quat:
                return slerp(values[i-1], values[i], u)
            return lerp(values[i-1], values[i], u)
    return values[-1]

def map_time(told, times, values, is_quat):
    """Map an old-clip time to a pose, with amplified windup and spread snap."""
    rest = values[0]
    # identify snap pose (first large change after windup)
    snap_i = 0
    for i in range(1, len(times)):
        if times[i] >= OLD_SNAP - 1e-4:
            snap_i = i
            break
    snap_q = values[snap_i]
    # later unique poses
    follow_t = min(t for t in times if t >= OLD_FOLLOW - 1e-3) if any(t >= OLD_FOLLOW - 1e-3 for t in times) else times[-1]
    follow_p = sample_channel(times, values, follow_t, is_quat)

    def pose_at_old(t):
        return sample_channel(times, values, t, is_quat)

    # Did this channel actually wind up before the snap?
    pre = pose_at_old(OLD_WINDUP)
    if is_quat:
        moved_pre = (1 - abs(qdot(qnorm(rest), qnorm(pre)))) > 1e-4
    else:
        if isinstance(rest, tuple):
            moved_pre = math.sqrt(sum((rest[i]-pre[i])**2 for i in range(len(rest)))) > 1e-5
        else:
            moved_pre = abs(rest - pre) > 1e-5

    if told <= WINDUP_END:
        u = told / WINDUP_END
        # ease-in
        e = u * u * (3 - 2 * u)
        if moved_pre:
            # amplify existing windup (about 2.4x the original deviation)
            src = pose_at_old(e * OLD_WINDUP)
            if is_quat:
                # go 2.4x from rest toward src
                return slerp(rest, src, 2.4 * e if e > 0 else 0.0) if e > 0 else rest
            if isinstance(rest, tuple):
                extra = tuple(rest[i] + 2.4 * (src[i] - rest[i]) for i in range(len(rest)))
                return lerp(rest, extra, e)
            return rest + 2.4 * (src - rest) * e
        else:
            # invent a pull-back: opposite 18% of rest->snap, then return toward rest
            # rise to 0.7 then come back a little so the strike has a coil
            coil = math.sin(e * math.pi)  # 0..1..0, peak mid windup? Wait we want end of windup coiled
            coil = e  # fully coiled at windup end
            if is_quat:
                return slerp(rest, snap_q, -0.20 * coil)
            if isinstance(rest, tuple):
                return tuple(rest[i] + (-0.20 * coil) * (snap_q[i] - rest[i]) for i in range(len(rest)))
            return rest + (-0.20 * coil) * (snap_q - rest)
    if told <= STRIKE_END:
        u = (told - WINDUP_END) / (STRIKE_END - WINDUP_END)
        e = u * u * (3 - 2 * u)
        # start from the coiled windup-end pose
        start = map_time(WINDUP_END, times, values, is_quat)
        if is_quat:
            return slerp(start, snap_q, e)
        return lerp(start, snap_q, e)
    if told <= FOLLOW_END:
        u = (told - STRIKE_END) / (FOLLOW_END - STRIKE_END)
        e = u * u * (3 - 2 * u)
        # interpolate snap -> original follow/recover pose
        if is_quat:
            return slerp(snap_q, follow_p, e)
        return lerp(snap_q, follow_p, e)
    return follow_p


def pad4(b, pad=b"\x00"):
    return b + pad * ((4 - len(b) % 4) % 4)

def write_glb(path, js, blobs):
    # blobs is a single bytearray for buffer 0
    bin_bytes = pad4(bytes(blobs), b"\x00")
    js["buffers"][0]["byteLength"] = len(bin_bytes)
    # JSON chunk must be padded with spaces, not NULs.
    json_bytes = pad4(json.dumps(js, separators=(",", ":"), ensure_ascii=False).encode("utf-8"), b" ")
    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    out = bytearray()
    out += b"glTF" + struct.pack("<II", 2, total)
    out += struct.pack("<I", len(json_bytes)) + b"JSON" + json_bytes
    out += struct.pack("<I", len(bin_bytes)) + b"BIN\x00" + bin_bytes
    path.write_bytes(out)

def resample_one(path):
    js, blob = load_glb(path)
    anim = next(a for a in js["animations"] if a["name"] == "attack")
    nodes = js["nodes"]
    # new times: 24 fps from 0 to TOTAL inclusive
    nkeys = int(round(TOTAL * FPS)) + 1
    new_times = [i / FPS for i in range(nkeys)]
    # we will append new buffer data
    new_blob = bytearray(blob)
    # avoid rewriting same sampler twice
    done = set()
    changed = 0
    for ch in anim["channels"]:
        samp_i = ch["sampler"]
        if samp_i in done:
            continue
        done.add(samp_i)
        samp = anim["samplers"][samp_i]
        times, _ = acc_values(js, blob, samp["input"])
        values, acc_v = acc_values(js, blob, samp["output"])
        path_t = ch["target"]["path"]
        is_quat = path_t == "rotation"
        # skip scale? still resample for consistency
        new_vals = [map_time(t, times, values, is_quat) for t in new_times]
        # write new input
        t_bytes = b"".join(struct.pack("<f", t) for t in new_times)
        off_t = len(new_blob)
        new_blob += t_bytes
        # output
        if is_quat or (isinstance(values[0], tuple) and len(values[0]) == 3):
            comps = 4 if is_quat else 3
            v_bytes = b"".join(struct.pack("<" + "f"*comps, *v) for v in new_vals)
        else:
            v_bytes = b"".join(struct.pack("<f", float(v)) for v in new_vals)
        off_v = len(new_blob)
        new_blob += v_bytes
        # new bufferViews + accessors
        bv_t = {"buffer": 0, "byteOffset": off_t, "byteLength": len(t_bytes)}
        bv_v = {"buffer": 0, "byteOffset": off_v, "byteLength": len(v_bytes)}
        js["bufferViews"].append(bv_t)
        bvi_t = len(js["bufferViews"]) - 1
        js["bufferViews"].append(bv_v)
        bvi_v = len(js["bufferViews"]) - 1
        acc_t = {"bufferView": bvi_t, "componentType": 5126, "count": len(new_times),
                 "type": "SCALAR", "min": [new_times[0]], "max": [new_times[-1]]}
        typ = acc_v["type"]
        acc_new_v = {"bufferView": bvi_v, "componentType": 5126, "count": len(new_vals), "type": typ}
        js["accessors"].append(acc_t)
        ai_t = len(js["accessors"]) - 1
        js["accessors"].append(acc_new_v)
        ai_v = len(js["accessors"]) - 1
        samp["input"] = ai_t
        samp["output"] = ai_v
        samp["interpolation"] = "LINEAR"
        changed += 1
    write_glb(path, js, new_blob)
    return changed, new_times[-1], nkeys

def main():
    BACKUP.mkdir(parents=True, exist_ok=True)
    for name in TARGETS:
        src = ROOT / name
        if not src.exists():
            print("MISSING", src)
            continue
        bak = BACKUP / name
        if not bak.exists():
            shutil.copy2(src, bak)
        n, end, keys = resample_one(src)
        print(f"{name}: rewrote {n} attack samplers, length={end:.4f}s keys={keys}")

if __name__ == "__main__":
    main()

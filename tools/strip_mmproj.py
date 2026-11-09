"""Makes an audio-only copy of a Gemma 4 multimodal projector (mmproj) GGUF: drops the image ("v.") tensors and
marks the file as having no vision encoder, so the phone loads only the audio encoder.

Usage: python3 tools/strip_mmproj.py <in.gguf> <out.gguf>
Pure Python (no gguf package needed). Keeps tensor data byte-for-byte.
"""
import struct
import sys

GGUF_TYPES = {0: "B", 1: "b", 2: "H", 3: "h", 4: "I", 5: "i", 6: "f", 7: "?", 10: "Q", 11: "q", 12: "d"}


def main(src, dst):
    f = open(src, "rb")

    def read(fmt):
        size = struct.calcsize("<" + fmt)
        return struct.unpack("<" + fmt, f.read(size))[0]

    def read_str():
        n = read("Q")
        return f.read(n)

    def read_value(t):
        if t == 8:
            return read_str()
        if t == 9:
            at = read("I")
            n = read("Q")
            return (at, [read_value(at) for _ in range(n)])
        return read(GGUF_TYPES[t])

    assert f.read(4) == b"GGUF"
    version = read("I")
    n_tensors = read("Q")
    n_kv = read("Q")
    kvs = []
    alignment = 32
    for _ in range(n_kv):
        key = read_str()
        t = read("I")
        value = read_value(t)
        if key == b"general.alignment":
            alignment = value
        kvs.append([key, t, value])
    tensors = []
    for _ in range(n_tensors):
        name = read_str()
        nd = read("I")
        dims = [read("Q") for _ in range(nd)]
        typ = read("I")
        offset = read("Q")
        tensors.append((name, dims, typ, offset))
    data_start = (f.tell() + alignment - 1) // alignment * alignment

    # Each tensor's byte length = distance to the next offset (tensors are stored in offset order).
    f.seek(0, 2)
    end = f.tell()
    ordered = sorted(tensors, key=lambda x: x[3])
    lengths = {}
    for i, (name, _, _, off) in enumerate(ordered):
        nxt = ordered[i + 1][3] if i + 1 < len(ordered) else end - data_start
        lengths[name] = nxt - off

    kept = [t for t in tensors if not t[0].startswith(b"v.")]
    for kv in kvs:
        if kv[0] == b"clip.has_vision_encoder":
            kv[2] = False
    kvs = [kv for kv in kvs if not kv[0].startswith(b"clip.vision.")]

    def write_str(out, s):
        out.write(struct.pack("<Q", len(s)))
        out.write(s)

    def write_value(out, t, v):
        if t == 8:
            write_str(out, v)
        elif t == 9:
            at, items = v
            out.write(struct.pack("<IQ", at, len(items)))
            for item in items:
                write_value(out, at, item)
        else:
            out.write(struct.pack("<" + GGUF_TYPES[t], v))

    out = open(dst, "wb")
    out.write(b"GGUF")
    out.write(struct.pack("<IQQ", version, len(kept), len(kvs)))
    for key, t, v in kvs:
        write_str(out, key)
        out.write(struct.pack("<I", t))
        write_value(out, t, v)
    new_offsets = {}
    offset = 0
    for name, _, _, _ in kept:
        new_offsets[name] = offset
        offset += (lengths[name] + alignment - 1) // alignment * alignment
    for name, dims, typ, _ in kept:
        write_str(out, name)
        out.write(struct.pack("<I", len(dims)))
        for d in dims:
            out.write(struct.pack("<Q", d))
        out.write(struct.pack("<IQ", typ, new_offsets[name]))
    pad = (alignment - out.tell() % alignment) % alignment
    out.write(b"\0" * pad)
    for name, _, _, off in kept:
        f.seek(data_start + off)
        out.write(f.read(lengths[name]))
        out.write(b"\0" * ((alignment - lengths[name] % alignment) % alignment))
    out.close()
    print(f"kept {len(kept)} of {len(tensors)} tensors -> {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

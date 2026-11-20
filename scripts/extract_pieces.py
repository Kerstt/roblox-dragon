"""Pull named meshes out of a (huge) Roblox Studio glTF export into a small GLB.

Studio's File > Export as glTF writes the whole place. This keeps only the
pieces you ask for, ready for File > Import, which uploads each mesh.

usage:
  python extract_pieces.py <export.gltf> <out.glb> <ParentNode>:<Piece>,<Piece>,... [<ParentNode>:...]

Each piece is looked up among the descendants of its parent node (for example a
dragon's model) and written as "<ParentNode>__<Piece>", so pieces from several
models can share one file (DragonMeshSplitter.Adopt takes the prefix).

Only geometry is kept (positions, normals, UVs, indices). Materials and textures
are dropped: the pieces reuse their existing textures on Roblox. Every piece is a
root node with no transform.
"""
import base64
import json
import re
import struct
import sys

src, out_path, *groups = sys.argv[1:]
requests = []
for g in groups:
    parent, _, names = g.partition(":")
    requests.append((parent, [n for n in names.split(",") if n]))

raw = open(src, "rb").read()

# Replace every embedded data URI with a short token so the JSON is small to parse.
spans = []
parts = []
last = 0
for m in re.finditer(rb'"uri"\s*:\s*"data:[^,"]*,', raw):
    start = m.end()
    end = raw.index(b'"', start)
    parts.append(raw[last:m.start()])
    parts.append(b'"uri":"@%d"' % len(spans))
    spans.append((start, end))
    last = end + 1
parts.append(raw[last:])
doc = json.loads(b"".join(parts))

decoded = {}


def buffer_bytes(index):
    if index not in decoded:
        uri = doc["buffers"][index]["uri"]
        if not uri.startswith("@"):
            raise SystemExit("external buffer files are not supported: " + uri)
        s, e = spans[int(uri[1:])]
        decoded[index] = base64.b64decode(raw[s:e])
    return decoded[index]


COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
FORMATS = {5126: "f", 5125: "I", 5123: "H", 5121: "B"}
SIZES = {5126: 4, 5125: 4, 5123: 2, 5121: 1}


def read_accessor(index):
    acc = doc["accessors"][index]
    view = doc["bufferViews"][acc["bufferView"]]
    data = buffer_bytes(view["buffer"])
    n = COMPONENTS[acc["type"]]
    size = SIZES[acc["componentType"]]
    stride = view.get("byteStride") or n * size
    base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    fmt = "<" + FORMATS[acc["componentType"]] * n
    return [struct.unpack_from(fmt, data, base + i * stride) for i in range(acc["count"])]


nodes = doc["nodes"]


def find_pieces(parent_name, pieces):
    parent = next((i for i, nd in enumerate(nodes) if nd.get("name") == parent_name), None)
    if parent is None:
        raise SystemExit("no node named " + parent_name)
    wanted = {}
    stack = [parent]
    while stack:
        i = stack.pop()
        nd = nodes[i]
        if nd.get("name") in pieces and nd["name"] not in wanted:
            # the mesh may sit on this node or on a direct child
            mesh = nd.get("mesh")
            if mesh is None:
                for c in nd.get("children", []):
                    if nodes[c].get("mesh") is not None:
                        mesh = nodes[c]["mesh"]
                        break
            if mesh is not None:
                wanted[nd["name"]] = mesh
        stack.extend(nd.get("children", []))
    missing = [p for p in pieces if p not in wanted]
    if missing:
        raise SystemExit("pieces not found under %s: %s" % (parent_name, missing))
    return wanted


binary = bytearray()
out = {"asset": {"version": "2.0", "generator": "extract_pieces.py"}, "buffers": [], "bufferViews": [],
       "accessors": [], "meshes": [], "nodes": [], "scenes": [{"nodes": []}], "scene": 0}


def add_view(blob, target):
    while len(binary) % 4:
        binary.append(0)
    out["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(blob), "target": target})
    binary.extend(blob)
    return len(out["bufferViews"]) - 1


def add_float_accessor(rows, kind):
    n = COMPONENTS[kind]
    blob = b"".join(struct.pack("<" + "f" * n, *r) for r in rows)
    acc = {"bufferView": add_view(blob, 34962), "componentType": 5126, "count": len(rows), "type": kind}
    if kind == "VEC3":
        acc["min"] = [min(r[k] for r in rows) for k in range(3)]
        acc["max"] = [max(r[k] for r in rows) for k in range(3)]
    out["accessors"].append(acc)
    return len(out["accessors"]) - 1


report = []
for parent_name, pieces in requests:
    wanted = find_pieces(parent_name, pieces)
    for name in pieces:
        mesh = doc["meshes"][wanted[name]]
        prims = []
        tris = 0
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            new_attrs = {"POSITION": add_float_accessor(read_accessor(attrs["POSITION"]), "VEC3")}
            if "NORMAL" in attrs:
                new_attrs["NORMAL"] = add_float_accessor(read_accessor(attrs["NORMAL"]), "VEC3")
            if "TEXCOORD_0" in attrs:
                new_attrs["TEXCOORD_0"] = add_float_accessor(read_accessor(attrs["TEXCOORD_0"]), "VEC2")
            idx = [r[0] for r in read_accessor(prim["indices"])]
            tris += len(idx) // 3
            blob = struct.pack("<%dI" % len(idx), *idx)
            out["accessors"].append({"bufferView": add_view(blob, 34963), "componentType": 5125, "count": len(idx), "type": "SCALAR"})
            prims.append({"attributes": new_attrs, "indices": len(out["accessors"]) - 1, "mode": 4})
        full = parent_name + "__" + name
        out["meshes"].append({"name": full, "primitives": prims})
        out["nodes"].append({"name": full, "mesh": len(out["meshes"]) - 1})
        out["scenes"][0]["nodes"].append(len(out["nodes"]) - 1)
        report.append("%s: %d triangles" % (full, tris))

while len(binary) % 4:
    binary.append(0)
out["buffers"].append({"byteLength": len(binary)})
js = json.dumps(out, separators=(",", ":")).encode()
while len(js) % 4:
    js += b" "
glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary))
glb += struct.pack("<II", len(js), 0x4E4F534A) + js
glb += struct.pack("<II", len(binary), 0x004E4942) + bytes(binary)
open(out_path, "wb").write(glb)
print("\n".join(report))
print("wrote %s (%d bytes, %d pieces)" % (out_path, len(glb), len(out["nodes"])))

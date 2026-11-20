"""Copies every Script / LocalScript / ModuleScript out of a Roblox XML place file
(.rbxlx, made with File > Save to File As in Studio) into the repo, using the same
folder layout Rojo uses:

    <out>/<Service>/<Folder>/.../<Name>.luau          ModuleScript
    <out>/<Service>/.../<Name>.server.luau            Script
    <out>/<Service>/.../<Name>.client.luau            LocalScript

It only writes files; it never deletes. If you deleted a script in Studio, delete
its file here too. Reads the place as a stream, so big places are fine.

Usage: python -I scripts/extract_scripts.py <place.rbxlx> <out_dir>
"""
import os
import sys
import xml.etree.ElementTree as ET

KEEP = {"ServerScriptService", "ServerStorage", "ReplicatedStorage", "StarterPlayer", "StarterGui", "ReplicatedFirst", "Workspace"}
SCRIPT_CLASSES = {"Script": ".server.luau", "LocalScript": ".client.luau", "ModuleScript": ".luau"}


def safe(name: str) -> str:
    return "".join(c if c.isalnum() or c in " _-." else "_" for c in name).strip() or "_"


def main(place: str, out: str) -> None:
    out = os.path.abspath(out)
    stack = []  # one [className, name, element] per open <Item>
    written = []
    for event, elem in ET.iterparse(place, events=("start", "end")):
        if event == "start" and elem.tag == "Item":
            stack.append([elem.get("class"), None, elem])
        elif event == "end" and elem.tag == "string" and stack:
            # <Properties><string name="Name"> comes before an Item's children.
            if elem.get("name") == "Name" and stack[-1][1] is None:
                stack[-1][1] = elem.text or ""
        elif event == "end" and elem.tag == "Item":
            cls, name, item = stack.pop()
            parents = [n for (_, n, _) in stack]
            if cls in SCRIPT_CLASSES and parents and parents[0] in KEEP and all(parents):
                source = ""
                props = item.find("Properties")
                if props is not None:
                    for p in props:
                        if p.get("name") == "Source":
                            source = p.text or ""
                rel = os.path.join(*[safe(n) for n in parents], safe(name or cls) + SCRIPT_CLASSES[cls])
                target = os.path.abspath(os.path.join(out, rel))
                if not target.startswith(out + os.sep):
                    raise ValueError("bad path " + rel)
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with open(target, "w", encoding="utf-8", newline="\n") as f:
                    f.write(source.replace("\r\n", "\n"))
                written.append(rel)
            item.clear()  # free memory as we go
    for rel in sorted(written):
        print("  " + rel)
    print(f"{len(written)} scripts copied into {out}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])

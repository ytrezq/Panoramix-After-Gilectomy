#!/usr/bin/env python3
"""A corpus of deployed bytecode from npm packages that ship compiled
artifacts (OpenZeppelin, Uniswap, Aave, Gnosis Safe, 0x...).

    npm pack @openzeppelin/contracts@4.9.6 ...    # the tarballs, in DIR
    corpus_from_npm.py DIR OUT

Every artifact with a runtime bytecode (truffle's deployedBytecode, solc's
evm.deployedBytecode.object) becomes OUT/<package>_<contract>.hex, the
library placeholders replaced by zeros and the duplicates dropped."""
import glob, hashlib, json, os, re, sys, tarfile

def runtime_of(j):
    for path in (("deployedBytecode",), ("evm", "deployedBytecode", "object"),
                 ("compilerOutput", "evm", "deployedBytecode", "object"),
                 ("compiledOutput", "evm", "deployedBytecode", "object")):
        v = j
        for k in path:
            v = v.get(k) if isinstance(v, dict) else None
        if isinstance(v, dict):
            v = v.get("object")
        if isinstance(v, str):
            return v
    return None

if __name__ == "__main__":
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    seen, count = set(), 0
    for tgz in sorted(glob.glob(os.path.join(src, "*.tgz"))):
        prefix = re.sub(r"[^a-z0-9]+", "", os.path.basename(tgz).split("-")[0])[:6] + \
            re.sub(r"[^0-9]", "", os.path.basename(tgz))[:3]
        with tarfile.open(tgz) as tar:
            for m in tar.getmembers():
                if not m.name.endswith(".json") or not m.isfile():
                    continue
                try:
                    j = json.load(tar.extractfile(m))
                except Exception:
                    continue
                code = runtime_of(j) if isinstance(j, dict) else None
                if not code:
                    continue
                code = code[2:] if code.startswith("0x") else code
                code = re.sub(r"__\$[0-9a-f]{34}\$__|__[0-9A-Za-z$:._]{36}__", "0" * 40, code)
                if len(code) < 20 or not re.fullmatch(r"[0-9a-fA-F]+", code):
                    continue
                h = hashlib.sha1(code.encode()).hexdigest()
                if h in seen:
                    continue
                seen.add(h)
                name = "%s_%s" % (prefix, os.path.basename(m.name)[:-5])
                path, i = os.path.join(out, name + ".hex"), 2
                while os.path.exists(path):
                    path, i = os.path.join(out, "%s_%d.hex" % (name, i)), i + 1
                open(path, "w").write(code)
                count += 1
    print(count, "contracts")

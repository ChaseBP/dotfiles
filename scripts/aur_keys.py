#!/usr/bin/env python3
"""Pre-import the PGP keys AUR packages will ask for, over plain HTTPS.

paru imports `validpgpkeys` through gpg's dirmngr, which on some networks just
times out ("keyserver receive failed: Server indicated a failure") — and with
--noconfirm that aborts the whole install. Found on the KDE VM test: the
papirus-folders key, pulled in by `caelestia install`. curl reaches the same
keyservers fine, so fetch the keys ourselves and `gpg --import` them first.

    aur_keys.py [--caelestia COMPONENTS] PKG...

Walks the AUR dependency tree of PKG... (plus, with --caelestia, the packages of
those Caelestia dots components), reads each AUR package's .SRCINFO, and imports
every missing key. Best effort: prints what it did, never fails the install.
"""
import argparse
import json
import re
import subprocess
import tomllib
import urllib.parse
import urllib.request

AUR = "https://aur.archlinux.org"
MANIFEST = "https://raw.githubusercontent.com/caelestia-dots/caelestia/main/manifest.toml"
KEYSERVERS = (
    "https://keyserver.ubuntu.com/pks/lookup?op=get&options=mr&search=0x{}",
    "https://keys.openpgp.org/vks/v1/by-fingerprint/{}",
)


def get(url, timeout=30):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read()


def strip_version(dep):
    return re.split(r"[<>=]", dep, maxsplit=1)[0]


_REPO = None


def in_repos(names):
    """Names (or provided names) resolvable from the sync repos."""
    global _REPO
    if _REPO is None:  # one listing instead of a pacman call per dependency
        _REPO = set(subprocess.run(["pacman", "-Slq"], capture_output=True, text=True).stdout.split())
    found = {n for n in names if n in _REPO}
    for name in set(names) - found:  # virtual names (sh, libfoo.so, ...) via provides
        r = subprocess.run(["pacman", "-Sp", "--print-format", "%n", name], capture_output=True, text=True)
        if r.returncode == 0:
            found.add(name)
    return found


def caelestia_packages(components):
    manifest = tomllib.loads(get(MANIFEST).decode())
    pkgs = list(manifest.get("packages", []))
    for comp in manifest.get("components", []):
        if comp["name"] in components:
            pkgs += [p for p in comp.get("packages", []) if not p.startswith("local:")]
    return pkgs


def aur_tree(roots):
    """{pkgname: pkgbase} for every AUR package reachable from roots."""
    seen, todo, aur = set(), set(roots), {}
    while todo:
        batch = sorted(todo - seen)
        seen |= set(batch)
        todo = set()
        candidates = sorted(set(batch) - in_repos(batch))
        if not candidates:
            continue
        query = "&".join("arg[]=" + urllib.parse.quote(n) for n in candidates)
        results = json.loads(get(f"{AUR}/rpc/v5/info?{query}"))["results"]
        for r in results:
            aur[r["Name"]] = r["PackageBase"]
            for key in ("Depends", "MakeDepends", "CheckDepends"):
                todo |= {strip_version(d) for d in r.get(key, [])}
    return aur


def have_key(fpr):
    return subprocess.run(["gpg", "--list-keys", fpr], capture_output=True).returncode == 0


def import_key(fpr):
    for url in KEYSERVERS:
        try:
            data = get(url.format(fpr))
        except OSError:
            continue
        if subprocess.run(["gpg", "--import"], input=data, capture_output=True).returncode == 0 and have_key(fpr):
            return True
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--caelestia", default="", help="comma-separated dots components")
    ap.add_argument("packages", nargs="*")
    args = ap.parse_args()

    roots = list(args.packages)
    if args.caelestia:
        try:
            roots += caelestia_packages(set(args.caelestia.split(",")))
        except (OSError, ValueError) as e:
            print(f"   (could not read Caelestia's manifest: {e})")
    try:
        aur = aur_tree(roots)
    except (OSError, ValueError) as e:
        print(f"   (could not query the AUR: {e}) — paru will import keys itself")
        return

    keys = {}
    for base in sorted(set(aur.values())):
        try:
            srcinfo = get(f"{AUR}/cgit/aur.git/plain/.SRCINFO?h={urllib.parse.quote(base)}").decode()
        except OSError:
            continue
        for fpr in re.findall(r"^\s*validpgpkeys = ([0-9A-Fa-f]+)", srcinfo, re.M):
            keys.setdefault(fpr.upper(), base)

    print(f"   {len(aur)} AUR package(s), {len(keys)} signing key(s)")
    for fpr, base in sorted(keys.items(), key=lambda kv: kv[1]):
        if have_key(fpr):
            continue
        ok = import_key(fpr)
        print(f"   {'imported' if ok else 'COULD NOT import'} {fpr} ({base})")


if __name__ == "__main__":
    main()

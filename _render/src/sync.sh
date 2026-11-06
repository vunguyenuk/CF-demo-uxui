#!/bin/bash
# usage: sync.sh <tgz in _sync>  — overwrite files in place (deletes are blocked in this folder)
B="$(cd "$(dirname "$0")/.." && pwd)"; S=$B/ChargeFuzeApp/ChargeFuze; T=$(mktemp -d)
tar xzf "$B/_sync/$1" -C "$T"
cd "$T" && find . -type f | while read f; do mkdir -p "$S/$(dirname "$f")"; cmp -s "$f" "$S/$f" || { cat "$f" > "$S/$f"; echo "updated $f"; }; done

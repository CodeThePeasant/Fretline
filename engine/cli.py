"""One request per process. JSON Lines on stdout; diagnostics on stderr."""
import argparse
import json
import os
import sys
from pathlib import Path

# Keep JIT cache writable even when running inside a read-only .app bundle.
cache = Path.home() / "Library" / "Caches" / "GuitarTab" / "numba"
cache.mkdir(parents=True, exist_ok=True)
os.environ.setdefault("NUMBA_CACHE_DIR", str(cache))


def emit(kind, **payload):
    print(json.dumps(dict(type=kind, **payload), ensure_ascii=False, allow_nan=False), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        from guitartab.transcribe import analyze
        result = analyze(args.source, args.output, lambda value, message: emit("progress", value=value, message=message))
        emit("result", result=result)
    except Exception as error:
        emit("error", message=str(error))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

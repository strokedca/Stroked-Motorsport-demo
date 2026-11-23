"""Build the reproducible Windows delivery ZIP; no network or owner data."""
from __future__ import annotations

import argparse
import codecs
import hashlib
from pathlib import Path
import zipfile

VERSION = "1.8"
ROOT_NAME = f"Stroked-Local-Website-Restore-v{VERSION}"


def windows_script_bytes(raw: bytes) -> bytes:
    text = raw.decode("utf-8").lstrip("\ufeff")
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return codecs.BOM_UTF8 + text.replace("\n", "\r\n").encode("utf-8")


def build(source: Path, output: Path) -> str:
    source = source.resolve()
    output = output.resolve()
    if source in output.parents:
        raise ValueError("Output ZIP must be outside the source folder")
    # Path's default ordering differs on Windows and Linux. Choose one
    # explicit order so the tested ZIP hash identifies the delivered bytes.
    files = sorted(
        (p for p in source.rglob("*") if p.is_file()),
        key=lambda p: (p.relative_to(source).as_posix().casefold(), p.relative_to(source).as_posix()),
    )
    if not files or not (source / "Restore-Local-Website.ps1").is_file():
        raise ValueError("Recovery package source is incomplete")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_STORED) as archive:
        for path in files:
            if path.is_symlink():
                raise ValueError("Package sources must be regular files")
            rel = path.relative_to(source).as_posix()
            info = zipfile.ZipInfo(f"{ROOT_NAME}/{rel}", (2026, 11, 22, 0, 0, 0))
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            data = path.read_bytes()
            if path.suffix.lower() == ".ps1":
                data = windows_script_bytes(data)
            elif path.suffix.lower() == ".cmd":
                # cmd.exe expects no encoding marker. Normalize checkout
                # differences without touching the archived browser SDK.
                data = windows_script_bytes(data)[len(codecs.BOM_UTF8):]
            archive.writestr(info, data)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    print(f"PACKAGE_SHA256={digest}")
    print(f"PACKAGE_BYTES={output.stat().st_size}")
    print(f"PACKAGE_ENTRIES={len(files)}")
    return digest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).parent / "local-website")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.source, args.output)

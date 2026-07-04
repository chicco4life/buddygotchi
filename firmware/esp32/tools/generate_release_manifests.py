#!/usr/bin/env python3
import argparse
import datetime as dt
import hashlib
import json
import shutil
from pathlib import Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def copy_required(src: Path, dest: Path) -> Path:
    if not src.exists():
        raise SystemExit(f"missing build artifact: {src}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    return dest


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Buddygotchi firmware release manifests.")
    parser.add_argument("--version", required=True)
    parser.add_argument("--base-url", required=True, help="Public URL prefix that will host the copied files.")
    parser.add_argument("--build-dir", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    parser.add_argument("--min-app-version", default="0.3.0")
    parser.add_argument("--board", default="m5stickc-plus2")
    args = parser.parse_args()

    out_dir = args.out_dir
    version = args.version.removeprefix("v")
    base_url = args.base_url.rstrip("/")
    published_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    app_name = f"buddygotchi-fw-{version}.bin"
    bootloader_name = f"buddygotchi-bootloader-{version}.bin"
    partitions_name = f"buddygotchi-partitions-{version}.bin"

    app_bin = copy_required(args.build_dir / "firmware.bin", out_dir / app_name)
    bootloader_bin = copy_required(args.build_dir / "bootloader.bin", out_dir / bootloader_name)
    partitions_bin = copy_required(args.build_dir / "partitions.bin", out_dir / partitions_name)

    manifest = {
        "version": version,
        "url": f"{base_url}/{app_name}",
        "sha256": sha256(app_bin),
        "notes": f"Buddygotchi firmware {version}.",
        "published_at": published_at,
        "minAppVersion": args.min_app_version,
        "board": args.board,
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    web_tools_manifest = {
        "name": "Buddygotchi",
        "version": version,
        "home_assistant_domain": "esphome",
        "new_install_prompt_erase": True,
        "builds": [
            {
                "chipFamily": "ESP32",
                "parts": [
                    {"path": f"{base_url}/{bootloader_name}", "offset": 0x1000},
                    {"path": f"{base_url}/{partitions_name}", "offset": 0x8000},
                    {"path": f"{base_url}/{app_name}", "offset": 0x10000},
                ],
            }
        ],
    }
    (out_dir / "esp-web-tools-manifest.json").write_text(
        json.dumps(web_tools_manifest, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Wrote {out_dir / 'manifest.json'}")
    print(f"Wrote {out_dir / 'esp-web-tools-manifest.json'}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Package tested v1.18.4 payloads for publication without rebuilding binaries."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    args.source.resolve().relative_to(project / "out/local-test-packages")
    args.destination.resolve().relative_to(project / "out")
    report = json.loads((args.source / "VALIDATION.json").read_text())
    expected_cert = (project / "android/package/release-cert.sha256").read_text().strip()
    assert report["apkSignerSha256"] == expected_cert, "Release signer mismatch"
    assert report["version"] == "1.18.4" and report["protocol"] == "13.6"
    assert not report["newStrictFailureRules"]
    args.destination.mkdir(parents=True, exist_ok=False)
    spec = importlib.util.spec_from_file_location("builder", project / "tools/prepare-stock-rom-test-kit.py")
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    for kind, basename in (("module", "Rodin-Essential-KernelSU-Next-Magisk"),
                           ("rom", "Rodin-Essential-Stock-EEA")):
        source = args.source / f"{basename}-v1.18.4-local-test.zip"
        stage = args.destination / kind
        stage.mkdir()
        with zipfile.ZipFile(source) as archive:
            assert archive.testzip() is None
            for entry in archive.infolist():
                assert not entry.filename.startswith("/") and ".." not in Path(entry.filename).parts
                if entry.is_dir() or entry.filename in ("SHA256SUMS", "LOCAL-TEST.txt"):
                    continue
                data = archive.read(entry)
                if kind == "module" and entry.filename in ("customize.sh", "service.sh", "action.sh", "uninstall.sh", "module.prop", "skip_mount"):
                    assert data == (project / "android/kernelsu-next" / entry.filename).read_text().replace("\r\n", "\n").encode(), "Installer source drift"
                if kind == "rom" and entry.filename == "FULL-GUIDE.md":
                    data = (project / "docs/STOCK_ROM_PORTER_GUIDE.md").read_text().replace("\r\n", "\n").encode()
                if kind == "rom" and entry.filename == "README.txt":
                    data = data.replace(b"LOCAL STOCK ROM TEST KIT", b"STOCK EEA ROM INTEGRATION KIT")
                    data = data.replace(
                        b"Both local test\npackages use the same current Windows test signing key, NOT the old public\nrelease key.",
                        b"Both release\npackages use the same v1.18.4 replacement signing identity. This differs\nfrom the v1.18.3 public release key.")
                target = stage / entry.filename
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
        for relative, expected in report["payload"].items():
            if kind == "module":
                target = stage / relative
            else:
                relative = "app/RodinEssential/RodinEssential.apk" if relative.startswith("app/") else relative
                target = stage / "copy-to-extracted-rom/product" / relative
            assert builder.digest(target) == expected, "Tested binary payload changed"
        builder.write(stage / "SHA256SUMS", "".join(
            f"{builder.digest(path)}  {path.relative_to(stage).as_posix()}\n"
            for path in sorted(stage.rglob("*")) if path.is_file()))
        release_basename = "Rodin-Essential-ROM-Integration" if kind == "rom" else basename
        output = args.destination / f"{release_basename}-v1.18.4.zip"
        builder.archive(stage, output)
        builder.write(output.with_suffix(".zip.sha256"), builder.digest(output) + "  " + output.name + "\n")
        print(output.name, builder.digest(output))
    builder.write(args.destination / "VALIDATION.json", json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()

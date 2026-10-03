#!/usr/bin/env python3
"""Update only the guide/checksums in an already built local ROM test kit."""
import argparse
import importlib.util
from pathlib import Path
import shutil
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    directory = parser.parse_args().directory.resolve()
    project = Path(__file__).resolve().parents[1]
    # Restrict this maintenance command to generated output, never ROM sources.
    directory.relative_to(project / "out/local-test-packages")
    kit = directory / "rom-kit"
    archive_path = directory / "Rodin-Essential-Stock-EEA-v1.18.4-local-test.zip"
    assert kit.is_dir() and archive_path.is_file()
    spec = importlib.util.spec_from_file_location("kit_builder", project / "tools/prepare-stock-rom-test-kit.py")
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    shutil.copyfile(project / "docs/STOCK_ROM_PORTER_GUIDE.md", kit / "FULL-GUIDE.md")
    readme = kit / "README.txt"
    text = readme.read_text()
    pointer = "Read FULL-GUIDE.md first. Metadata files are for the ROM kitchen, not the phone.\n"
    if pointer not in text:
        builder.write(readme, pointer + "\n" + text)
    builder.write(kit / "SHA256SUMS", "".join(
        f"{builder.digest(path)}  {path.relative_to(kit).as_posix()}\n"
        for path in sorted(kit.rglob("*")) if path.is_file() and path.name != "SHA256SUMS"))
    pending = archive_path.with_suffix(".updated.zip")
    builder.archive(kit, pending)
    with zipfile.ZipFile(pending) as zipped:
        assert zipped.testzip() is None
        assert "FULL-GUIDE.md" in zipped.namelist()
    pending.replace(archive_path)
    builder.write(archive_path.with_suffix(".zip.sha256"), builder.digest(archive_path) + "  " + archive_path.name + "\n")
    print("ROM guide refreshed; application, daemon and module unchanged")


if __name__ == "__main__":
    main()

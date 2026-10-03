#!/usr/bin/env python3
"""Read-only checks of the synchronized local ROM/module test archives."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
import zipfile


def aligned_elf(data):
    assert data[:6] == b"\x7fELF\x02\x01", "Expected little-endian ELF64"
    assert struct.unpack_from("<H", data, 18)[0] == 183, "Expected AArch64"
    offset = struct.unpack_from("<Q", data, 32)[0]
    size, count = struct.unpack_from("<HH", data, 54)
    loads = [struct.unpack_from("<IIQQQQQQ", data, offset + index * size)
             for index in range(count)]
    loads = [header for header in loads if header[0] == 1]
    assert loads and all(header[7] >= 16384 for header in loads), "ELF alignment below 16KB"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    directory = parser.parse_args().directory
    report = json.loads((directory / "VALIDATION.json").read_text())
    assert not report["newStrictFailureRules"]
    assert report["policyCompileExitCodes"]["stock-runtime-mode"] == 0
    assert report["policyCompileExitCodes"]["rodin-runtime-mode"] == 0
    published_rom = directory / "Rodin-Essential-ROM-Integration-v1.18.4.zip"
    suffix = "" if published_rom.exists() else "-local-test"
    rom_path = published_rom if published_rom.exists() else directory / "Rodin-Essential-Stock-EEA-v1.18.4-local-test.zip"
    with zipfile.ZipFile(rom_path) as rom, \
         zipfile.ZipFile(directory / f"Rodin-Essential-KernelSU-Next-Magisk-v1.18.4{suffix}.zip") as module:
        assert rom.testzip() is None and module.testzip() is None
        root = "copy-to-extracted-rom/product/"
        for relative in ("app/RodinEssential.apk", "bin/rodin_daemon", "bin/rodin_ctl"):
            rom_name = root + ("app/RodinEssential/RodinEssential.apk" if relative.startswith("app/") else relative)
            data = module.read(relative)
            assert data == rom.read(rom_name), "ROM/module payload differs"
            assert hashlib.sha256(data).hexdigest() == report["payload"][relative]
            if relative.startswith("bin/"):
                aligned_elf(data)
                if relative.endswith("rodin_daemon"):
                    assert b"13.6" in data, "Protocol string missing from daemon"
        with zipfile.ZipFile(io.BytesIO(module.read("app/RodinEssential.apk"))) as apk:
            assert not any(name.startswith("classes") and name.endswith(".dex") for name in apk.namelist())
            libraries = [name for name in apk.namelist() if name.startswith("lib/") and name.endswith(".so")]
            assert libraries
            for name in libraries:
                aligned_elf(apk.read(name))
            assert b"13.6" in apk.read("lib/arm64-v8a/librodin_essential_host.so")
        mac = ET.fromstring(rom.read(root + "etc/selinux/product_mac_permissions.xml"))
        mapping = [signer for signer in mac.findall("signer")
                   if signer.find("package[@name='io.github.neeschal.rodinessential']") is not None]
        assert len(mapping) == 1
        certificate = bytes.fromhex(mapping[0].attrib["signature"])
        assert hashlib.sha256(certificate).hexdigest() == report["apkSignerSha256"]
        seapp = rom.read(root + "etc/selinux/product_seapp_contexts").decode()
        assert "domain=rodin_app type=app_data_file levelFrom=all" in seapp
        policy = rom.read(root + "etc/selinux/product_sepolicy.cil").decode()
        assert "(allow rodin_app rodin_daemon (unix_stream_socket (connectto)))" in policy
        assert "(allow untrusted_app_all rodin_daemon" not in policy
        rc = rom.read(root + "etc/init/rodin_daemon.rc").decode()
        assert "service rodin_daemon /product/bin/rodin_daemon" in rc
        assert "on property:sys.boot_completed=1" in rc
        assert "/data/adb" not in rc and "seclabel u:r:su" not in rc
        assert len(rom.read("REMOVE-BEFORE-COPY.txt").decode().splitlines()) == 3
        prop = module.read("module.prop").decode()
        assert "version=v1.18.4\n" in prop and "versionCode=11804\n" in prop
        for name in module.namelist():
            assert ".." not in Path(name).parts and not name.startswith("/")
            if name.endswith(".sh"):
                assert b"\r" not in module.read(name)
                assert module.getinfo(name).external_attr >> 16 & 0o111
    print("LOCAL_PACKAGE_PARITY_LABELS_ABI_PROTOCOL_TEST=PASS")


if __name__ == "__main__":
    main()

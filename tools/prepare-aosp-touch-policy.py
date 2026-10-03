#!/usr/bin/env python3
"""Preview an explicit, scoped platform exception for the legacy THP backend.

This is not a policy compiler or a certification check. Unknown rule layouts
are rejected. Run the complete target SELinux build after applying the patch.
"""
import argparse
import difflib
from pathlib import Path
import re

ATTRIBUTE = "rodin_native_touch_access"


def prepare(attributes: str, domain: str) -> tuple[str, str]:
    declaration = f"attribute {ATTRIBUTE};"
    expansion = f"expandattribute {ATTRIBUTE} false;"
    exclusion = f"  -{ATTRIBUTE}\n"
    member = f"  {ATTRIBUTE}\n"
    ptrace = re.compile(
        r"neverallow \{\n(?P<body>[^{}]*?)\n\} self:global_capability_class_set sys_ptrace;"
    )
    dac = re.compile(r"define\(`dac_override_allowed', `\{\n(?P<body>.*?)\n\}'\)", re.S)
    ptrace_matches = list(ptrace.finditer(domain))
    dac_matches = list(dac.finditer(domain))
    if len(ptrace_matches) != 1 or len(dac_matches) != 1:
        raise ValueError("Unknown platform capability rules; manual maintainer review required")
    if "domain" not in ptrace_matches[0]["body"].split():
        raise ValueError("Unexpected SYS_PTRACE neverallow scope")
    existing = (
        declaration in attributes,
        expansion in attributes,
        f"-{ATTRIBUTE}" in ptrace_matches[0]["body"].split(),
        ATTRIBUTE in dac_matches[0]["body"].split(),
    )
    if any(existing):
        if not all(existing):
            raise ValueError("Partial existing exception; reconcile it manually")
        return attributes, domain
    if ATTRIBUTE in attributes or ATTRIBUTE in domain:
        raise ValueError("Conflicting pre-existing Rodin attribute")
    attributes = attributes.rstrip() + (
        "\n\n# Opt-in legacy Rodin THP access. Assign only to rodin_daemon.\n"
        + declaration + "\n" + expansion + "\n"
    )
    domain = ptrace.sub(lambda match: match[0].replace("neverallow {\n", "neverallow {\n" + exclusion, 1), domain)
    domain = dac.sub(lambda match: match[0].replace("`{\n", "`{\n" + member, 1), domain)
    return attributes, domain


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("aosp_root", type=Path)
    parser.add_argument("--apply", action="store_true", help="Apply the reviewed preview to the source checkout")
    args = parser.parse_args()
    policy = args.aosp_root.resolve() / "system/sepolicy"
    paths = (policy / "public/attributes", policy / "private/domain.te")
    originals = tuple(path.read_text(encoding="utf-8") for path in paths)
    try:
        updated = prepare(*originals)
    except ValueError as error:
        parser.error(str(error))
    for path, before, after in zip(paths, originals, updated):
        print("".join(difflib.unified_diff(before.splitlines(True), after.splitlines(True), fromfile=str(path), tofile=str(path))), end="")
    if args.apply:
        for path, before, after in zip(paths, originals, updated):
            if before != after:
                path.write_text(after, encoding="utf-8", newline="\n")
        print("Applied source exception. Full target policy build and device verification are still required.")
    else:
        print("Preview only; no files changed. Use --apply only after maintainer review.")


if __name__ == "__main__":
    main()

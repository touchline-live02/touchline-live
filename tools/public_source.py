#!/usr/bin/env python3
"""Validate and package the approved source set without archiving a mutable tree."""
import argparse
import hashlib
import pathlib
import re
import stat
import sys
import zipfile

sys.dont_write_bytecode = True
ROOT = pathlib.Path(__file__).resolve().parents[1]
FILE_LIST = 'tools/source_files.txt'
MANIFEST = 'SOURCE_MANIFEST.sha256'
ZIP_TIME = (1980, 1, 1, 0, 0, 0)
RULES = {
    'personal home path': rb'/(?:Users|home)/[A-Za-z0-9_.-]+/',
    'email address': rb'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    'credential token': rb'(?:gh[pousr]_[A-Za-z0-9]{20,}|AKIA[A-Z0-9]{16}|sk-[A-Za-z0-9_-]{24,})',
    'private IPv4': rb'(?:192\.168\.[0-9]{1,3}\.[0-9]{1,3}|10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})',
}


def files(root=ROOT):
    root = pathlib.Path(root)
    names = [line.strip() for line in (root/FILE_LIST).read_text().splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    if len(names) != len(set(names)):
        raise ValueError('Duplicate approved source path')
    if 'LICENSE' not in names:
        raise ValueError('LICENSE must be in the approved source list')
    for name in names:
        path = pathlib.PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts or str(path) != name or '\\' in name:
            raise ValueError('Invalid approved source path')
    return [root/name for name in sorted(names)]


def scan(paths, root=ROOT):
    findings = []
    root = pathlib.Path(root)
    for path in paths:
        if path.is_symlink() or not path.is_file():
            findings.append((str(path.relative_to(root)), 'missing file or symlink'))
            continue
        data = path.read_bytes()
        for label, pattern in RULES.items():
            if re.search(pattern, data):
                findings.append((str(path.relative_to(root)), label))
    return findings


def validate_tree(root, allow_git=False):
    root = pathlib.Path(root)
    expected = {p.relative_to(root).as_posix() for p in files(root)}
    allowed_directories = {parent.as_posix() for name in expected
                           for parent in pathlib.PurePosixPath(name).parents if str(parent) != '.'}
    found = set()
    for path in root.rglob('*'):
        relative = path.relative_to(root).as_posix()
        if allow_git and relative.split('/')[0] == '.git':
            continue
        if path.is_symlink():
            raise ValueError('Symlinks are not publication files: '+relative)
        if path.is_dir():
            if relative not in allowed_directories:
                raise ValueError('Unexpected publication directory: '+relative)
        else:
            found.add(relative)
    extras = found - expected - {MANIFEST}
    missing = expected - found
    if extras or missing:
        raise ValueError(f'Unexpected or missing source files: extra={sorted(extras)}, missing={sorted(missing)}')
    findings = scan([root/name for name in expected], root)
    if findings:
        raise ValueError('Source scan failed: '+repr(findings))
    return expected


def snapshot(root=ROOT):
    root = pathlib.Path(root)
    names = validate_tree(root, allow_git=True)
    # Read the approved inputs once: exports and archives use these bytes, not a later directory walk.
    payload = {name: (root/name).read_bytes() for name in sorted(names)}
    for name, data in payload.items():
        if any(re.search(pattern, data) for pattern in RULES.values()):
            raise ValueError('Publication bytes failed privacy scan: '+name)
    payload[MANIFEST] = manifest(payload)
    return payload


def manifest(payload):
    return ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n'
                   for name, data in sorted(payload.items()) if name != MANIFEST).encode('utf-8')


def verify_export(destination, root=ROOT):
    destination = pathlib.Path(destination)
    validate_tree(destination)
    expected = snapshot(root)
    actual = {p.relative_to(destination).as_posix(): p.read_bytes()
              for p in destination.rglob('*') if p.is_file()}
    if actual != expected:
        raise ValueError('Export membership, manifest or contents do not match approved source')
    return len(actual)


def outside_source(destination, root):
    destination = pathlib.Path(destination).resolve()
    root = pathlib.Path(root).resolve()
    if destination == root or root in destination.parents or destination in root.parents:
        raise ValueError('Publication output must be outside the source tree')
    return destination


def export(destination, root=ROOT):
    payload = snapshot(root)
    destination = outside_source(destination, root)
    if destination.exists() and any(destination.iterdir()):
        raise ValueError('Destination must be absent or empty')
    destination.mkdir(parents=True, exist_ok=True)
    for name, data in payload.items():
        target = destination/name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        target.chmod(0o755 if name.endswith('.sh') else 0o644)
    verify_export(destination, root)
    return len(payload)


def verify_archive(path, root=ROOT):
    expected = snapshot(root)
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = [entry.filename for entry in entries]
        if len(names) != len(set(names)) or set(names) != set(expected):
            raise ValueError('Unexpected, missing or duplicated archive member')
        if archive.comment:
            raise ValueError('Unexpected archive comment')
        for entry in entries:
            mode = entry.external_attr >> 16
            if (entry.extra or entry.comment or entry.date_time != ZIP_TIME or
                entry.create_system != 3 or not stat.S_ISREG(mode) or
                stat.S_IMODE(mode) != (0o755 if entry.filename.endswith('.sh') else 0o644)):
                raise ValueError('Unexpected archive metadata: '+entry.filename)
            if archive.read(entry) != expected[entry.filename]:
                raise ValueError('Archive content/hash differs from approved source: '+entry.filename)
    return len(entries)


def package(destination, root=ROOT):
    payload = snapshot(root)
    destination = outside_source(destination, root)
    if destination.exists():
        raise ValueError('Archive destination already exists')
    destination.parent.mkdir(parents=True, exist_ok=True)
    # No source directory is zipped: every member comes directly from the approved snapshot.
    try:
        with zipfile.ZipFile(destination, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in payload.items():
                entry = zipfile.ZipInfo(name, date_time=ZIP_TIME)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFREG | (0o755 if name.endswith('.sh') else 0o644)) << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.extra = entry.comment = b''
                archive.writestr(entry, data)
        verify_archive(destination, root)
    except Exception:
        destination.unlink(missing_ok=True)
        raise
    return len(payload)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group()
    actions.add_argument('--output', type=pathlib.Path)
    actions.add_argument('--archive', type=pathlib.Path)
    actions.add_argument('--verify-export', type=pathlib.Path)
    actions.add_argument('--verify-archive', type=pathlib.Path)
    args = parser.parse_args()
    if args.output:
        count = export(args.output)
    elif args.archive:
        count = package(args.archive)
    elif args.verify_export:
        count = verify_export(args.verify_export)
    elif args.verify_archive:
        count = verify_archive(args.verify_archive)
    else:
        count = len(snapshot())
    print(f'Approved publication set verified: {count} files including the hash manifest.')


if __name__ == '__main__':
    main()

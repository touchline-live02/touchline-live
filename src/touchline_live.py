#!/usr/bin/env python3
"""Exact-build, collection-first FM24 reader. Live memory only."""
import argparse
import datetime as dt
import hashlib
import json
import pathlib
import shlex
import struct
import subprocess
import tempfile
import time
from collections import Counter
from live_currency import capture_currencies
from live_nationality import populate_nationalities, DEFINITION as NATIONALITY_DEFINITION
from live_date import read_game_date, apply_game_date, AGE_DEFINITION
from live_transfers import TransferResolver, extract_anchor
from live_player import (LivePlayerCache, NameResolver, decode_player, apply_names, FIELD_DEFINITIONS)

PROJECT = pathlib.Path(__file__).resolve().parents[1]
SHA256 = 'f0ba078c384f1095320ed4059a18fe4de4701cae5661a117417b2624d12b16e2'
UUID = 'd710f6fa6aca32bb99fe451cee8dfa3d'
ROOT_RVA = 0x5302580
PERSON_ROOT_RVA = ROOT_RVA - 24
# Offset of person subobject and concrete object size for the two observed types.
TYPES = {0x107e0d770-0x102c28000: ('player', 0x268, 0x3c8),
         0x107e13848-0x102c28000: ('player_staff', 0x350, 0x4b0)}

class Session:
    def __init__(self, directory):
        self.directory = pathlib.Path(directory)
        self.bytes = self.calls = 0

    def request(self, command):
        ident = str(time.time_ns())
        tmp = self.directory / 'request.tmp'
        tmp.write_text(ident + ' ' + command + '\n')
        tmp.replace(self.directory / 'request.txt')
        response = self.directory / ('response-' + ident + '.txt')
        deadline = time.monotonic() + 55
        while not response.exists():
            if time.monotonic() > deadline:
                raise RuntimeError('Read-only helper did not respond; no snapshot published.')
            time.sleep(.025)
        try:
            lines = response.read_text().splitlines()
        finally:
            # Consume private transport files; don't retain raw memory dumps if a later stage fails.
            response.unlink(missing_ok=True)
        for line in lines:
            if line.startswith('ERROR'):
                raise RuntimeError(line)
            if line.startswith('METRICS'):
                _, size, calls, _ = line.split()
                self.bytes += int(size)
                self.calls += int(calls)
        return lines

    def read(self, pairs, strict=True):
        rows = self.request('batch ' + ' '.join(f'{a:x} {n:x}' for a, n in pairs))
        result = {}
        for line in rows:
            if line.startswith('READ'):
                _, a, n, raw = line.split()
                if raw == 'FAILED':
                    if strict:
                        raise RuntimeError(f'Unreadable collection/object block at {a}; discarded snapshot.')
                    result[int(a,16)] = None
                    continue
                b = bytes.fromhex(raw)
                if len(b) != int(n, 16):
                    raise RuntimeError('Truncated read')
                result[int(a, 16)] = b
        if len(result) != len(set(a for a, _ in pairs)):
            raise RuntimeError('Incomplete response')
        return result

    def image_base(self):
        # Region metadata only, followed by bounded Mach-O header reads.
        # No UID, heap-content or field search occurs during normal enumeration.
        for line in self.request('map'):
            v = line.split()
            if v[0] != 'REGION' or int(v[3]) != 5 or int(v[4]) != 0:
                continue
            a = int(v[1], 16)
            h = self.read([(a, 0x4000)])[a]
            if struct.unpack_from('<I', h)[0] != 0xfeedfacf:
                continue
            if struct.unpack_from('<I', h, 12)[0] != 2:
                continue
            off = 32
            for _ in range(struct.unpack_from('<I', h, 16)[0]):
                cmd, size = struct.unpack_from('<II', h, off)
                if size < 8 or off + size > len(h):
                    raise RuntimeError('Unsupported Mach-O header')
                if cmd == 0x1b and h[off+8:off+24].hex() == UUID:
                    return a
                off += size
            raise RuntimeError('FM24 image UUID does not match the verified build')
        raise RuntimeError('Verified FM24 executable image not found')

def vector(header):
    start, end, capacity = struct.unpack('<QQQ', header)
    if not (start > 0x100000000 and start <= end <= capacity and
            start % 8 == end % 8 == capacity % 8 == 0 and
            0 < (end-start)//8 <= 500000 and (capacity-start)//8 <= 1000000):
        raise RuntimeError('Invalid or changing collection header')
    return start, end, capacity

def capture_cache(session, progress=None):
    progress = progress or (lambda message, fraction: None)
    progress("Locating the established player collection", 0.12)
    began = time.monotonic()
    initial_bytes, initial_calls = session.bytes, session.calls
    base = session.image_base()
    game_date, game_date_info = read_game_date(session, base)
    currencies = capture_currencies(session, base)
    root = base + ROOT_RVA
    ph = session.read([(root, 24), (base+PERSON_ROOT_RVA, 24)])
    header = ph[root]
    start, end, capacity = vector(header)
    person_start, person_end, _ = vector(ph[base+PERSON_ROOT_RVA])
    table = session.read([(start, end-start)])[start]
    pointers = struct.unpack('<' + 'Q'*((end-start)//8), table)
    if len(set(pointers)) != len(pointers) or any(p < 0x100000000 or p % 8 for p in pointers):
        raise RuntimeError('Null, duplicate or malformed player pointer')
    progress(f"Reading {len(pointers):,} player records", 0.18)
    # Read occupied 64 KiB blocks once; no per-player remote lookup.
    pages = sorted({a & ~0xffff for p in pointers for a in (p, p+0x4af)})
    cache = {}
    for i in range(0, len(pages), 400):
        cache.update(session.read([(a, 65536) for a in pages[i:i+400]]))
        progress("Reading player records", 0.18 + 0.27*min(i+400,len(pages))/len(pages))
    def get(a, n):
        result = bytearray()
        while n:
            page = a & ~0xffff
            size = min(n, 65536-(a-page))
            result.extend(cache[page][a-page:a-page+size])
            a += size
            n -= size
        return result
    rows, types, alias_differences, name_pointers = [], {}, 0, []
    relationship_anchors = []
    nationality_anchors = []
    for i, p in enumerate(pointers):
        vt = struct.unpack('<Q', get(p, 8))[0]
        profile = TYPES.get(vt-base)
        if profile is None:
            raise RuntimeError(f'Unmapped player subtype at {p:x}; no partial census published')
        subtype, person, length = profile
        b = get(p, length)
        player, adjacent = decode_player(i, p, subtype, person, b)
        alias_differences += player.uid != adjacent
        types[subtype] = types.get(subtype, 0) + 1
        rows.append(player)
        relationship_anchors.append(extract_anchor(p,person,b))
        nationality_anchors.append((p+person,struct.unpack_from('<Q',b,person+0x40)[0]))
        name_pointers.append(struct.unpack_from('<3Q', b, person+0x28))
    if len({r.uid for r in rows}) != len(rows):
        raise RuntimeError('Duplicate player UIDs')
    apply_game_date(rows, game_date)
    object_seconds = time.monotonic()-began
    progress("Decoding names and scouting attributes", 0.48)
    resolver = NameResolver(session)
    names = resolver.resolve(p for triple in name_pointers for p in triple)
    for player, ptrs in zip(rows,name_pointers):
        apply_names(player,ptrs,names)
    nationalities = populate_nationalities(rows,nationality_anchors,session,base,memory=resolver)
    name_seconds = time.monotonic()-began-object_seconds
    progress("Resolving clubs and contracts", 0.64)
    relationships = TransferResolver(session,base).populate(rows,relationship_anchors)
    progress("Checking collection consistency", 0.83)
    # A reload or changed collection invalidates the entire cache.
    again = session.read([(root, 24), (start, end-start)])
    if again[root] != header or again[start] != table:
        raise RuntimeError('Player collection changed during capture; retry with the game idle')
    # Exact build, vector, subtype and core-field checks apply to every record.
    # A resolved bounded name validates the string relationship without requiring
    # a particular player or database.
    sample = next((row for row in rows if row.name and row.name.strip()
                   and row.fieldStatus['name'] == 'derived'), None)
    if sample is None:
        raise RuntimeError('No player has a valid decoded name; snapshot was not published')
    coverage = {field:dict(Counter(r.fieldStatus[field] for r in rows)) for field in (*FIELD_DEFINITIONS, 'nationality')}
    context = dict(currencies=currencies, modelVersion=3, source='FM24 live memory',
        capturedAt=dt.datetime.now(dt.timezone.utc).isoformat(),
        imageUUID=UUID, imageBase=hex(base), rootRVA=hex(ROOT_RVA), root=hex(root),
        collection=dict(start=hex(start), end=hex(end), capacityEnd=hex(capacity),
                        representation='64-bit pointer vector; begin/end/capacity',
                        count=len(rows), capacity=(capacity-start)//8),
        personCount=(person_end-person_start)//8, types=types,
        adjacentUIDDifferences=alias_differences,
        elapsedSeconds=round(time.monotonic()-began, 4),
        timings=dict(objectsSeconds=round(object_seconds,4),namesSeconds=round(name_seconds,4),relationshipsSeconds=relationships['seconds']),
        remoteBytesRead=session.bytes-initial_bytes, remoteReadCalls=session.calls-initial_calls,
        nameCache=dict(entries=len(names)-1,pages=len(resolver.pages)),
        fieldDefinitions=dict(FIELD_DEFINITIONS, age=AGE_DEFINITION, nationality=NATIONALITY_DEFINITION),fieldCoverage=coverage,
        nationalities=nationalities,
        collectionStable=True, atomicSnapshot=False, gameDate=game_date.isoformat(), gameDateInfo=game_date_info, relationships=relationships)
    return LivePlayerCache(context,rows)

def capture(session):
    return capture_cache(session).snapshot()

def authorization_script(command):
    # AppleScript accepts literal UTF-8, not JSON's ASCII-only Unicode escapes.
    return 'do shell script ' + json.dumps(command, ensure_ascii=False) + ' with administrator privileges'

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--session', help='Reuse an already attached read-only helper session')
    ap.add_argument('--output', type=pathlib.Path, default=PROJECT/'app-data/latest',
                    help='Capture directory (default: app-data/latest beside the backend project)')
    ap.add_argument('--progress-json', action='store_true', help='Native application progress events')
    args = ap.parse_args()
    import signal
    cancelled = False
    def request_cancel(signum, frame):
        nonlocal cancelled
        cancelled = True
    if args.progress_json:
        # Defer cancellation to stage boundaries; never interrupt task-port cleanup.
        signal.signal(signal.SIGINT, request_cancel)
        signal.signal(signal.SIGTERM, request_cancel)
    def emit(message, fraction):
        if cancelled and fraction < 0.87:
            raise KeyboardInterrupt()
        if args.progress_json:
            print(json.dumps(dict(event='progress',message=message,fraction=fraction)),flush=True)
        else:
            print(message,flush=True)
    owned = not args.session
    session = None
    directory = None
    snapshot = None
    began = time.monotonic()
    try:
        try:
            if owned:
                emit('Checking for FM24', 0.02)
                listing = subprocess.check_output(['ps', '-axo', 'pid=,comm='], text=True)
                targets = [line.strip().split(None, 1) for line in listing.splitlines()
                           if line.endswith('/Football Manager 2024/fm.app/Contents/MacOS/fm')]
                if len(targets) != 1:
                    raise RuntimeError('FM24 is not running. Open FM24 with your career loaded, then refresh. Your saved cache is unchanged.' if not targets else 'More than one FM24 process is running. Leave one career open, then refresh.')
                pid, executable = targets[0]
                with open(executable, 'rb') as f:
                    digest = hashlib.sha256()
                    for block in iter(lambda: f.read(1024*1024), b''):
                        digest.update(block)
                if digest.hexdigest() != SHA256:
                    raise RuntimeError('This FM24 build does not match the verified reader. Your saved cache is unchanged.')
                directory = pathlib.Path(tempfile.mkdtemp(prefix='touchline-live-'))
                command = shlex.join([str(PROJECT/'touchline-probe'), pid, str(directory)])
                command += ' > /dev/null 2>&1 &'
                script = authorization_script(command)
                emit('Waiting for macOS authorization for a read-only capture', 0.07)
                try:
                    subprocess.run(['osascript', '-e', script], check=True)
                except subprocess.CalledProcessError:
                    raise RuntimeError('macOS authorization was cancelled or denied. Your saved cache is unchanged.') from None
                deadline = time.monotonic()+10
                while not (directory/'ready.txt').exists():
                    if time.monotonic()>deadline:
                        raise RuntimeError('The read-only attachment was not established. Your saved cache is unchanged.')
                    time.sleep(.05)
                session = Session(directory)
            else:
                session = Session(args.session)
            began = time.monotonic()
            snapshot = capture_cache(session,emit).snapshot()
        finally:
            if owned and directory and (directory/'ready.txt').exists():
                emit('Detaching from FM24', 0.87)
                # Also handles cancellation immediately after authorization.
                reply = (session or Session(directory)).request('quit')
                if 'BYE' not in reply:
                    raise RuntimeError('Could not confirm read-only attachment closure; cache was not replaced.')
                if args.progress_json:
                    print(json.dumps(dict(event='detached')),flush=True)
                import shutil
                shutil.rmtree(directory)
        # No task port remains while serializing, saving or browsing this snapshot.
        emit('Saving the local player cache', 0.91)
        output = args.output
        output.mkdir(parents=True,exist_ok=True)
        target = output/'players.json'
        tmp = output/'players.tmp'
        tmp.write_text(json.dumps(snapshot, ensure_ascii=False, separators=(',', ':')))
        tmp.replace(target)
        summary = {k:v for k,v in snapshot.items() if k != 'players'}
        summary['captureAndSaveSeconds'] = round(time.monotonic()-began,4)
        summary['attachmentClosed'] = owned
        (output/'summary.json').write_text(json.dumps(summary, indent=2))
        if args.progress_json:
            print(json.dumps(dict(event='complete',count=snapshot['collection']['count'],
                                  captureSeconds=snapshot['elapsedSeconds'],path=str(target))),flush=True)
        else:
            print(json.dumps(summary, indent=2))
    except (Exception,KeyboardInterrupt) as error:
        message = 'Capture cancelled; the previous cache is retained.' if isinstance(error,KeyboardInterrupt) else str(error)
        if args.progress_json:
            print(json.dumps(dict(event='error',message=message)),flush=True)
        else:
            print(message)
        raise SystemExit(130 if isinstance(error,KeyboardInterrupt) else 1)

if __name__ == '__main__':
    main()

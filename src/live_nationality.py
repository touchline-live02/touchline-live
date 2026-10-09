"""Verified primary nationality for the exact gated FM24 ARM64 build."""
import struct
import time
from collections import Counter
from live_player import NameResolver

NATION_VTABLE_RVA = 0x52099f0  # RTTI: N2db6NATIONE
PERSON_NATION_OFFSET = 0x40
NATION_NAME_OFFSET = 0x18
DEFINITION = {'status':'verified',
              'layout':'u64 person+0x40 -> NATION (vtable RVA 0x52099f0); +0x18 -> direct u32 byte length + UTF-8',
              'scope':'Primary nationality only; no secondary nationalities or inference'}


def valid_address(a, length=1):
    return 0x100000000 <= a and a+length <= 0x100000000000


def populate_nationalities(players, anchors, session, base, memory=None):
    """Anchors are (person origin, nation pointer) extracted from existing player bytes.

    Deduplicate nation and direct-string pages, sharing the capture's name cache.
    No per-player remote requests, no searches, and no lazy memory access.
    """
    if len(players) != len(anchors):
        raise ValueError('Nationality anchors must match player collection')
    began=time.monotonic(); before_bytes,before_calls=session.bytes,session.calls
    mem=memory if memory is not None else NameResolver(session)
    nations={nation for _,nation in anchors}
    mem.preload([(a,0x20) for a in nations if valid_address(a,0x20) and a%8==0])
    records={}; strings={}
    def failed(status,reason,**provenance):
        return dict(status=status,name=None,reason=reason,**provenance)
    for a in nations:
        info={'address':hex(a)}
        if a==0:
            records[a]=failed('unavailable','Primary nation pointer is null',**info);continue
        if not valid_address(a,0x20) or a%8:
            records[a]=failed('inconsistent','Malformed primary nation pointer',**info);continue
        b=mem.get(a,0x20)
        if b is None or len(b)!=0x20:
            records[a]=failed('unresolved','Unreadable nation object',**info);continue
        rva=struct.unpack_from('<Q',b)[0]-base;info['vtableRVA']=hex(rva)
        if rva!=NATION_VTABLE_RVA:
            records[a]=failed('inconsistent','Object is not the verified NATION type',**info);continue
        target=struct.unpack_from('<Q',b,NATION_NAME_OFFSET)[0];info['nameAddress']=hex(target)
        if not target:
            records[a]=failed('unresolved','Nation exists but name pointer is null',**info);continue
        if not valid_address(target,4):
            records[a]=failed('inconsistent','Malformed direct nation-name pointer',**info);continue
        records[a]=info;strings[a]=target
    mem.preload([(a,4) for a in set(strings.values())])
    lengths={}; decoded={}
    for a in set(strings.values()):
        h=mem.get(a,4)
        if h is None or len(h)!=4:
            decoded[a]=failed('unresolved','Unreadable nation-name length');continue
        n=struct.unpack('<I',h)[0]
        if not 0<n<=mem.MAX_NAME_BYTES or not valid_address(a,4+n):
            decoded[a]=failed('inconsistent','Invalid nation-name byte length');continue
        lengths[a]=n
    mem.preload([(a+4,n) for a,n in lengths.items()])
    for a,n in lengths.items():
        raw=mem.get(a+4,n)
        if raw is None or len(raw)!=n:
            decoded[a]=failed('unresolved','Unreadable nation-name bytes');continue
        try: name=raw.decode('utf-8')
        except UnicodeDecodeError:
            decoded[a]=failed('inconsistent','Invalid nation-name UTF-8');continue
        if not name.strip() or not name.isprintable():
            decoded[a]=failed('inconsistent','Invalid nation-name text');continue
        decoded[a]=dict(status='verified',name=name)
    for a,target in strings.items():
        records[a].update(decoded[target])
    for player,(person,nation) in zip(players,anchors):
        result=dict(records[nation],personAddress=hex(person),sourceAddress=hex(person+PERSON_NATION_OFFSET))
        player.nationality=result
        player.fieldStatus['nationality']=result['status']
        if result['status'] in ('unresolved','inconsistent'):
            player.issues.append(dict(field='nationality',status=result['status'],reason=result['reason']))
    return dict(definition=DEFINITION,distinctNations=len(nations-{0}),
                coverage=dict(Counter(p.fieldStatus['nationality'] for p in players)),
                seconds=round(time.monotonic()-began,4),
                remoteBytesRead=session.bytes-before_bytes,remoteReadCalls=session.calls-before_calls)

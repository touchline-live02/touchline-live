"""Exact-build FM24 currency store. Read once per capture, separate from players."""
import math
import struct
import time
from live_player import NameResolver

ROOT_RVA = 0x53024b0
TABLE_VTABLE_RVA = 0x51fe4c8
RECORD_VTABLE_RVA = 0x51fbc28

def read_currencies(session, base):
    began=time.monotonic()
    before_bytes, before_calls=session.bytes, session.calls
    root=base+ROOT_RVA
    root_bytes=session.read([(root,8)])[root]
    table=struct.unpack('<Q',root_bytes)[0]
    if not 0x100000000<=table<0x100000000000:raise RuntimeError('Invalid currency table pointer')
    body=session.read([(table,0xb0)])[table]
    if struct.unpack_from('<Q',body)[0]!=base+TABLE_VTABLE_RVA:raise RuntimeError('Unrecognized currency table type')
    vector=struct.unpack_from('<Q',body,0x88)[0]
    header=session.read([(vector,24)])[vector]
    start,end,capacity=struct.unpack('<QQQ',header)
    if not (0x100000000<=start<end<=capacity<0x100000000000 and start%8==end%8==capacity%8==0 and 1<=(end-start)//8<=512 and (capacity-start)//8<=1024):raise RuntimeError('Invalid currency vector')
    array=session.read([(start,end-start)])[start]
    pointers=struct.unpack('<'+'Q'*((end-start)//8),array)
    if len(set(pointers))!=len(pointers) or any(not 0x100000000<=p<0x100000000000 for p in pointers):raise RuntimeError('Invalid currency records')
    reader=NameResolver(session)
    reader.preload([(p,0x58) for p in pointers])
    records=[];strings=set()
    for p in pointers:
        b=reader.get(p,0x58)
        if b is None or struct.unpack_from('<Q',b)[0]!=base+RECORD_VTABLE_RVA:raise RuntimeError('Unrecognized currency record type')
        name,short=struct.unpack_from('<2Q',b,0x18);symbol=struct.unpack_from('<Q',b,0x30)[0]
        value=struct.unpack_from('<f',b,0x38)[0]
        if not math.isfinite(value) or value<=0:raise RuntimeError('Invalid live currency multiplier')
        records.append((p,b,name,short,symbol,value));strings.update((name,short,symbol))
    strings.discard(0);reader.preload([(p,4) for p in strings])
    lengths={}
    for p in strings:
        b=reader.get(p,4)
        if b is None:raise RuntimeError('Unreadable currency string')
        n=struct.unpack('<I',b)[0]
        if n>128:raise RuntimeError('Oversized currency string')
        lengths[p]=n
    reader.preload([(p+4,n) for p,n in lengths.items() if n])
    decoded={0:''}
    for p,n in lengths.items():
        raw=reader.get(p+4,n)
        try:text=raw.decode('utf-8') if raw is not None else None
        except UnicodeDecodeError:raise RuntimeError('Invalid currency UTF-8')
        if text is None or (text and not text.isprintable()):raise RuntimeError('Invalid currency text')
        decoded[p]=text
    definitions=[]
    for p,b,name,short,symbol,value in records:
        if not decoded[name]:raise RuntimeError('Currency name is missing')
        definitions.append(dict(id=struct.unpack_from('<I',b,8)[0],name=decoded[name],shortName=decoded[short],symbol=decoded[symbol],value=value,valueBytes=b[0x38:0x3c].hex(),address=hex(p)))
    if len({d['name'] for d in definitions})!=len(definitions) or len({d['id'] for d in definitions})!=len(definitions):raise RuntimeError('Duplicate currency identity')
    again=session.read([(root,8),(table+0x88,8),(vector,24),(start,end-start)])
    if again[root]!=root_bytes or again[table+0x88]!=body[0x88:0x90] or again[vector]!=header or again[start]!=array:raise RuntimeError('Currency collection changed during capture')
    return dict(status='verified',definitions=definitions,count=len(definitions),rootRVA=hex(ROOT_RVA),tableAddress=hex(table),vectorAddress=hex(vector),representation='pointer to database table; +0x88 points to begin/end/capacity vector of record pointers',layout=dict(name='0x18',shortName='0x20',symbol='0x30',value='0x38 float32 little-endian'),conversion='display = raw * value; float32 multiplier promoted to double; whole-unit rounding',seconds=round(time.monotonic()-began,4),remoteBytesRead=session.bytes-before_bytes,remoteReadCalls=session.calls-before_calls)

def capture_currencies(session,base):
    # A missing currency table must never substitute a guessed or stale multiplier.
    try:return read_currencies(session,base)
    except (RuntimeError,struct.error) as error:return dict(status='unresolved',definitions=[],reason=str(error))

"""Exact-build, read-only relationship decoder; all remote reads are batched pages."""
import datetime as dt
import struct
import time
from collections import Counter
from live_player import NameResolver

TEAM_RVA = 0x5216ee8
CLUB_RVA = 0x51f9ba8
FULL_RVA = 0x51ff9a8
LOAN_RVA = 0x5209338
TRIAL_RVA = 0x50ff308
B_CLUB_RVA = 0x51f83c0
KINDS = {FULL_RVA:'full_contract', LOAN_RVA:'loan_contract',
         TRIAL_RVA:'trial_contract', B_CLUB_RVA:'b_club_contract'}
DEFINITIONS = {
    'currentTeam':'u64 player+0x128 -> TEAM; UID u32 team+0xc',
    'currentClub':'u64 team+0x30 -> CLUB; UID u32 club+0xc; name u64 club+0xc0 -> length-prefixed UTF-8',
    'employmentContract':'u64 person+0x98 -> FULL_CONTRACT; owner +8 must equal person+0x140; employer TEAM +0x10',
    'weeklyWage':'u32 FULL_CONTRACT+0x18; raw internal money per week; currency unresolved; zero retained',
    'contractExpiry':'u16 day/year FULL_CONTRACT+0x40/+0x42; day & 0x1ff; year 1900 remains unresolved',
    'askingPrice':'i32 player+0x1c8; raw internal money; no decoding or currency conversion; zero retained, negative sentinel unresolved',
    'playerValue':'Unresolved: no verified owning field/representation. Asking price is not substituted.',
    'auxiliaryContracts':'person+0xa0 -> 16-byte holder: +0 LOAN/TRIAL_CONTRACT, +8 B_CLUB_CONTRACT; owner at +8, team +0x10',
    'loanState':'Derived from LOAN_CONTRACT and agreement between borrowing club and current club; conflicting relationships unresolved',
    'freeAgentState':'Derived true only if current team, full contract and both auxiliary slots are absent; trial/loan without full employment unresolved',
}


def u64(b, off=0): return struct.unpack_from('<Q', b, off)[0]
def valid_pointer(a): return 0x100000000 <= a < 0x100000000000 and a % 8 == 0

def state(status, **fields): return dict(status=status, **fields)
def absent(reason): return state('unavailable', reason=reason)
def unresolved(reason, **fields): return state('unresolved', reason=reason, **fields)

def extract_anchor(address, person, b):
    return dict(owner=address+person+0x140, team=u64(b,0x128),
                contract=u64(b,person+0x98), holder=u64(b,person+0xa0),
                askingPriceRaw=struct.unpack_from("<i",b,0x1c8)[0], askingPriceAddress=hex(address+0x1c8))

def decode_asking_price(raw, address):
    fields=dict(raw=raw, unit='internal_money', currency=None, currencyStatus='unresolved',
                sourceAddress=address, offset='0x1c8', representation='signed_int32_little_endian',
                label='Asking Price')
    if raw < 0:
        return unresolved('Negative asking-price sentinel; monetary meaning unresolved', **fields)
    return state('verified', **fields)

def decode_expiry(b):
    raw_day, year = struct.unpack_from('<HH',b,0x40)
    day = raw_day & 0x1ff
    raw = dict(rawDay=raw_day, rawYear=year, flags=raw_day>>9)
    if not 2000 <= year <= 2200 or not 1 <= day <= 366:
        return unresolved('No established expiry date; sentinel/invalid representation retained', date=None, **raw)
    value = dt.date(year,1,1)+dt.timedelta(days=day-1)
    if value.year != year:
        return unresolved('Day exceeds length of year', date=None, **raw)
    return state('derived',date=value.isoformat(),**raw)


class TransferResolver:
    def __init__(self, session, base, memory=None):
        self.mem = memory or NameResolver(session)
        self.base = base
        self.teams = {}
        self.clubs = {}

    def preload(self, pointers, length):
        self.mem.preload([(a,length) for a in set(pointers) if valid_pointer(a)])

    def typed(self, a, length, allowed):
        if not a: return None, absent('Null relationship pointer')
        if not valid_pointer(a): return None, unresolved('Malformed pointer',address=hex(a))
        b = self.mem.get(a,length)
        if b is None or len(b)!=length:
            return None, unresolved('Unreadable related object',address=hex(a))
        rva = u64(b)-self.base
        if rva not in allowed:
            return None, unresolved('Unknown related-object vtable',address=hex(a),vtableRVA=hex(rva))
        return b, state('verified',address=hex(a))

    def contract(self, a, owner, allowed):
        length = 0x48 if FULL_RVA in allowed else 0x18
        b, result = self.typed(a,length,allowed)
        if b is None: return result, None
        if u64(b,8)!=owner:
            return unresolved('Contract owner does not match player identity subobject',
                              address=hex(a),ownerAddress=hex(u64(b,8))), None
        result.update(kind=KINDS[u64(b)-self.base],ownerAddress=hex(owner),teamAddress=hex(u64(b,16)))
        return result, b

    def holder(self, a):
        if not a:return (0,0),None
        if not valid_pointer(a):return None,'Malformed auxiliary holder pointer'
        b = self.mem.get(a,16)
        if b is None or len(b)!=16:return None,'Unreadable auxiliary holder'
        return struct.unpack('<2Q',b),None

    def resolve_teams(self, addresses):
        self.preload(addresses,0x38)
        for a in set(addresses):
            b, result = self.typed(a,0x38,{TEAM_RVA})
            if b is not None:
                result.update(uid=struct.unpack_from('<I',b,12)[0],
                              adjacentID=struct.unpack_from('<I',b,16)[0],clubAddress=hex(u64(b,48)))
            self.teams[a] = result
        clubs = {int(t['clubAddress'],16) for t in self.teams.values() if t['status']=='verified'}
        self.preload(clubs,0xd0)
        strings = {}
        for a in clubs:
            b, result = self.typed(a,0xd0,{CLUB_RVA})
            if b is not None:
                result.update(uid=struct.unpack_from('<I',b,12)[0])
                strings[a] = u64(b,0xc0)
            self.clubs[a] = result
        # Club names are direct strings, not player-name entry indirections.
        self.mem.preload([(a,4) for a in set(strings.values())])
        lengths = {}
        for a in set(strings.values()):
            b = self.mem.get(a,4) if 0x100000000<=a<0x100000000000 else None
            if b is not None:
                n = struct.unpack('<I',b)[0]
                if 0<n<=512:lengths[a]=n
        self.mem.preload([(a+4,n) for a,n in lengths.items()])
        for club,a in strings.items():
            raw = self.mem.get(a+4,lengths[a]) if a in lengths else None
            try: name = raw.decode('utf-8') if raw is not None else None
            except UnicodeDecodeError: name=None
            # Legitimate club names can contain Unicode format characters (e.g. U+200B).
            if name is not None and any(ord(c)<32 or ord(c)==127 for c in name):name=None
            self.clubs[club].update(name=name,nameStatus='verified' if name else 'unresolved')
        for team in self.teams.values():
            if team['status']=='verified':team['club']=self.clubs[int(team['clubAddress'],16)]

    def populate(self, players, anchors):
        began = time.monotonic()
        self.preload((a['holder'] for a in anchors),16)
        slots = [self.holder(a['holder']) for a in anchors]
        self.preload((a['contract'] for a in anchors),0x48)
        self.preload((p for (pair,error) in slots if pair for p in pair),0x18)
        decoded = []
        team_addresses = {a['team'] for a in anchors}
        for a,(pair,error) in zip(anchors,slots):
            full,b = self.contract(a['contract'],a['owner'],{FULL_RVA})
            if error:
                aux = unresolved(error,holderAddress=hex(a['holder']))
            else:
                first,_ = self.contract(pair[0],a['owner'],{LOAN_RVA,TRIAL_RVA})
                second,_ = self.contract(pair[1],a['owner'],{B_CLUB_RVA})
                aux = state('unresolved' if any(c['status']=='unresolved' for c in (first,second)) else 'verified',
                            holderAddress=hex(a['holder']),loanOrTrial=first,bClub=second)
                for c in (first,second):
                    if c['status']=='verified':team_addresses.add(int(c['teamAddress'],16))
            if b is not None:team_addresses.add(u64(b,16))
            decoded.append((full,b,aux))
        self.resolve_teams(team_addresses)
        for player,a,(full,b,aux) in zip(players,anchors,decoded):
            current = self.teams[a['team']]
            club = current.get('club',absent('No current team') if current['status']=='unavailable'
                               else unresolved('Current team unresolved'))
            if b is not None:
                full['team'] = self.teams[u64(b,16)]
                wage = state('verified',raw=struct.unpack_from('<I',b,24)[0],unit='internal_money_per_week',
                             currency=None,currencyStatus='unresolved',sourceContract=full['address'])
                expiry = decode_expiry(b)
            else:
                wage = state(full['status'],raw=None,reason=full['reason'])
                expiry = state(full['status'],date=None,reason=full['reason'])
            for key in ('loanOrTrial','bClub'):
                c = aux.get(key,{})
                if c.get('status')=='verified':c['team']=self.teams[int(c['teamAddress'],16)]
            loan = self.loan_state(aux,current)
            free = self.free_agent_state(full,aux,current)
            player.transfers = dict(currentTeam=current,currentClub=club,employmentContract=full,
                                    weeklyWage=wage,contractExpiry=expiry,
                                    askingPrice=decode_asking_price(a["askingPriceRaw"],a["askingPriceAddress"]),
                                    playerValue=unresolved('Owning field and raw value representation not mapped',raw=None),
                                    auxiliaryContracts=aux,loanState=loan,freeAgentState=free)
        coverage = {field:dict(Counter(p.transfers[field]['status'] for p in players)) for field in DEFINITIONS}
        return dict(definitions=DEFINITIONS,coverage=coverage,
                    auxiliaryKinds=dict(Counter(c['kind'] for p in players
                        for c in (p.transfers['auxiliaryContracts'].get('loanOrTrial',{}),
                                  p.transfers['auxiliaryContracts'].get('bClub',{})) if c.get('status')=='verified')),
                    loanStates=dict(Counter(str(p.transfers['loanState']['value']) for p in players)),
                    freeAgentStates=dict(Counter(str(p.transfers['freeAgentState']['value']) for p in players)),
                    distinctTeams=len(self.teams)-int(0 in self.teams),distinctClubs=len(self.clubs)-int(0 in self.clubs),
                    clubNameCoverage=dict(Counter(c.get('nameStatus',c['status']) for c in self.clubs.values())),
                    pages=len(self.mem.pages),seconds=round(time.monotonic()-began,4))

    @staticmethod
    def loan_state(aux,current):
        if aux['status']=='unresolved':return unresolved('Auxiliary relationship unresolved',value=None)
        first = aux['loanOrTrial']
        if first.get('kind')!='loan_contract':return state('derived',value=False,rule='No linked LOAN_CONTRACT')
        borrowing = first['team'].get('club',{})
        club = current.get('club',{})
        if borrowing.get('status')!='verified' or club.get('status')!='verified' or borrowing.get('address')!=club.get('address'):
            return unresolved('Linked loan borrowing club disagrees with or cannot resolve current club',value=None)
        return state('derived',value=True,rule='Owner-linked LOAN_CONTRACT borrowing club matches current club; game-date validity not established')

    @staticmethod
    def free_agent_state(full,aux,current):
        if full['status']=='verified':return state('derived',value=False,rule='Owner-linked full employment contract exists')
        if full['status']=='unavailable' and current['status']=='unavailable' and aux['status']=='verified' and all(
                aux[k]['status']=='unavailable' for k in ('loanOrTrial','bClub')):
            return state('derived',value=True,rule='No current team, employment or auxiliary contract')
        return unresolved('Employment absence alone does not establish free-agent state',value=None)

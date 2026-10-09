"""Structured player model and exact-build layouts."""
import datetime as dt
import struct
from dataclasses import dataclass, fields

POSITION_NAMES = ('GK','SW','DL','DC','DR','DM','ML','MC','MR','AML','AMC','AMR','ST','WBL','WBR')
# Attribute slots follow their physical order in the FM24 object.
ATTRIBUTE_NAMES = (
    'crossing','dribbling','finishing','heading','long_shots','marking','off_the_ball',
    'passing','penalty_taking','tackling','vision','handling','aerial_reach',
    'command_of_area','communication','kicking','throwing','anticipation','decisions',
    'one_on_ones','positioning','reflexes','first_touch','technique','left_foot',
    'right_foot','flair','corners','teamwork','work_rate','long_throws','eccentricity',
    'rushing_out','punching','acceleration','free_kick_taking','strength','stamina',
    'pace','jumping_reach','leadership','dirtiness','balance','bravery','consistency',
    'aggression','agility','important_matches','injury_proneness','versatility',
    'natural_fitness','determination','composure','concentration')
HIDDEN = {'dirtiness','consistency','important_matches','injury_proneness','versatility'}
FEET = {'left_foot','right_foot'}
PERSONALITY_COMPONENTS = ('adaptability','ambition','loyalty','pressure',
                          'professionalism','sportsmanship','temperament','controversy')
# Preferred-move IDs are 1-based; label provenance is in docs/ATTRIBUTION.md.
PPM_LABELS = {
    1: 'Runs with ball down left',
    2: 'Runs with ball down right',
    3: 'Runs with ball through centre',
    4: 'Gets into opposition area',
    5: 'Moves into channels',
    6: 'Gets forward whenever possible',
    7: 'Plays short simple passes',
    8: 'Tries killer balls often',
    9: 'Shoots from distance',
    10: 'Shoots with power',
    11: 'Places shots',
    12: 'Curls ball',
    13: 'Likes to round keeper',
    14: 'Likes to try to beat offside trap',
    15: 'Uses outside of foot',
    16: 'Marks opponent tightly',
    17: 'Winds up opponents',
    18: 'Argues with officials',
    19: 'Plays with back to goal',
    20: 'Comes deep to get ball',
    21: 'Plays one-twos',
    22: 'Likes to lob keeper',
    23: 'Dictates tempo',
    24: 'Attempts overhead kicks',
    25: 'Looks for pass rather than attempting to score',
    26: 'Plays no through balls',
    27: 'Stops play',
    28: 'Knocks ball past opponent',
    29: 'Moves ball to right foot before dribble attempt',
    30: 'Moves ball to left foot before dribble attempt',
    31: 'Dwells on ball',
    32: 'Arrives late in opponents area',
    33: 'Tries to play way out of trouble',
    34: 'Stays back at all times',
    35: 'Avoids using weaker foot',
    36: 'Tries tricks',
    37: 'Tries long range free kicks',
    38: 'Dives into tackles',
    39: 'Does not dive into tackles',
    40: 'Cuts inside',
    41: 'Hugs line',
    42: 'Gets crowd going',
    43: 'Tries first time shots',
    44: 'Tries long range passes',
    45: 'Likes ball played into feet',
    46: 'Hits free kick with power',
    47: 'Likes to beat man repeatedly',
    48: 'Likes to switch ball to other flank',
    49: 'Will retire at top',
    50: 'Will play football as long as possible',
    51: 'Possesses long flat throw',
    52: 'Runs with ball often',
    53: 'Runs with ball rarely',
    54: 'Attemps to develop weaker foot',
    55: 'Static target man',
    56: 'Uses Long Throw to start Counter Attack',
    57: 'Refrains from taking Long Shots',
    58: 'Cuts Inside from Left Wing',
    59: 'Cuts Inside from Right Wing',
    60: 'Crosses early',
    61: 'Brings ball out of defence',
    64: 'Plays Ball with feet',
}
TRAIT_LABELS = {ppm_id-1: name for ppm_id,name in PPM_LABELS.items()}

FIELD_DEFINITIONS = {
    'uid': {'status':'verified','layout':'u32 person+0x14c'},
    'nameParts': {'status':'verified','layout':'person+0x28/0x30/0x38 -> entry -> u32 byte length + UTF-8'},
    'name': {'status':'derived','rule':'common name, otherwise first name + surname'},
    'birthDate': {'status':'derived','layout':'u16 day-of-year/year at person+0x14/0x16'},
    'age': {'status':'unresolved','reason':'No trusted capture-scoped gameDate supplied yet; host date and old captures are not used'},
    'ca': {'status':'verified','layout':'u16 player+0x1f8'},
    'pa': {'status':'verified','layout':'u16 player+0x1fa'},
    'positions': {'status':'verified','layout':'15 u8 ratings at player+0x200; 1..20'},
    'rawAttributes': {'status':'verified','layout':'54 u8 slots at player+0x20f'},
    'visibleAttributes': {'status':'derived','rule':'47 named slots; max(1,min(20,(raw+2)//5)) for raw 1..100'},
    'hiddenAttributes': {'status':'derived','rule':'5 named slots using the same scale'},
    'footStrengths': {'status':'derived','rule':'left/right at attribute slots 24/25, same scale'},
    'personalityComponents': {'status':'verified','layout':'8 i8 values at person+0x48, direct 1..20; order verified against named accessors and FM24 native behavior'},
    'personalityContext': {'status':'verified','layout':'flags byte at person+0x158; bit 3 enables negative personality labels in the FM24 classifier; read from existing object block'},
    'heightCM': {'status':'verified','layout':'u16 player+0x146'},
    'weightKG': {'status':'verified','layout':'u16 player+0x144'},
    'reputation': {'status':'verified','layout':'u16 home/current/world at player+0x1f2/+0x1f4/+0x1f6',
                   'order':['home','current','world'],
                   'evidence':'Static current-layout interoperability evidence; same layout as verified Asking Price, height and weight'},
    'traits': {'status':'verified','layout':'u64 person+0xc0',
               'labelCoverage':'Static resource IDs 1–61 and 64 mapped via bit=ID-1; bits 61/62 remain unresolved'},
}

@dataclass(slots=True)
class LivePlayer:
    index: int
    uid: int
    entity: int
    address: str
    subtype: str
    name: str | None
    nameParts: dict
    birthDate: str
    age: int | None
    ca: int
    pa: int
    positions: dict
    rawAttributes: list
    visibleAttributes: dict
    hiddenAttributes: dict
    footStrengths: dict
    personalityComponents: dict
    heightCM: int | None
    weightKG: int | None
    reputation: dict
    traits: dict
    fieldStatus: dict
    issues: list
    transfers: dict | None = None
    nationality: dict | None = None
    personalityContext: dict | None = None

    def to_dict(self):
        return {f.name:getattr(self,f.name) for f in fields(self)}

class LivePlayerCache:
    """A capture-scoped local object index. No lazy reads or process access."""
    def __init__(self, context, players):
        self.context = context
        self.players = players
        self.by_uid = {p.uid:p for p in players}
        if len(self.by_uid) != len(players):
            raise RuntimeError('Duplicate UIDs in structured model')

    def snapshot(self):
        return dict(self.context, players=[p.to_dict() for p in self.players])

    @classmethod
    def from_snapshot(cls, snapshot):
        if snapshot.get('modelVersion') not in (2,3):
            raise ValueError('Unsupported LivePlayer cache version')
        return cls({k:v for k,v in snapshot.items() if k!='players'},
                   [LivePlayer(**p) for p in snapshot['players']])

def decode_player(index, address, subtype, person, b):
    """Decode only local object bytes; optional bad fields never drop a player."""
    u16=lambda off:struct.unpack_from('<H',b,off)[0]
    uid, adjacent = struct.unpack_from('<II',b,person+0x14c)
    ca,pa=u16(0x1f8),u16(0x1fa)
    day,year=u16(person+0x14),u16(person+0x16)
    if not (0<uid<0xffffffff and 0<ca<=200 and 0<pa<=200 and
            1850<=year<=2100 and 1<=day<=366):
        raise RuntimeError(f'Invalid core identity at {address:x}')
    birth=dt.date(year,1,1)+dt.timedelta(days=day-1)
    if birth.year!=year:raise RuntimeError('Invalid birth date')
    status={k:v['status'] for k,v in FIELD_DEFINITIONS.items()}
    status['nationality']='unresolved'  # Populated through the typed nation relationship.
    issues=[]
    def issue(field, state, message):
        if status[field] != 'inconsistent':status[field]=state
        issues.append({'field':field,'status':state,'reason':message})
    def bounded(value,low,high,field):
        if low<=value<=high:return value
        issue(field,'unresolved' if value==0 else 'inconsistent',f'Raw value {value} outside {low}..{high}')
        return None
    raw=list(b[0x20f:0x245]);visible={};hidden={};feet={}
    for name,value in zip(ATTRIBUTE_NAMES,raw):
        field='footStrengths' if name in FEET else 'hiddenAttributes' if name in HIDDEN else 'visibleAttributes'
        v=bounded(value,1,100,field)
        display=max(1,min(20,(v+2)//5)) if v is not None else None
        (feet if name in FEET else hidden if name in HIDDEN else visible)[name]=display
    positions={name:bounded(v,1,20,'positions') for name,v in zip(POSITION_NAMES,b[0x200:0x20f])}
    components={name:bounded(v,1,20,'personalityComponents') for name,v in zip(PERSONALITY_COMPONENTS,struct.unpack_from('<8b',b,person+0x48))}
    height=bounded(u16(0x146),90,250,'heightCM');weight=bounded(u16(0x144),25,250,'weightKG')
    rep=list(struct.unpack_from('<3H',b,0x1f2))
    if any(v>10000 for v in rep):issue('reputation','inconsistent','Raw reputation slot exceeds 10000')
    mask=struct.unpack_from('<Q',b,person+0xc0)[0]
    bits=[bit for bit in range(64) if mask&(1<<bit)]
    traits={'rawMask':f'0x{mask:016x}', 'mapped':[{'bit':bit,'name':TRAIT_LABELS[bit]} for bit in bits if bit in TRAIT_LABELS],
            'unresolvedBits':[bit for bit in bits if bit not in TRAIT_LABELS]}
    if traits['unresolvedBits']:status['traits']='unresolved'
    player = LivePlayer(index,uid,struct.unpack_from('<I',b,person+0x148)[0],hex(address),subtype,
        None,{},birth.isoformat(),None,ca,pa,positions,raw,visible,hidden,feet,components,
        height,weight,dict(zip(('home','current','world'),(v if v<=10000 else None for v in rep)),rawSlots=rep),traits,status,issues)
    flags = b[person+0x158]
    player.personalityContext = {'status':'verified', 'rawFlagsByte':flags,
        'negativeLabelsAllowed':bool(flags & 8)}
    return player, adjacent

class NameResolver:
    """Resolve only pointers read from person objects. Deduplicate both pointer layers."""
    PAGE=16384
    MAX_NAME_BYTES=512
    def __init__(self,session):
        self.session=session
        self.pages={}
        self.names={0:('',None)}
    def preload(self,pairs):
        pages=set()
        for a,n in pairs:
            if not (0x100000000<=a<0x100000000000 and 0<n<=self.MAX_NAME_BYTES+4):continue
            pages.update(range(a&~(self.PAGE-1),((a+n-1)&~(self.PAGE-1))+self.PAGE,self.PAGE))
        needed=sorted(pages-self.pages.keys())
        for i in range(0,len(needed),400):
            self.pages.update(self.session.read([(p,self.PAGE) for p in needed[i:i+400]],strict=False))
    def get(self,a,n):
        out=bytearray()
        while n:
            base=a&~(self.PAGE-1);size=min(n,self.PAGE-(a-base));page=self.pages.get(base)
            if page is None:return None
            out.extend(page[a-base:a-base+size]);a+=size;n-=size
        return bytes(out)
    def resolve(self,entries):
        entries=set(entries)-{0}
        self.preload([(a,8) for a in entries])
        strings={}
        for a in entries:
            raw=self.get(a,8)
            if raw is None:self.names[a]=(None,'unreadable name entry');continue
            target=struct.unpack('<Q',raw)[0]
            if not 0x100000000<=target<0x100000000000:
                self.names[a]=(None,'invalid name-string pointer');continue
            strings[a]=target
        self.preload([(a,4) for a in set(strings.values())])
        lengths={}
        for a in set(strings.values()):
            h=self.get(a,4)
            n=struct.unpack('<I',h)[0] if h else None
            if n is not None and n<=self.MAX_NAME_BYTES:lengths[a]=n
        self.preload([(a+4,n) for a,n in lengths.items() if n])
        decoded={}
        for a,n in lengths.items():
            raw=self.get(a+4,n)
            try:
                text=raw.decode('utf-8') if raw is not None else None
                if text is not None and (not text or text.isprintable()):decoded[a]=text
            except UnicodeDecodeError:pass
        for a,target in strings.items():
            name=decoded.get(target)
            self.names[a]=(name,None if name is not None else 'invalid, oversized or unreadable UTF-8 name string')
        return self.names

def apply_names(player, pointers, names):
    parts={};errors=[]
    for key,p in zip(('first','surname','common'),pointers):
        text,error=names.get(p,(None,'unresolved name pointer'))
        parts[key]=text
        if error:errors.append(key+': '+error)
    player.nameParts=parts
    if errors:
        player.fieldStatus['nameParts']='unresolved'
        player.fieldStatus['name']='unresolved'
        player.issues.append({'field':'name','status':'unresolved','reason':'; '.join(errors)})
    if parts['common']:
        player.name=parts['common']
    elif parts['first'] is not None and parts['surname'] is not None:
        player.name=' '.join(x for x in (parts['first'],parts['surname']) if x) or None
    if player.name is None:
        player.fieldStatus['name']='unresolved'
        if not errors:player.issues.append({'field':'name','status':'unresolved','reason':'All name parts are empty'})

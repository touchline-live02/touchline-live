"""Offline relationship tests: no target process, money conversions or UI access."""
import struct
import unittest
from types import SimpleNamespace
from live_transfers import (TransferResolver, extract_anchor, decode_expiry, decode_asking_price,
                            TEAM_RVA,CLUB_RVA,FULL_RVA,LOAN_RVA,TRIAL_RVA,B_CLUB_RVA)
from live_player import LivePlayerCache
from test_reader import FakeSession
from touchline_live import capture

BASE=0x100000000
OWNER=0x200000140
TEAM=0x300000000
EMPLOYER=0x300001000
CLUB=0x400000000
PARENT=0x400001000
FULL=0x500000000
HOLDER=0x500001000
LOAN=0x500002000
BCLUB=0x500003000
NAME=0x600000004 # Direct strings need not be pointer-aligned.

class Memory:
    def __init__(self):self.data={};self.pages={};self.requests=[]
    def preload(self,pairs):self.requests.append(list(pairs))
    def get(self,a,n):
        for start,b in self.data.items():
            if start<=a and a+n<=start+len(b):return bytes(b[a-start:a-start+n])
        return None
    def obj(self,a,vt,length=0xd0):
        b=bytearray(length);struct.pack_into('<Q',b,0,BASE+vt);self.data[a]=b;return b

class TransferTests(unittest.TestCase):
    def fixture(self,aux=None):
        m=Memory()
        for a,c in [(TEAM,CLUB),(EMPLOYER,PARENT)]:
            b=m.obj(a,TEAM_RVA);struct.pack_into('<II',b,12,713 if a==TEAM else 740,999);struct.pack_into('<Q',b,48,c)
        for i,c in enumerate((CLUB,PARENT)):
            b=m.obj(c,CLUB_RVA);struct.pack_into('<I',b,12,713 if c==CLUB else 740);struct.pack_into('<Q',b,0xc0,NAME+i*0x100)
            text=('Southampton' if c==CLUB else 'Wolverhampton Wanderers').encode();m.data[NAME+i*0x100]=bytearray(struct.pack('<I',len(text))+text)
        b=m.obj(FULL,FULL_RVA);struct.pack_into('<QQI',b,8,OWNER,EMPLOYER,28076);struct.pack_into('<HH',b,0x40,182,2028)
        anchor=dict(owner=OWNER,team=TEAM,contract=FULL,holder=HOLDER if aux else 0,askingPriceRaw=0,askingPriceAddress=hex(OWNER-0x140+0x1c8))
        if aux:
            m.data[HOLDER]=bytearray(struct.pack('<2Q',LOAN if aux!='b' else 0,BCLUB if aux in ('b','both') else 0))
            if aux!='b':
                b=m.obj(LOAN,TRIAL_RVA if aux=='trial' else LOAN_RVA);struct.pack_into('<QQI',b,8,OWNER,TEAM,11230)
            if aux in ('b','both'):
                b=m.obj(BCLUB,B_CLUB_RVA);struct.pack_into('<QQ',b,8,OWNER,EMPLOYER)
        return m,anchor
    def run_decode(self,m,a):
        p=SimpleNamespace();report=TransferResolver(None,BASE,m).populate([p],[a]);return p.transfers,report
    def test_loan_owner_clubs_and_full_salary(self):
        m,a=self.fixture('loan');p,report=self.run_decode(m,a)
        self.assertEqual(p['currentClub']['name'],'Southampton')
        self.assertEqual(p['employmentContract']['team']['club']['name'],'Wolverhampton Wanderers')
        self.assertEqual(p['weeklyWage']['raw'],28076) # Not auxiliary 11230.
        self.assertIsNone(p['weeklyWage']['currency'])
        self.assertEqual(p['contractExpiry']['date'],'2028-06-30')
        self.assertTrue(p['loanState']['value'])
        self.assertIsNone(p['playerValue']['raw'])
        self.assertEqual(p['playerValue']['status'],'unresolved')
    def test_foreign_owner_never_used(self):
        m,a=self.fixture();struct.pack_into('<Q',m.data[FULL],8,OWNER+8);p,_=self.run_decode(m,a)
        self.assertEqual(p['employmentContract']['status'],'unresolved')
        self.assertEqual(p['weeklyWage']['status'],'unresolved')
        self.assertIsNone(p['weeklyWage']['raw'])
    def test_b_club_is_not_loan(self):
        m,a=self.fixture('b');p,_=self.run_decode(m,a)
        self.assertFalse(p['loanState']['value'])
        self.assertEqual(p['auxiliaryContracts']['bClub']['kind'],'b_club_contract')
    def test_trial_without_employment_not_declared_free_agent(self):
        m,a=self.fixture('trial');a['contract']=0;p,_=self.run_decode(m,a)
        self.assertFalse(p['loanState']['value'])
        self.assertIsNone(p['freeAgentState']['value'])
        self.assertEqual(p['weeklyWage']['status'],'unavailable')
    def test_two_slots_preserved(self):
        m,a=self.fixture('both');p,r=self.run_decode(m,a)
        self.assertEqual(r['auxiliaryKinds'],{'loan_contract':1,'b_club_contract':1})
        self.assertTrue(p['loanState']['value'])
    def test_disagreeing_loan_clubs_unresolved(self):
        m,a=self.fixture('loan');struct.pack_into('<Q',m.data[LOAN],16,EMPLOYER);p,_=self.run_decode(m,a)
        self.assertEqual(p['loanState']['status'],'unresolved')
        self.assertIsNone(p['loanState']['value'])
    def test_reserve_team_same_club_accepted(self):
        m,a=self.fixture('loan');struct.pack_into('<Q',m.data[EMPLOYER],48,CLUB);struct.pack_into('<Q',m.data[LOAN],16,EMPLOYER)
        p,_=self.run_decode(m,a);self.assertTrue(p['loanState']['value'])
    def test_absence_differs_from_unreadable(self):
        m,a=self.fixture();a.update(team=0,contract=0);p,_=self.run_decode(m,a)
        self.assertTrue(p['freeAgentState']['value'])
        a['holder']=HOLDER;p,_=self.run_decode(m,a)
        self.assertEqual(p['auxiliaryContracts']['status'],'unresolved')
        self.assertIsNone(p['freeAgentState']['value'])
    def test_zero_salary_preserved(self):
        m,a=self.fixture();struct.pack_into('<I',m.data[FULL],24,0);p,_=self.run_decode(m,a)
        self.assertEqual(p['weeklyWage']['raw'],0);self.assertEqual(p['weeklyWage']['status'],'verified')
    def test_bad_related_type_and_bad_name(self):
        m,a=self.fixture();struct.pack_into('<Q',m.data[FULL],0,BASE+123);struct.pack_into('<I',m.data[NAME],0,9999)
        p,_=self.run_decode(m,a);self.assertEqual(p['weeklyWage']['status'],'unresolved')
        self.assertEqual(p['currentClub']['nameStatus'],'unresolved')
    def test_flagged_date_leap_and_sentinel(self):
        b=bytearray(0x48)
        for day,year,date in [(0x7e00|181,2026,'2026-06-30'),(366,2028,'2028-12-31'),(366,2027,None),(2,1900,None)]:
            struct.pack_into('<HH',b,0x40,day,year);self.assertEqual(decode_expiry(b)['date'],date)
    def test_unicode_format_character_in_club_name(self):
        m,a=self.fixture();text='FC Buckow/\u200bWaldsieversdorf'.encode('utf8')
        m.data[NAME]=struct.pack('<I',len(text))+text
        p,_=self.run_decode(m,a)
        self.assertEqual(p['currentClub']['name'],text.decode('utf8'))
        self.assertEqual(p['currentClub']['nameStatus'],'verified')
    def test_asking_price_signed_raw_and_currency_separation(self):
        for raw in (0,313768,17426704,300000000):
            price=decode_asking_price(raw,'0x2000001c8')
            self.assertEqual(price['status'],'verified');self.assertEqual(price['raw'],raw)
            self.assertIsNone(price['currency']);self.assertEqual(price['label'],'Asking Price')
        self.assertEqual(decode_asking_price(-1,'0x2000001c8')['status'],'unresolved')
        self.assertEqual(decode_asking_price(-1,'0x2000001c8')['raw'],-1)
    def test_asking_price_from_existing_object_bytes_for_both_types(self):
        for person,size in ((0x268,0x3c8),(0x350,0x4b0)):
            for raw in (300000000,313768,0,-1):
                block=bytearray(size);struct.pack_into('<i',block,0x1c8,raw)
                self.assertEqual(extract_anchor(BASE,person,block)['askingPriceRaw'],raw)
    def test_asking_price_does_not_need_relationship_or_remote_money_read(self):
        m,a=self.fixture();a.update(team=0,contract=0,askingPriceRaw=313768)
        p,r=self.run_decode(m,a)
        self.assertEqual(p['askingPrice']['raw'],313768)
        self.assertEqual(p['askingPrice']['status'],'verified')
        self.assertEqual(p['playerValue']['status'],'unresolved')
        self.assertFalse(any(address==int(a['askingPriceAddress'],16) for pairs in m.requests for address,n in pairs))

    def test_both_player_subtype_anchors(self):
        for person in [0x268,0x350]:
            b=bytearray(0x4b0);struct.pack_into('<Q',b,0x128,TEAM);struct.pack_into('<2Q',b,person+0x98,FULL,HOLDER)
            a=extract_anchor(BASE,person,b);self.assertEqual(a,dict(owner=BASE+person+0x140,team=TEAM,contract=FULL,holder=HOLDER,askingPriceRaw=0,askingPriceAddress=hex(BASE+0x1c8)))
    def test_reads_deduplicated_independent_of_player_count(self):
        m,a=self.fixture('both');players=[SimpleNamespace() for _ in range(1000)]
        TransferResolver(None,BASE,m).populate(players,[a]*1000)
        self.assertLessEqual(len(m.requests),7)
        for pairs in m.requests:self.assertEqual(len(pairs),len(set(pairs)))
    def test_version_two_cache_still_loads(self):
        snapshot=capture(FakeSession());snapshot['modelVersion']=2
        for p in snapshot['players']:p.pop('transfers')
        self.assertIsNone(LivePlayerCache.from_snapshot(snapshot).players[0].transfers)

if __name__=='__main__':unittest.main()

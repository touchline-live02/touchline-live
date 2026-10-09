"""Offline typed primary-nation fixtures; no attachment or nationality inference."""
import copy
import struct
import unittest
from types import SimpleNamespace
from live_nationality import populate_nationalities, NATION_VTABLE_RVA
from live_player import NameResolver, LivePlayerCache
from test_reader import FakeSession
from touchline_live import capture, TYPES

class NationSession:
    base=0x100000000
    page=0x200000000
    def __init__(self):
        self.data=bytearray(32768);self.bytes=self.calls=0;self.missing=set()
        self.nation=self.page+0x100;self.string=self.page+0x500
        struct.pack_into('<Q',self.data,0x100,self.base+NATION_VTABLE_RVA)
        self.set_string(self.string,"Côte d'Ivoire")
    def set_string(self,address,text):
        struct.pack_into('<Q',self.data,0x118,address)
        raw=text.encode();off=address-self.page
        struct.pack_into('<I',self.data,off,len(raw));self.data[off+4:off+4+len(raw)]=raw
    def read(self,pairs,strict=True):
        result={}
        for a,n in pairs:
            self.calls+=1
            if a in self.missing or a<self.page or a+n>self.page+len(self.data):result[a]=None
            else:result[a]=bytes(self.data[a-self.page:a-self.page+n]);self.bytes+=n
        return result

class NationalityTests(unittest.TestCase):
    def resolve(self,s=None,pointer=None,count=1):
        s=s or NationSession()
        players=[SimpleNamespace(nationality=None,fieldStatus={},issues=[]) for _ in range(count)]
        result=populate_nationalities(players,[(s.page+0x1000,s.nation if pointer is None else pointer)]*count,s,s.base)
        return players,result
    def test_direct_utf8_and_provenance(self):
        s=NationSession();ps,summary=self.resolve(s)
        n=ps[0].nationality
        self.assertEqual(n['name'],"Côte d'Ivoire");self.assertEqual(n['status'],'verified')
        self.assertEqual(n['sourceAddress'],hex(s.page+0x1040))
        self.assertEqual(n['address'],hex(s.nation));self.assertEqual(n['nameAddress'],hex(s.string))
        self.assertEqual(summary['coverage'],{'verified':1});self.assertEqual(ps[0].issues,[])
    def test_shared_pages_not_per_player_reads(self):
        s=NationSession();ps,summary=self.resolve(s,count=70000)
        self.assertEqual(summary['distinctNations'],1);self.assertEqual(s.calls,1)
        self.assertEqual(ps[-1].nationality['name'],"Côte d'Ivoire")
    def test_existing_name_pages_reused(self):
        s=NationSession();mem=NameResolver(s);mem.preload([(s.nation,32)])
        p=SimpleNamespace(nationality=None,fieldStatus={},issues=[])
        result=populate_nationalities([p],[(s.page,s.nation)],s,s.base,memory=mem)
        self.assertEqual(result['remoteReadCalls'],0)
    def test_null_is_unavailable_not_unresolved(self):
        ps,r=self.resolve(pointer=0)
        self.assertEqual(ps[0].nationality['status'],'unavailable');self.assertIsNone(ps[0].nationality['name'])
        self.assertEqual(r['remoteReadCalls'],0)
    def test_malformed_and_wrong_type_inconsistent(self):
        for pointer in (1,0x200000001,0x100000000000):
            ps,r=self.resolve(pointer=pointer);self.assertEqual(ps[0].nationality['status'],'inconsistent');self.assertEqual(r['remoteReadCalls'],0)
        s=NationSession();struct.pack_into('<Q',s.data,0x100,s.base+NATION_VTABLE_RVA+8)
        ps,_=self.resolve(s);self.assertEqual(ps[0].nationality['status'],'inconsistent')
    def test_unreadable_object_and_string_unresolved(self):
        s=NationSession();s.missing.add(s.page)
        ps,_=self.resolve(s);self.assertEqual(ps[0].nationality['status'],'unresolved')
        s=NationSession();struct.pack_into('<Q',s.data,0x118,s.page+0x8000)
        ps,_=self.resolve(s);self.assertEqual(ps[0].nationality['status'],'unresolved')
    def test_null_name_does_not_mean_no_nationality(self):
        s=NationSession();struct.pack_into('<Q',s.data,0x118,0)
        ps,_=self.resolve(s);self.assertEqual(ps[0].nationality['status'],'unresolved')
    def test_name_pointer_length_utf8_and_controls(self):
        for n in (0,513,0xffffffff):
            s=NationSession();struct.pack_into('<I',s.data,0x500,n)
            ps,_=self.resolve(s);self.assertEqual(ps[0].nationality['status'],'inconsistent')
        for text in ('\nNorway','\x00','   '):
            s=NationSession();s.set_string(s.string,text)
            ps,_=self.resolve(s);self.assertEqual(ps[0].nationality['status'],'inconsistent')
        s=NationSession();s.data[0x504]=255
        ps,_=self.resolve(s);self.assertEqual(ps[0].nationality['status'],'inconsistent')
        s=NationSession();struct.pack_into('<Q',s.data,0x118,17)
        ps,_=self.resolve(s);self.assertEqual(ps[0].nationality['status'],'inconsistent')
    def test_cross_page_string_and_unreadable_tail(self):
        s=NationSession();s.set_string(s.page+16380,'Türkiye')
        ps,_=self.resolve(s);self.assertEqual(ps[0].nationality['name'],'Türkiye')
        s.missing.add(s.page+16384)
        ps,_=self.resolve(s);self.assertEqual(ps[0].nationality['status'],'unresolved')
    def test_both_subtypes_capture_and_legacy_roundtrip(self):
        s=FakeSession()
        for i in range(3):
            _,person,_=list(TYPES.values())[i%2]
            struct.pack_into('<Q',s.data,i*0x1000+person+0x40,s.page+0xc000)
        struct.pack_into('<Q',s.data,0xc000,s.base+NATION_VTABLE_RVA)
        struct.pack_into('<Q',s.data,0xc018,s.page+0xc100)
        struct.pack_into('<I',s.data,0xc100,6);s.data[0xc104:0xc10a]=b'Norway'
        snapshot=capture(s)
        self.assertEqual(snapshot['fieldCoverage']['nationality'],{'verified':3})
        self.assertEqual({p['subtype'] for p in snapshot['players']},{'player','player_staff'})
        self.assertTrue(all(p['nationality']['name']=='Norway' for p in snapshot['players']))
        self.assertEqual(LivePlayerCache.from_snapshot(snapshot).snapshot(),snapshot)
        old=copy.deepcopy(snapshot)
        for p in old['players']:p.pop('nationality');p['fieldStatus'].pop('nationality')
        restored=LivePlayerCache.from_snapshot(old)
        self.assertTrue(all(p.nationality is None for p in restored.players))
    def test_anchor_count_mismatch_rejected(self):
        s=NationSession()
        with self.assertRaises(ValueError):populate_nationalities([object()],[],s,s.base)

if __name__=='__main__':unittest.main()

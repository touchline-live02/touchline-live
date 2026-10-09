"""Offline rejection tests. These never attach to a process."""
import struct
import unittest
import datetime as dt
from touchline_live import capture, vector, TYPES, ROOT_RVA, PERSON_ROOT_RVA
from live_date import GAME_DATE_RVA
from live_player import LivePlayerCache, NameResolver, decode_player, apply_names

FIXTURE_PLAYERS = {1001: ('Synthetic Forward', '1998-07-21', 195),
                   1002: ('Synthetic Keeper', '1990-10-02', 182),
                   1003: ('Synthetic Player Staff', '2004-03-12', 170)}

class FakeSession:
    bytes = calls = 0
    base = 0x100000000
    page = 0x200000000
    table = 0x300000000
    def __init__(self, unknown=False, change=False):
        self.change = change
        self.table_reads = 0
        self.data = bytearray(65536)
        self.ptrs = []
        profiles = list(TYPES.items())
        for i, (uid, (_, dob, pa)) in enumerate(FIXTURE_PLAYERS.items()):
            a = self.page + i*0x1000
            self.ptrs.append(a)
            vtable, (_, person, _) = profiles[i % 2]
            struct.pack_into('<Q', self.data, i*0x1000, self.base+vtable+(1 if unknown else 0))
            birth = dt.date.fromisoformat(dob)
            struct.pack_into('<HH', self.data, i*0x1000+person+0x14,
                             birth.timetuple().tm_yday, birth.year)
            struct.pack_into('<HH', self.data, i*0x1000+0x1f8, 100, pa)
            # Adjacent UID intentionally differs, as observed on generated players.
            struct.pack_into('<III', self.data, i*0x1000+person+0x148, i+1, uid, 0)
            name = FIXTURE_PLAYERS[uid][0].split(' ',1)
            for j,part in enumerate((name+[''])[:2]):
                entry=self.page+0x8000+i*0x100+j*24
                string=self.page+0x9000+i*0x200+j*0x80
                struct.pack_into('<Q',self.data,i*0x1000+person+0x28+j*8,entry)
                struct.pack_into('<Q',self.data,entry-self.page,string)
                raw=part.encode('utf-8')
                struct.pack_into('<I',self.data,string-self.page,len(raw))
                self.data[string-self.page+4:string-self.page+4+len(raw)]=raw
        self.pointers = struct.pack('<3Q', *self.ptrs)
        self.header = struct.pack('<3Q', self.table, self.table+24, self.table+40)
    def image_base(self): return self.base
    def read(self, pairs, strict=True):
        result = {}
        for a, n in pairs:
            if a == self.base+0x53024b0: raise RuntimeError('Currency store absent in player fixture')
            if a == self.base+GAME_DATE_RVA:
                result[a] = struct.pack("<HH",153+(9<<9),2026)
            elif a in (self.base+ROOT_RVA, self.base+PERSON_ROOT_RVA):
                result[a] = self.header
            elif a == self.table:
                self.table_reads += 1
                data = bytearray(self.pointers)
                if self.change and self.table_reads > 1: data[0] ^= 8
                result[a] = bytes(data)
            elif self.page <= a < self.page+65536:
                result[a] = bytes(self.data[a-self.page:a-self.page+n])
            else: raise AssertionError(hex(a))
        return result

class ReaderTests(unittest.TestCase):
    def test_both_subtypes_and_nonduplicated_uid(self):
        s = capture(FakeSession())
        self.assertEqual(s['collection']['count'], 3)
        self.assertNotIn('verifiedPlayers', s)
        self.assertEqual(s['players'][0]['name'], 'Synthetic Forward')
        self.assertEqual(s['adjacentUIDDifferences'], 3)
        self.assertEqual(s['types'], {'player': 2, 'player_staff': 1})
    def test_capacity_is_not_count(self):
        start, end, cap = vector(FakeSession().header)
        self.assertEqual((end-start)//8, 3)
        self.assertEqual((cap-start)//8, 5)

    def test_dob_and_pa_are_database_values(self):
        session=FakeSession()
        birth=dt.date(2000,7,21)
        struct.pack_into('<HH',session.data,0x268+0x14,birth.timetuple().tm_yday,birth.year)
        struct.pack_into('<H',session.data,0x1fa,190)
        snapshot=capture(session)
        self.assertEqual(snapshot['players'][0]['birthDate'],'2000-07-21')
        self.assertEqual(snapshot['players'][0]['pa'],190)

    def test_no_specific_player_is_required(self):
        snapshot=capture(FakeSession())
        self.assertNotIn(29179241,{row['uid'] for row in snapshot['players']})
        for key in ('prototype', 'phase', 'verifiedPlayers', 'referenceName',
                    'referenceCheck', 'researchCareerDifferences'):
            self.assertNotIn(key, snapshot)
        self.assertTrue(snapshot['collectionStable'])

    def test_custom_player_names_are_allowed(self):
        session=FakeSession();session.data[0x9004]=ord('X')
        self.assertTrue(capture(session)['players'][0]['name'].startswith('X'))

    def test_all_unresolved_names_reject_snapshot(self):
        session=FakeSession()
        for i in range(3):
            for j in range(2):
                struct.pack_into('<I',session.data,0x9000+i*0x200+j*0x80,0)
        with self.assertRaisesRegex(RuntimeError,'valid decoded name'):
            capture(session)

    def test_invalid_core_still_rejects_without_named_reference(self):
        session=FakeSession();struct.pack_into('<H',session.data,0x1f8,201)
        with self.assertRaisesRegex(RuntimeError,'Invalid core identity'):
            capture(session)

    def test_bad_header_rejected(self):
        for h in [(0, 8, 16), (0x200000000, 0x200000010, 0x200000008),
                  (0x200000000, 0x200000009, 0x200000010)]:
            with self.assertRaises(RuntimeError): vector(struct.pack('<3Q', *h))
    def test_unknown_subtype_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'Unmapped player subtype'):
            capture(FakeSession(unknown=True))
    def test_changing_collection_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'collection changed'):
            capture(FakeSession(change=True))

    def test_local_model_roundtrip_has_no_process_dependency(self):
        import json
        snapshot=capture(FakeSession())
        restored=LivePlayerCache.from_snapshot(json.loads(json.dumps(snapshot)))
        self.assertEqual(restored.by_uid[1001].name,'Synthetic Forward')
        self.assertEqual(restored.snapshot(),snapshot)

    def test_legacy_metadata_remains_readable(self):
        snapshot=capture(FakeSession())
        for version in (2,3):
            legacy=dict(snapshot, modelVersion=version, prototype='Touchline Live', phase=3,
                        verifiedPlayers=[dict(snapshot['players'][0], referenceName='Synthetic Forward',
                                              referenceCheck='Structural identity and decoded name',
                                              researchCareerDifferences={})])
            restored=LivePlayerCache.from_snapshot(legacy)
            self.assertEqual(restored.by_uid[1001].name, 'Synthetic Forward')
            self.assertEqual(restored.snapshot(), legacy)

    def test_optional_unknowns_do_not_drop_player(self):
        snapshot=capture(FakeSession())
        p=snapshot['players'][0]
        self.assertIsNone(p['weightKG'])
        self.assertEqual(p['age'],27)
        self.assertEqual(p['reputation']['current'],0)
        self.assertEqual(p['fieldStatus']['weightKG'],'unresolved')

    def test_out_of_range_attribute_not_silently_clamped(self):
        s=FakeSession();s.data[0x20f]=255;s.data[0x210]=0
        p,unused=decode_player(0,s.page,'player',0x268,s.data[:0x3c8])
        self.assertIsNone(p.visibleAttributes['crossing'])
        self.assertEqual(p.rawAttributes[0],255)
        self.assertEqual(p.fieldStatus['visibleAttributes'],'inconsistent')

    def test_unknown_trait_bits_preserved(self):
        s=FakeSession();struct.pack_into('<Q',s.data,0x268+0xc0,(1<<13)|(1<<61)|(1<<62))
        p,unused=decode_player(0,s.page,'player',0x268,s.data[:0x3c8])
        self.assertEqual(p.traits['unresolvedBits'],[61,62])
        self.assertEqual(p.traits['mapped'][0]['bit'],13)

    def test_name_length_limit(self):
        s=FakeSession();struct.pack_into('<I',s.data,0x9000,513)
        resolver=NameResolver(s);names=resolver.resolve([s.page+0x8000])
        self.assertIsNone(names[s.page+0x8000][0])

    def test_unicode_and_common_name_precedence(self):
        s=FakeSession();p,unused=decode_player(0,s.page,'player',0x268,s.data[:0x3c8])
        apply_names(p,(1,2,3),{1:('João',None),2:('Gonçalves',None),3:('Jô',None)})
        self.assertEqual(p.name,'Jô')
        self.assertEqual(p.nameParts['first'],'João')

if __name__ == '__main__': unittest.main()

"""Static interoperability fixtures; no process or external application dependency."""
import json
import pathlib
import struct
import unittest
from live_player import decode_player,TRAIT_LABELS,PPM_LABELS
from test_reader import FakeSession

class TraitTests(unittest.TestCase):
    def decode(self,mask):
        s=FakeSession();struct.pack_into('<Q',s.data,0x268+0xc0,mask)
        p,_=decode_player(0,s.page,'player',0x268,s.data[:0x3c8])
        self.assertEqual(p.traits['rawMask'],f'0x{mask:016x}')
        return p
    def test_static_resource_fixture_and_numbering(self):
        fixture=json.loads((pathlib.Path(__file__).resolve().parents[1]/'docs/evidence/trait-labels.json').read_text())
        self.assertEqual(PPM_LABELS,{int(k):v for k,v in fixture['ppmLabels'].items()})
        self.assertEqual(set(PPM_LABELS),set(range(1,62))|{64})
        for ppm,label in PPM_LABELS.items():
            with self.subTest(ppm=ppm):
                p=self.decode(1<<(ppm-1))
                self.assertEqual(p.traits['mapped'],[{'bit':ppm-1,'name':label}])
                self.assertEqual(p.fieldStatus['traits'],'verified')
                self.assertEqual(p.traits['unresolvedBits'],[])
    def test_existing_independent_five_exact(self):
        expected={13:'Likes to try to beat offside trap',27:'Knocks ball past opponent',41:'Gets crowd going',42:'Tries first time shots',55:'Uses Long Throw to start Counter Attack'}
        self.assertEqual({b:TRAIT_LABELS[b] for b in expected},expected)
    def test_low_middle_high_and_simultaneous(self):
        p=self.decode((1<<0)|(1<<31)|(1<<60)|(1<<63))
        self.assertEqual(p.traits['mapped'],[
            {'bit':0,'name':'Runs with ball down left'},
            {'bit':31,'name':'Arrives late in opponents area'},
            {'bit':60,'name':'Brings ball out of defence'},
            {'bit':63,'name':'Plays Ball with feet'}])
    def test_empty_is_valid(self):
        p=self.decode(0)
        self.assertEqual(p.traits,{'rawMask':'0x0000000000000000','mapped':[],'unresolvedBits':[]})
        self.assertEqual(p.fieldStatus['traits'],'verified')
    def test_only_unsupported_ids_remain_unknown(self):
        for mask,bits in [(1<<61,[61]),(1<<62,[62]),((1<<61)|(1<<62),[61,62])]:
            p=self.decode(mask)
            self.assertEqual(p.traits['unresolvedBits'],bits)
            self.assertEqual(p.traits['mapped'],[])
            self.assertEqual(p.fieldStatus['traits'],'unresolved')
    def test_all_bits_preserves_unsigned_mask_and_known_labels(self):
        p=self.decode(0xffffffffffffffff)
        self.assertEqual(len(p.traits['mapped']),62)
        self.assertEqual(p.traits['unresolvedBits'],[61,62])
        self.assertEqual(p.traits['mapped'][-1],{'bit':63,'name':'Plays Ball with feet'})
        self.assertEqual(p.fieldStatus['traits'],'unresolved')

if __name__=='__main__':unittest.main()

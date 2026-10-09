"""Reputation semantics over existing local player bytes; no live reads."""
import struct
import unittest
from live_player import decode_player
from test_reader import FakeSession
from touchline_live import TYPES

class ReputationTests(unittest.TestCase):
    def decode(self,values,index=0):
        s=FakeSession();offset=index*0x1000
        struct.pack_into('<3H',s.data,offset+0x1f2,*values)
        subtype,person,length=list(TYPES.values())[index]
        p,_=decode_player(index,s.page+offset,subtype,person,s.data[offset:offset+length])
        self.assertEqual(p.reputation['rawSlots'],list(values))
        return p
    def test_exact_order_both_subtypes(self):
        for index in (0,1):
            p=self.decode([1234,5678,9012],index)
            self.assertEqual(p.reputation,{'home':1234,'current':5678,'world':9012,'rawSlots':[1234,5678,9012]})
            self.assertEqual(p.fieldStatus['reputation'],'verified')
    def test_zero_and_upper_boundary_valid(self):
        p=self.decode([0,10000,1])
        self.assertEqual((p.reputation['home'],p.reputation['current'],p.reputation['world']),(0,10000,1))
        self.assertEqual(p.fieldStatus['reputation'],'verified')
    def test_each_invalid_slot_retained_not_clamped(self):
        for i,key in enumerate(('home','current','world')):
            for bad in (10001,65535):
                values=[123,456,789];values[i]=bad;p=self.decode(values)
                self.assertIsNone(p.reputation[key])
                self.assertEqual(p.fieldStatus['reputation'],'inconsistent')
                self.assertIn({'field':'reputation','status':'inconsistent','reason':'Raw reputation slot exceeds 10000'},p.issues)
                for j,other in enumerate(('home','current','world')):
                    if j!=i:self.assertEqual(p.reputation[other],values[j])
    def test_all_invalid_remain_null(self):
        p=self.decode([65535]*3)
        self.assertTrue(all(p.reputation[k] is None for k in ('home','current','world')))
        self.assertEqual(p.fieldStatus['reputation'],'inconsistent')

if __name__=='__main__':unittest.main()

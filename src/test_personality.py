"""Personality layout tests over fixture bytes; no live process access."""
import struct
import unittest
from live_player import decode_player, PERSONALITY_COMPONENTS, FIELD_DEFINITIONS
from test_reader import FakeSession
from touchline_live import TYPES

class PersonalityTests(unittest.TestCase):
    def decode(self, values, flags=0, index=0):
        session=FakeSession();offset=index*0x1000
        subtype,person,length=list(TYPES.values())[index]
        struct.pack_into('<8b',session.data,offset+person+0x48,*values)
        session.data[offset+person+0x158]=flags
        player,_=decode_player(index,session.page+offset,subtype,person,session.data[offset:offset+length])
        return player
    def test_exact_order_and_context_both_subtypes(self):
        for subtype in (0,1):
            p=self.decode(list(range(1,9)),8,subtype)
            self.assertEqual(p.personalityComponents,dict(zip(PERSONALITY_COMPONENTS,range(1,9))))
            self.assertEqual(p.personalityContext,dict(status='verified',rawFlagsByte=8,negativeLabelsAllowed=True))
            self.assertEqual(p.to_dict()['personalityContext'],p.personalityContext)
    def test_only_bit_three_controls_negative_labels(self):
        for flags in range(256):
            p=self.decode([20]*8,flags)
            self.assertEqual(p.personalityContext['negativeLabelsAllowed'],bool(flags&8))
            self.assertEqual(p.personalityContext['rawFlagsByte'],flags)
    def test_invalid_signed_values_never_clamp(self):
        for slot in range(8):
            for value in (-128,-1,0,21,127):
                values=[10]*8;values[slot]=value;p=self.decode(values)
                self.assertIsNone(p.personalityComponents[PERSONALITY_COMPONENTS[slot]])
                self.assertEqual(p.fieldStatus['personalityComponents'],'unresolved' if value==0 else 'inconsistent')
                self.assertTrue(any(str(value) in issue['reason'] for issue in p.issues if issue['field']=='personalityComponents'))
                self.assertTrue(all(p.personalityComponents[k]==10 for j,k in enumerate(PERSONALITY_COMPONENTS) if j!=slot))
    def test_capture_definition_retains_provenance(self):
        self.assertIn('i8',FIELD_DEFINITIONS['personalityComponents']['layout'])
        self.assertIn('person+0x158',FIELD_DEFINITIONS['personalityContext']['layout'])

if __name__=='__main__':unittest.main()

import struct,unittest
from live_currency import read_currencies,capture_currencies,ROOT_RVA,TABLE_VTABLE_RVA,RECORD_VTABLE_RVA
class CurrencySession:
    base=0x100000000;p=0x200000000
    def __init__(self):
        self.bytes=self.calls=0;self.data=bytearray(16384);self.changed=False;self.rootReads=0
        struct.pack_into('<Q',self.data,0x100,self.base+TABLE_VTABLE_RVA)
        struct.pack_into('<Q',self.data,0x188,self.p+0x200)
        struct.pack_into('<3Q',self.data,0x200,self.p+0x300,self.p+0x310,self.p+0x320)
        struct.pack_into('<2Q',self.data,0x300,self.p+0x400,self.p+0x458)
        for i,(name,symbol,value) in enumerate([('Canadian Dollar','$',1.7079838514328003),('European Euro','€',1.1662288904190063)]):
            r=0x400+i*0x58;st=0x800+i*0x200
            struct.pack_into('<QI',self.data,r,self.base+RECORD_VTABLE_RVA,i)
            struct.pack_into('<2Q',self.data,r+0x18,self.p+st,self.p+st+0x80)
            struct.pack_into('<Qf',self.data,r+0x30,self.p+st+0x100,value)
            for off,text in [(st,name),(st+0x80,'Dollar' if i==0 else 'Euro'),(st+0x100,symbol)]:
                b=text.encode();struct.pack_into('<I',self.data,off,len(b));self.data[off+4:off+4+len(b)]=b
    def read(self,pairs,strict=True):
        out={}
        for a,n in pairs:
            self.calls+=1;self.bytes+=n
            if a==self.base+ROOT_RVA:
                self.rootReads+=1;out[a]=struct.pack('<Q',self.p+0x100+(8 if self.changed and self.rootReads>1 else 0))
            elif self.p<=a and a+n<=self.p+len(self.data):out[a]=bytes(self.data[a-self.p:a-self.p+n])
            else:raise RuntimeError('Unreadable currency memory')
        return out
class CurrencyTests(unittest.TestCase):
    def test_table_and_utf8_and_conversion(self):
        s=CurrencySession();t=read_currencies(s,s.base);c=t['definitions'][0]
        self.assertEqual(t['count'],2);self.assertEqual(c['name'],'Canadian Dollar');self.assertEqual(c['valueBytes'],'379fda3f');self.assertEqual(t['definitions'][1]['symbol'],'€')
        for raw,display in [(300000000,512395155),(17426704,29764529),(313768,535911),(450000,768593),(768900,1313269),(6061,10352),(0,0)]:self.assertEqual(round(raw*c['value']),display)
        self.assertLess(s.calls,20)
    def test_absent_symbol_is_empty_not_invented(self):
        s=CurrencySession();struct.pack_into('<Q',s.data,0x430,0)
        self.assertEqual(read_currencies(s,s.base)['definitions'][0]['symbol'],'')
    def test_invalid_rates_fail_closed(self):
        for v in [float('nan'),float('inf'),0,-1]:
            s=CurrencySession();struct.pack_into('<f',s.data,0x438,v)
            self.assertEqual(capture_currencies(s,s.base)['status'],'unresolved')
    def test_changed_root_rejects(self):
        s=CurrencySession();s.changed=True
        self.assertEqual(capture_currencies(s,s.base)['definitions'],[])
    def test_wrong_vtable_and_oversized_vector_reject(self):
        for off,value in [(0x100,0),(0x210,0xffffffffffffffff)]:
            s=CurrencySession();struct.pack_into('<Q',s.data,off,value)
            self.assertEqual(capture_currencies(s,s.base)['status'],'unresolved')
    def test_bad_string_and_duplicate_identity_reject(self):
        for off,value in [(0x800,10000),(0x460,0)]:
            s=CurrencySession();struct.pack_into('<I',s.data,off,value)
            self.assertEqual(capture_currencies(s,s.base)['status'],'unresolved')
if __name__=='__main__':unittest.main()

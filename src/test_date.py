import datetime as dt
import struct
import unittest
from live_date import decode_game_date, age_on_date, read_game_date, GAME_DATE_RVA
from test_reader import FakeSession
from touchline_live import capture

class DateTests(unittest.TestCase):
    def test_verified_live_bytes_and_high_time_bit(self):
        date, info=decode_game_date(bytes.fromhex('9912ea07'))
        self.assertEqual(date,dt.date(2026,6,2));self.assertEqual(info['timeCode'],9)
        for code in (0,63,64,127):
            self.assertEqual(decode_game_date(struct.pack('<HH',153+(code<<9),2026))[0],date)
    def test_invalid_days_and_truncation(self):
        for raw in (b'',b'123',struct.pack('<HH',0,2026),struct.pack('<HH',366,2026),struct.pack('<HH',367,2024),struct.pack('<HH',1,0)):
            with self.assertRaises(RuntimeError):decode_game_date(raw)
        self.assertEqual(decode_game_date(struct.pack('<HH',366,2024))[0],dt.date(2024,12,31))
    def test_birthday_boundaries_and_leap_birth(self):
        birth=dt.date(2000,6,2)
        self.assertEqual([age_on_date(birth,dt.date(2026,6,d)) for d in (1,2,3)],[25,26,26])
        self.assertEqual(age_on_date(dt.date(2000,2,29),dt.date(2025,2,28)),24)
        self.assertEqual(age_on_date(dt.date(2000,2,29),dt.date(2025,3,1)),25)
        self.assertIsNone(age_on_date(dt.date(2027,1,1),dt.date(2026,6,2)))
    def test_full_capture_one_global_read_and_cached_ages(self):
        session=FakeSession();calls=[];read=session.read
        def tracked(pairs,strict=True):
            calls.extend((a,n) for a,n in pairs if a==session.base+GAME_DATE_RVA)
            return read(pairs,strict)
        session.read=tracked
        snapshot=capture(session)
        self.assertEqual(calls,[(session.base+GAME_DATE_RVA,4)])
        self.assertEqual(snapshot['gameDate'],'2026-06-02')
        self.assertEqual(snapshot['fieldCoverage']['age'],{'derived':3})
        self.assertEqual(snapshot['players'][0]['age'],27)
        self.assertEqual(snapshot['fieldDefinitions']['age']['status'],'derived')

if __name__=='__main__':unittest.main()

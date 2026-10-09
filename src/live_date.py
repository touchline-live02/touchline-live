"""Exact-build global FM date; one four-byte read per capture, no clock fallback."""
import calendar
import datetime as dt
import struct

GAME_DATE_RVA = 0x528cc28
AGE_DEFINITION = {
    'status': 'derived',
    'rule': 'Completed calendar years from verified DOB to capture-scoped live gameDate; birthday comparison, never host date',
}

def decode_game_date(raw):
    if len(raw) != 4:
        raise RuntimeError('Truncated global game date; cache retained')
    # The first Int16 is a bitfield: reinterpret its sign bit before shifting.
    packed, year = struct.unpack('<Hh', raw)
    day = packed & 0x1ff
    if not (1900 <= year <= 9999 and 1 <= day <= (366 if calendar.isleap(year) else 365)):
        raise RuntimeError('Invalid global game date; cache retained')
    date = dt.date(year, 1, 1) + dt.timedelta(days=day-1)
    return date, {'rawPacked': packed, 'rawYear': year, 'dayOfYear': day,
                  'timeCode': packed >> 9}

def read_game_date(session, image_base):
    address = image_base + GAME_DATE_RVA
    raw = session.read([(address, 4)])[address]
    date, fields = decode_game_date(raw)
    return date, dict(fields, status='verified', source='FM24 current-date global',
        address=hex(address), rootRVA=hex(GAME_DATE_RVA), rawBytes=raw.hex(),
        layout='u16 packed day/time at +0; i16 year at +2; day=packed&0x1ff; timeCode=packed>>9',
        timeStatus='unresolved', timeNote='Time code retained; hour/minute mapping is not required for calendar age')

def age_on_date(birth, game_date):
    if birth > game_date:
        return None
    return game_date.year - birth.year - ((game_date.month, game_date.day) < (birth.month, birth.day))

def apply_game_date(players, game_date):
    for player in players:
        player.age = age_on_date(dt.date.fromisoformat(player.birthDate), game_date)
        player.fieldStatus['age'] = 'derived' if player.age is not None else 'inconsistent'
        if player.age is None:
            player.issues.append({'field':'age', 'status':'inconsistent', 'reason':'DOB is after trusted gameDate'})

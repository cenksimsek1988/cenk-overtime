#!/usr/bin/env python3
"""contract-offset.py: the contract zone's fixed UTC offset over the case's window.

    python contract-offset.py --db CASE/master.sqlite

Reads contract_zone (an IANA name such as Europe/Istanbul), window_from and
window_to from case_info. When the zone keeps one UTC offset on every day of
the window, it writes that offset in minutes as contract_offset_minutes, which
the day views of schema.sql use. When the offset changes inside the window
(daylight saving), it writes NULL: the views' days are then NULL, and the
analysis converts each time with the zone's rules. A different earlier value
moves into the note. Standard library only; on Windows, zoneinfo needs the
tzdata package. Run it again whenever the window or the zone changes.
"""

import argparse
import sqlite3
import sys
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

KEY = "contract_offset_minutes"


def fail(message):
    print("contract-offset.py: " + message, file=sys.stderr)
    sys.exit(1)


def fixed_offset(zone, first, last):
    """Minutes east of UTC when the zone has one offset on every day from first to last, else None.

    Noon of each day is enough: an offset change holds for whole days on both sides."""
    offsets, day = set(), first
    while day <= last:
        offsets.add(datetime.combine(day, time(12), zone).utcoffset())
        day += timedelta(days=1)
    return int(offsets.pop().total_seconds() // 60) if len(offsets) == 1 else None


def read_case(con):
    try:
        info = dict(con.execute(
            "SELECT key, value FROM case_info WHERE key IN ('contract_zone', 'window_from', 'window_to')"))
    except sqlite3.OperationalError:
        fail("the database has no case_info table: create it from schema.sql first")
    missing = [k for k in ("contract_zone", "window_from", "window_to") if not info.get(k)]
    if missing:
        fail("case_info lacks " + ", ".join(missing))
    try:
        zone = ZoneInfo(info["contract_zone"])
    except (ZoneInfoNotFoundError, ValueError):
        fail("unknown time zone %r: use an IANA name such as Europe/Istanbul; on Windows, "
             "install the tzdata package" % info["contract_zone"])
    try:
        first, last = date.fromisoformat(info["window_from"]), date.fromisoformat(info["window_to"])
    except ValueError:
        fail("window_from and window_to must be YYYY-MM-DD")
    if first > last:
        fail("window_from is after window_to")
    return info["contract_zone"], zone, first, last


def save(con, value):
    """Writes the value; a different earlier value moves into the note, so it is not lost."""
    old = con.execute("SELECT value, note FROM case_info WHERE key = ?", (KEY,)).fetchone()
    note = old[1] if old else None
    if old and old[0] is not None and old[0] != value:
        note = "was %s until %s" % (old[0], date.today().isoformat()) + ("; " + note if note else "")
    con.execute("INSERT OR REPLACE INTO case_info (key, value, note) VALUES (?, ?, ?)", (KEY, value, note))
    con.commit()


def main():
    parser = argparse.ArgumentParser(description="Write the contract zone's fixed UTC offset over the window.")
    parser.add_argument("--db", required=True, help="the case's master.sqlite")
    args = parser.parse_args()
    con = sqlite3.connect(args.db)
    try:
        name, zone, first, last = read_case(con)
        minutes = fixed_offset(zone, first, last)
        save(con, None if minutes is None else str(minutes))
    finally:
        con.close()
    if minutes is None:
        print("%s changes its UTC offset between %s and %s (daylight saving): %s is NULL, the day views "
              "give NULL, and the analysis converts each time with the zone's rules." % (name, first, last, KEY))
    else:
        hours, rest = divmod(abs(minutes), 60)
        print("%s = %d: %s keeps UTC%s%02d:%02d from %s to %s." % (
            KEY, minutes, name, "-" if minutes < 0 else "+", hours, rest, first, last))


if __name__ == "__main__":
    main()

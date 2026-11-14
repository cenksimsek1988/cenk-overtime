# Mail index: commands, queries, limits

Read when a mail archive is indexed or searched (`collect`, section 5, "Mail archives"). The script is `scripts/mail-index.py`; it uses Python's standard library, and `libpff-python` only for an Outlook backup.

## Commands

| Command | Does | Example |
|---|---|---|
| `measure <source>...` | says `index: yes` for any `.pst`, or above 10 MB of message text | `measure 4_Raw_Data/email/sent.mbox` |
| `build --index <file> <source>...` | writes a new index of all the sources | `build --index work/mail-index/mail.sqlite backup.pst sent.mbox` |
| `search --index <file> '<query>'` | header lines of the matching messages, oldest first | `search --index <file> 'invoice AND overtime'` |
| `folders --index <file>` | per folder: messages, first and last day, attachments, messages without text | `folders --index <file> --zone Europe/Rome` |
| `secrets --index <file>` | messages that hold secret-like words or values: header line and the word, never the value | `secrets --index <file>` |

- A source is a `.pst` file, an mbox file, one `.eml` file or a folder of `.eml` files (read with its subfolders). Sources are opened read-only.
- `build` always starts a new index: give it every source again when one is added. It builds in the system temp folder and moves the finished file, so a synced `work/` never uploads a half-written one.
- `--codepage` (`measure`, `build`): the Windows code page of old messages without Unicode text. Example: `--codepage cp1254` for Turkish; the default is `cp1252`.
- `search` options: `--folder Sent` (a folder's name or the last part of its path), `--sender hopper`, `--since 2024-03-01 --until 2024-03-31`, `--zone <IANA name>` (the contract zone from `case_info`; without it days and times are UTC), `--limit 50`, `--snippet`.

## Queries

FTS5 syntax over five columns: `subject`, `people` (sender and recipients, names and addresses), `body`, `attachments` (file names), `links` (link targets).

| Query | Finds |
|---|---|
| `overtime` | the word in any column |
| `deploy*` | words that start with deploy |
| `"release notes"` | the phrase |
| `release AND weekend`, `invoice OR receipt`, `release NOT draft` | combinations; the operators in capitals |
| `attachments: xlsx` | a file name that holds xlsx |
| `people: hopper` | a sender or recipient |
| `links: "files.example.org"` | a link to that host; quote anything with a dot or a hyphen |
| `subject: budget` | the subject only |

- Letters match without accents and in either case: `cagri` finds `Çağrı`, `uber` finds `Über`. The dotless ı and the dotted İ are indexed as plain i, and queries are changed the same way.
- Search in the languages the person's mail is in, with the stems of each: `overtime OR mesai OR straordinari*`.
- A line of the result: `#id | time | folder | sender -> recipients | subject | attachment names`. The id is `messages.id` in the index.

## Reading more than the script prints

The index is a SQLite file; open it read-only for a question the commands do not answer, and save the query in `work/queries/` when an artifact comes from it.

| Table | Holds |
|---|---|
| `sources` | path, kind, size, SHA-256, messages, messages without text, read errors |
| `messages` | source, folder, position in the source, `sent_utc`, `delivered_utc`, sender, recipient lists, subject, `internet_id`, `body_source` (`plain`, `html`, `rtf` or NULL), `body` |
| `attachments` | name, size and type per attachment; no contents |
| `links` | link targets per message |
| `errors` | messages and attachments that could not be read, with the error |

- Never print `messages.body` of many messages into the chat: select ids and header fields, then read the one body you need.
- Times are UTC. A day in the contract zone needs the zone's rules: use `--zone`, or convert in Python as the analysis does.

## What an Outlook backup needs

- The `libpff-python` package: the tools check of `cenk-overtime:start` asks for it only with `--pst`.
- The script opens the backup from a file object: the package's path-based open fails on Windows.
- Recipients are read from the message's recipient table, one record set per recipient.
- A message without a body raises "missing value data" in the package: it is counted as a message without text, not as a read error.

## Limits to state

- Attachment contents are not indexed, only their names: a spreadsheet's or PDF's text is not found. Say so with every answer.
- Messages without text (a picture, an empty forward) match only by subject, people and attachment names. `build` and `search` print their count.
- For an HTML-only message the text, the link targets (Outlook's safelinks unwrapped) and the pictures' descriptions are indexed. Links rewritten by another protection service stay as written: search `links:` for the target's host name, which is inside the rewritten link.
- Sent mail in a `.pst` is the folder the mail program names for it (`Sent Items` in English); check `folders` for its name in the person's language.
- A received mail proves nothing about the person's hours: the index is for finding, and `traces` still takes only what the person sent.
- `--snippet` and `secrets` find secret-like words in English, Turkish, Italian, German, Spanish and French, long key-like values and logins inside links. `secrets` lists too much on purpose: version numbers in file names, ids and hashes count as long values, and a mailbox with many system notices can have one message in eight listed. They can also miss a secret written another way: read a staged message yourself before it goes into the evidence folder.

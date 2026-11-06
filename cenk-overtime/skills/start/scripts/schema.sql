-- Master database of one overtime case. Running it again is safe: tables are
-- created only when missing, so data already loaded stays; the views are
-- recreated, so a database made by an older version gets the current ones.

CREATE TABLE IF NOT EXISTS case_info (
  key   TEXT PRIMARY KEY,  -- job, contract_hours, contract_days, contract_zone, lived_zone, window_from, window_to, ...
  value TEXT,
  note  TEXT
);

CREATE TABLE IF NOT EXISTS evidence_files (
  file_id       INTEGER PRIMARY KEY,
  source        TEXT NOT NULL,  -- email, teams, slack, whatsapp, calls, calendar, tracker, other
  description   TEXT,
  original_path TEXT NOT NULL,  -- kept so anyone can go back to where the file was found
  case_path     TEXT NOT NULL,  -- relative to the case folder
  sha256        TEXT NOT NULL,
  bytes         INTEGER,
  modified_at   TEXT,           -- modification time of the original
  received_at   TEXT NOT NULL,  -- when it entered the case folder
  method        TEXT NOT NULL,  -- copied, moved, exported, downloaded
  note          TEXT
);

CREATE TABLE IF NOT EXISTS traces (
  record_id          TEXT PRIMARY KEY,
  source             TEXT,
  channel_id         TEXT,
  channel_name       TEXT,
  time_utc           TEXT,
  time_contract      TEXT,
  time_second_source TEXT,
  author             TEXT,
  own_text           TEXT,
  quoted_author      TEXT,
  raw_text           TEXT,
  url                TEXT,
  extra              TEXT,     -- JSON
  file_id            INTEGER REFERENCES evidence_files(file_id)
);

-- One row per repository source (a local clone or a URL) that git-history.sh read.
CREATE TABLE IF NOT EXISTS repos (
  repo           TEXT NOT NULL,  -- several clones of one remote share this name
  source         TEXT NOT NULL,  -- local path, or URL without credentials
  kind           TEXT NOT NULL,  -- local, clone
  remote_url     TEXT,
  remote_host    TEXT,           -- tells employer repositories from others
  head           TEXT,
  commits_all    INTEGER,        -- every author, all refs
  commits_own    INTEGER,
  commits_others INTEGER,        -- other authors are kept only as this count
  author_regex   TEXT,
  extracted_at   TEXT,
  git_version    TEXT,
  tsv_dir        TEXT,
  PRIMARY KEY (repo, source)
);

CREATE TABLE IF NOT EXISTS commits (
  repo           TEXT NOT NULL,
  hash           TEXT NOT NULL,
  parents        TEXT,
  is_merge       INTEGER,
  author_name    TEXT,
  author_email   TEXT,
  author_date    TEXT,     -- the time of work, ISO 8601 with the author's own offset
  author_utc     TEXT,
  committer_date TEXT,
  committer_utc  TEXT,
  dates_differ   INTEGER,  -- 1 when committer time is more than 5 min from author time
  subject        TEXT,
  files_changed  INTEGER,
  lines_added    INTEGER,
  lines_deleted  INTEGER,
  binary_files   INTEGER,
  PRIMARY KEY (repo, hash)
);

CREATE TABLE IF NOT EXISTS commit_files (
  repo          TEXT NOT NULL,
  hash          TEXT NOT NULL,
  path          TEXT NOT NULL,
  lines_added   INTEGER,  -- NULL for binary files
  lines_deleted INTEGER,
  is_binary     INTEGER,
  PRIMARY KEY (repo, hash, path)
);

CREATE TABLE IF NOT EXISTS tags (
  repo             TEXT NOT NULL,
  tag              TEXT NOT NULL,
  type             TEXT,     -- annotated, lightweight
  tag_date         TEXT,     -- tagger date; for a lightweight tag the tagged commit's date
  commit_hash      TEXT,
  tagger_is_person INTEGER,  -- tagger emails of others are not stored
  subject          TEXT,
  PRIMARY KEY (repo, tag)
);

CREATE TABLE IF NOT EXISTS branches (
  repo           TEXT NOT NULL,
  ref            TEXT NOT NULL,
  branch         TEXT,
  committer_date TEXT,  -- of the branch's last commit
  author_date    TEXT,
  commit_hash    TEXT,
  PRIMARY KEY (repo, ref)
);

CREATE TABLE IF NOT EXISTS git_identities (
  repo         TEXT NOT NULL,
  author_name  TEXT NOT NULL,
  author_email TEXT NOT NULL,
  commits      INTEGER,
  PRIMARY KEY (repo, author_name, author_email)
);

CREATE TABLE IF NOT EXISTS decisions (
  decision_id INTEGER PRIMARY KEY,
  made_at     TEXT NOT NULL,
  subject     TEXT NOT NULL,  -- table and id, or a rule
  decision    TEXT NOT NULL,
  reason      TEXT NOT NULL,
  decided_by  TEXT NOT NULL   -- person, claude
);

-- One row per calendar day of the window, filled by cenk-overtime:analyse from
-- traces, commits and its events (query in work/queries/days.sql) and read by
-- its scripts/models.py. The day is the activity day in the contract zone: a
-- night trace counts for the evening before.
CREATE TABLE IF NOT EXISTS days (
  day           TEXT PRIMARY KEY,           -- YYYY-MM-DD
  off           TEXT,                       -- holiday, leave or sick; left out of the models. NULL on other days
  phase         TEXT,                       -- employer or role period the person named; NULL when there is one
  ooh_traces    INTEGER NOT NULL,           -- counted out-of-hours traces of the core tier: messages, mail, calls, commits
  ooh_chat      INTEGER,                    -- of which chat messages
  ooh_mail      INTEGER,                    -- of which sent mail
  ooh_commits   INTEGER,                    -- of which commit events (copies of one commit count once)
  last_chat_h   REAL,                       -- last counted chat message, hours on the activity day: 21:30 = 21.5, 01:30 after midnight = 25.5
  last_mail_h   REAL,
  last_commit_h REAL,
  release       INTEGER NOT NULL DEFAULT 0, -- 1 when a release was done or in progress that day, or a release tag or branch dates it
  patch         INTEGER NOT NULL DEFAULT 0,
  incident      INTEGER NOT NULL DEFAULT 0,
  events_from   TEXT                        -- message, git or both: what dated that day's events
);

-- Days and times below are the contract zone's, from author_utc and the fixed
-- offset in case_info (contract_offset_minutes, written by contract-offset.py).
-- The author's own offset can be anything (Z from a UTC container). Without a
-- fixed offset, as in a zone with daylight saving inside the window, they are
-- NULL, and the analysis converts each commit with the zone's rules.
DROP VIEW IF EXISTS v_repo_summary;
CREATE VIEW v_repo_summary AS
SELECT repo,
       count(*)                AS own_commits,
       sum(is_merge)           AS merges,
       min(author_utc)         AS first_commit_utc,
       max(author_utc)         AS last_commit_utc,
       datetime(min(author_utc), (SELECT value FROM case_info WHERE key = 'contract_offset_minutes') || ' minutes') AS first_commit_contract,
       datetime(max(author_utc), (SELECT value FROM case_info WHERE key = 'contract_offset_minutes') || ' minutes') AS last_commit_contract,
       sum(files_changed)      AS files_changed,
       sum(lines_added)        AS lines_added,
       sum(lines_deleted)      AS lines_deleted,
       sum(binary_files)       AS binary_files
FROM commits
GROUP BY repo;

DROP VIEW IF EXISTS v_commits_by_day;
CREATE VIEW v_commits_by_day AS
SELECT repo,
       date(author_utc, (SELECT value FROM case_info WHERE key = 'contract_offset_minutes') || ' minutes') AS day,
       count(*)                   AS commits,
       sum(files_changed)         AS files_changed,
       sum(lines_added)           AS lines_added,
       sum(lines_deleted)         AS lines_deleted
FROM commits
GROUP BY repo, day;

DROP VIEW IF EXISTS v_commits_in_window;
CREATE VIEW v_commits_in_window AS
SELECT c.*
FROM commits c
WHERE date(c.author_utc, (SELECT value FROM case_info WHERE key = 'contract_offset_minutes') || ' minutes')
      BETWEEN (SELECT value FROM case_info WHERE key = 'window_from')
          AND (SELECT value FROM case_info WHERE key = 'window_to');

CREATE VIEW IF NOT EXISTS v_evidence_by_source AS
SELECT source, count(*) AS files, sum(bytes) AS bytes, min(received_at) AS first_received, max(received_at) AS last_received
FROM evidence_files
GROUP BY source;

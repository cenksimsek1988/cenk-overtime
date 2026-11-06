# Many files at once: readers and checkers

Read when the evidence is more than about 10 files or 100 MB, or mixes many formats. One reader per source works at the same time as the others; a checker follows each reader; one merge and one critic finish the work.

## Before starting

- Run the Tools section of `cenk-overtime:start` first: readers use the installed libraries, not parsers of their own (section 5).
- Tell the person in plain words that you will read their files with several helpers at once, roughly how long it takes, and that it uses more of their Claude usage than reading one file after another. Start after their yes.
- Give every agent the model and the effort below: with the Agent tool on each call, in a workflow in each agent's options.

## Roles

The names are Claude Code's model aliases. As of November 2026: `haiku` is Claude Haiku 5.5, `sonnet` Claude Sonnet 5.5, `opus` Claude Opus 5.5, and `fable` Claude Fable 5.1 (`claude-fable-5-1`), the strongest. Where `fable` is not available, use `opus`. On Amazon Bedrock, Google Cloud and Microsoft Foundry the aliases can point to older models.

| Role | Model | Effort | Why |
|---|---|---|---|
| Reader: one source or file group | `sonnet` | `medium` | Parsing and counting with the installed libraries is coding work with tools; the checker catches its slips |
| Checker: one per reader, started as soon as that reader finishes | `opus` | `high` | It recomputes the reader's figures another way and compares a sample with the originals; another model than the reader's, so the same mistake is not made twice |
| Merge: one result from all readers and checks | `fable` | `high` | Judgment over everything at once; what it gets wrong reaches the report |
| Completeness critic: what the merge misses or overstates | `fable` | `high` | The same: nothing after it looks at the whole |
| Gap reader: only for a gap the critic names | `sonnet` | `medium` | Reader work again, narrower |

- No second full reader per source: the checker's recount and sample replace it, in a fraction of the time.
- Seen (Nov 2026): a run with every agent on the strongest model at `max`, a second full reader per source, and stages that waited for each other took hours. `xhigh` stays for the one check nothing follows: the audit in `cenk-overtime:court-package`.

## Briefs

- Reader: the files (paths under `for-lawyer/raw/`), the person's identities, the window, the columns of `traces` (section 8), "own sent messages and own actions only", "never print a secret". It writes rows to `work/readers/<source>/` and reports: files read, rows, first and last date, own rows against others, files it could not read and why.
- Checker: the reader's report, its output files and the original files, not the reader's reasoning. It recounts the rows and the first and last dates by another method (another library, or a plain line count), compares 20 random rows with the original records, and lists every mismatch with its ids.
- Merge: every reader's report and every checker's mismatch list. It writes one result per source: counts, open mismatches, files not read.
- Critic: the merge and the list in `evidence_files`. It names what is missing (a source, a year, a format), what is counted twice, and claims that go beyond the data.
- The main session decides each mismatch and each gap, records the decision in `decisions`, and loads the rows into `traces`.

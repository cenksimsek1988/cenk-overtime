# Privacy

cenk-overtime is a set of instructions and one script that run on your computer. Its author receives no data from it: there are no servers, hooks, analytics or tracking.

- Reads: the files, exports and repositories you agree to, and your own sent messages found through connectors you have connected.
- Stores: a case folder in your own Google Drive, or on your computer: copies of your evidence, their SHA-256 hashes, a SQLite database and reports.
- Employer repositories: cloned with your own git login into `~/overtime-clones/` on your computer, never into the case folder, and deleted after reading unless you ask to keep them.
- Passwords found in your messages: listed in `secrets.json` next to the clones, outside the case folder, used only to mask them, and deleted when you say the package is final.
- Who sees your data: you; Google, which stores your Drive; the lawyers you share the case folder with; Anthropic, which processes your Claude sessions under its own privacy policy (https://www.anthropic.com/legal/privacy); the providers of the connectors you use.
- Other people's data: your records contain colleagues' names and messages. The analysis keeps only your own messages and commits, counts other git authors without storing their addresses, and masks other people's private information before the package is built. The original files stay unmasked in your case folder.
- Retention: the plugin keeps nothing itself. Your case folder stays until you delete it.
- To delete everything: delete the case folder in Google Drive and empty the Drive trash; delete `~/overtime-clones/<case>/` if anything is left there.
- Contact: https://github.com/cenksimsek1988/cenk-overtime/issues

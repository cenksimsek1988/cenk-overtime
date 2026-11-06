#!/usr/bin/env bash
# git-history.sh: the person's git history as tables, for an overtime case.
#
#   git-history.sh identities [--case DIR] [--clones DIR] --author REGEX REPO...
#   git-history.sh extract --case DIR [--clones DIR] --author REGEX [--keep-clone] REPO...
#
# REPO is a local repository path or a URL. A URL is cloned with --mirror, with
# the person's own git login, into the clones folder: --clones, by default
# ~/overtime-clones/<case folder name>. It must be outside the case folder,
# which syncs to the cloud. extract deletes the clone after reading it unless
# --keep-clone is given. Local repositories are only read.
# REGEX is an extended regular expression, matched without case against each
# author's "Name <email>". extract writes TSV files to DIR/git/<repo>/ and
# loads them into DIR/master.sqlite (sqlite3, or Python's sqlite3 module).

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# Stash and notes commits are tooling, not work.
REFS=(--exclude=refs/stash --exclude='refs/notes/*' --all)

die() { printf 'git-history: %s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*" >&2; }
usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

# Read-only git: no optional locks, no prompts, no fsmonitor daemon, and output
# that does not depend on the person's own git configuration.
git_() {
	GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 git \
		-c safe.directory='*' -c core.fsmonitor=false -c core.quotepath=false \
		-c i18n.logOutputEncoding=UTF-8 -c log.showSignature=false -c color.ui=never \
		-C "$repo_dir" "$@"
}

is_url() { printf '%s\n' "$1" | grep -Eq '^[A-Za-z][A-Za-z0-9+.-]*://|^[^/\\:@]+@[^/\\:]+:'; }

# A password, or a token in place of the user name, must not reach a command
# line, a clone's config or the database.
has_credentials() {
	printf '%s\n' "$1" | grep -Eqi '^https?://[^/]*@|^[A-Za-z][A-Za-z0-9+.-]*://[^/@]*:[^/@]*@'
}

strip_userinfo() { printf '%s\n' "$1" | sed -E 's#^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@#\1#'; }

remote_host() { printf '%s\n' "$1" | sed -E 's#^[A-Za-z][A-Za-z0-9+.-]*://##; s#^[^/@]*@##; s#[/:].*##'; }

# Last two path parts of a remote without .git (team/backend), so clones of one
# remote get one name.
name_from_url() {
	printf '%s\n' "$1" |
		sed -E 's#^[A-Za-z][A-Za-z0-9+.-]*://[^/]*##; s#^[^/@]*@[^:/]*:##; s#/+$##; s#\.git$##' |
		awk -F/ '{ if (NF >= 2 && $(NF - 1) != "") print $(NF - 1) "/" $NF; else print $NF }'
}

safe_dir_name() { printf '%s\n' "$1" | sed -E 's#[^A-Za-z0-9._-]+#_#g'; }

# A clone holds the employer's source code. The case folder syncs to the cloud
# and holds the folder shared with lawyers, so clones never go inside it.
prepare_clones_dir() {
	[ -n "$CLONES" ] || die "--clones or --case is needed to clone a URL"
	mkdir -p "$CLONES"
	CLONES=$(cd "$CLONES" && pwd)
	if [ -n "$CASE" ]; then
		case "$CLONES/" in
			"$CASE"/*)
				rmdir "$CLONES" 2>/dev/null || true
				die "the clones folder must be outside the case folder, which syncs to the cloud: $CLONES"
				;;
		esac
	fi
}

sql_quote() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"; }

# Sets repo_dir, kind, source, remote_url and name for one REPO argument.
resolve_source() {
	local arg=$1 clone
	if is_url "$arg"; then
		if has_credentials "$arg"; then
			die "the URL contains a user name or password; use git's credential manager or an SSH key instead: $(strip_userinfo "$arg")"
		fi
		prepare_clones_dir
		remote_url=$arg
		name=$(name_from_url "$arg")
		clone="$CLONES/$(safe_dir_name "$name").git"
		if [ -d "$clone" ]; then
			say "using the existing clone $clone (not fetched again)"
		else
			say "cloning $arg into $clone"
			GIT_TERMINAL_PROMPT=0 git -c core.fsmonitor=false clone --mirror --quiet -- "$arg" "$clone"
		fi
		repo_dir=$clone kind=clone source=$arg
	else
		[ -d "$arg" ] || die "not a folder: $arg"
		repo_dir=$(cd "$arg" && pwd)
		git_ rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $arg"
		kind=local source=$repo_dir
		remote_url=$(git_ remote get-url origin 2>/dev/null || git_ remote get-url "$(git_ remote | head -n 1)" 2>/dev/null || true)
		remote_url=$(strip_userinfo "$remote_url")
		if [ -n "$remote_url" ]; then
			name=$(name_from_url "$remote_url")
		else
			name=$(basename "$repo_dir" .git)
		fi
	fi
}

# Machine-default addresses (user@HOSTNAME, user@10.1.2.3) name internal hosts.
AWK_EMAIL='
function clean(s) { gsub(/[\t\r\n]/, " ", s); return s }
function email(e,   p, d) {
	p = index(e, "@")
	if (p == 0) return clean(e)
	d = substr(e, p + 1)
	if (d ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ || index(d, ".") == 0) d = "local-machine"
	return clean(substr(e, 1, p) d)
}'

cmd_identities() {
	local arg
	for arg in "$@"; do
		resolve_source "$arg"
		printf '== %s (%s)\n' "$name" "$source"
		git_ log "${REFS[@]}" --no-mailmap -E -i --author="$AUTHOR" --format='%an%x1f%ae' |
			awk -F '\037' "$AWK_EMAIL"' { print clean($1) " <" email($2) ">" }' |
			sort | uniq -c | sort -rn
		if [ "$kind" = clone ]; then
			say "the clone stays in $repo_dir; extract deletes it after reading"
		fi
	done
}

write_commits() {
	git_ log "${REFS[@]}" --no-mailmap --no-renames --numstat -E -i --author="$AUTHOR" \
		--format='%x1e%H%x1f%P%x1f%an%x1f%ae%x1f%aI%x1f%cI%x1f%s' |
		awk -v repo="$name" -v files="$out/commit_files.tsv" "$AWK_EMAIL"'
		function flush() { if (head != "") print head "\t" n "\t" add "\t" del "\t" bin }
		BEGIN {
			print "repo\thash\tparents\tis_merge\tauthor_name\tauthor_email\tauthor_date\tcommitter_date\tsubject\tfiles_changed\tlines_added\tlines_deleted\tbinary_files"
			print "repo\thash\tpath\tlines_added\tlines_deleted\tis_binary" > files
		}
		{ sub(/\r$/, "") }
		substr($0, 1, 1) == "\036" {
			flush()
			split(substr($0, 2), f, "\037")
			hash = f[1]
			merge = split(f[2], parents, " ") > 1 ? 1 : 0
			head = repo "\t" hash "\t" f[2] "\t" merge "\t" clean(f[3]) "\t" email(f[4]) "\t" f[5] "\t" f[6] "\t" clean(f[7])
			n = add = del = bin = 0
			next
		}
		/^[0-9-]+\t[0-9-]+\t/ {
			split($0, s, "\t")
			path = substr($0, length(s[1]) + length(s[2]) + 3)
			n++
			if (s[1] == "-") { bin++; print repo "\t" hash "\t" path "\t\t\t1" > files }
			else { add += s[1]; del += s[2]; print repo "\t" hash "\t" path "\t" s[1] "\t" s[2] "\t0" > files }
		}
		END { flush() }' >"$out/commits.tsv"
}

write_identities() {
	awk -F '\t' -v repo="$name" '
		NR == 1 { print "repo\tauthor_name\tauthor_email\tcommits"; next }
		{ c[$5 "\t" $6]++ }
		END { for (k in c) print repo "\t" k "\t" c[k] }' "$out/commits.tsv" >"$out/identities.tsv"
}

write_tags() {
	git_ for-each-ref refs/tags \
		--format='%(refname:strip=2)%1f%(objecttype)%1f%(creatordate:iso-strict)%1f%(objectname)%1f%(*objectname)%1f%(taggername) %(taggeremail)%1f%(subject)' |
		awk -F '\037' -v repo="$name" "$AWK_EMAIL"'
		BEGIN { print "repo\ttag\ttype\ttag_date\tcommit_hash\ttagger_is_person\tsubject"; re = tolower(ENVIRON["GIT_HISTORY_AUTHOR"]) }
		{
			annotated = $2 == "tag"
			mine = annotated && tolower($6) ~ re ? 1 : 0
			print repo "\t" clean($1) "\t" (annotated ? "annotated" : "lightweight") "\t" $3 "\t" ($5 != "" ? $5 : $4) "\t" mine "\t" clean($7)
		}' >"$out/tags.tsv"
}

write_branches() {
	git_ for-each-ref refs/heads refs/remotes \
		--format='%(refname)%1f%(refname:short)%1f%(committerdate:iso-strict)%1f%(authordate:iso-strict)%1f%(objectname)' |
		awk -F '\037' -v repo="$name" "$AWK_EMAIL"'
		BEGIN { print "repo\tref\tbranch\tcommitter_date\tauthor_date\tcommit_hash" }
		$1 ~ /\/HEAD$/ { next }
		{ print repo "\t" clean($1) "\t" clean($2) "\t" $3 "\t" $4 "\t" $5 }' >"$out/branches.tsv"
}

write_repo() {
	local all own
	all=$(git_ rev-list "${REFS[@]}" --count)
	own=$(($(wc -l <"$out/commits.tsv") - 1))
	{
		printf 'repo\tsource\tkind\tremote_url\tremote_host\thead\tcommits_all\tcommits_own\tcommits_others\tauthor_regex\textracted_at\tgit_version\ttsv_dir\n'
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$name" "$source" "$kind" "$remote_url" "$(remote_host "$remote_url")" \
			"$(git_ rev-parse --verify -q HEAD || true)" "$all" "$own" "$((all - own))" \
			"$AUTHOR" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(git --version | sed 's/^git version //')" \
			"${out#"$CASE"/}"
	} >"$out/repo.tsv"
}

# INSERT statements from a TSV file with a header line; types has one letter
# per column: t = text, n = number (empty or "-" becomes NULL).
tsv_sql() {
	awk -F '\t' -v table="$1" -v cols="$2" -v types="$3" '
		NR == 1 { next }
		{
			sub(/\r$/, "")
			line = "INSERT OR REPLACE INTO " table " (" cols ") VALUES ("
			for (i = 1; i <= length(types); i++) {
				v = $i
				if (substr(types, i, 1) == "n") { if (v == "" || v == "-") v = "NULL" }
				else { gsub(/\047/, "\047\047", v); v = "\047" v "\047" }
				line = line (i > 1 ? ", " : "") v
			}
			print line ");"
		}' "$4"
}

load_sql() {
	local q
	q=$(sql_quote "$name")
	echo 'BEGIN;'
	# A repository's rows are replaced once per run, so all clones passed in
	# the same run add up, and a later run with a corrected pattern leaves no
	# stale rows.
	if ! printf '%s\n' "$loaded" | grep -Fxq -- "$name"; then
		local t
		for t in repos commits commit_files tags branches git_identities; do
			echo "DELETE FROM $t WHERE repo = $q;"
		done
	fi
	tsv_sql repos 'repo, source, kind, remote_url, remote_host, head, commits_all, commits_own, commits_others, author_regex, extracted_at, git_version, tsv_dir' ttttttnnntttt "$out/repo.tsv"
	tsv_sql commits 'repo, hash, parents, is_merge, author_name, author_email, author_date, committer_date, subject, files_changed, lines_added, lines_deleted, binary_files' tttntttttnnnn "$out/commits.tsv"
	tsv_sql commit_files 'repo, hash, path, lines_added, lines_deleted, is_binary' tttnnn "$out/commit_files.tsv"
	tsv_sql tags 'repo, tag, type, tag_date, commit_hash, tagger_is_person, subject' tttttnt "$out/tags.tsv"
	tsv_sql branches 'repo, ref, branch, committer_date, author_date, commit_hash' tttttt "$out/branches.tsv"
	tsv_sql git_identities 'repo, author_name, author_email, commits' tttn "$out/identities.tsv"
	echo "UPDATE commits SET author_utc = datetime(author_date), committer_utc = datetime(committer_date),"
	echo "  dates_differ = abs(strftime('%s', author_date) - strftime('%s', committer_date)) > 300 WHERE repo = $q;"
	echo 'COMMIT;'
}

run_sql() {
	if command -v sqlite3 >/dev/null 2>&1; then
		sqlite3 -bail "$1" <"$2"
		return
	fi
	local py
	for py in python3 python py; do
		# Windows has a python3 stub that only opens the Store: try each one.
		if command -v "$py" >/dev/null 2>&1 && "$py" -c 'import sqlite3' >/dev/null 2>&1; then
			"$py" -I -c '
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
with open(sys.argv[2], encoding="utf-8", errors="replace") as f:
    db.executescript(f.read())
db.close()' "$1" "$2"
			return
		fi
	done
	die "neither sqlite3 nor Python 3 is installed; the TSV files are in $CASE/git"
}

cmd_extract() {
	local arg dir n db=$CASE/master.sqlite used='' loaded=''
	mkdir -p "$CASE/git"
	# Scratch files stay on this computer instead of syncing with the case.
	tmp=$(mktemp -d "${TMPDIR:-/tmp}/git-history.XXXXXX")
	trap 'rm -rf "$tmp"' EXIT
	run_sql "$db" "$SCRIPT_DIR/schema.sql"
	for arg in "$@"; do
		resolve_source "$arg"
		# One folder per source, so two clones of one remote keep their own files.
		dir=$(safe_dir_name "$name") n=1
		while printf '%s\n' "$used" | grep -Fxq -- "$dir"; do
			n=$((n + 1))
			dir="$(safe_dir_name "$name")-$n"
		done
		used=$(printf '%s\n%s' "$used" "$dir")
		out=$CASE/git/$dir
		mkdir -p "$out"
		write_commits
		write_identities
		write_tags
		write_branches
		write_repo
		load_sql >"$tmp/load.sql"
		run_sql "$db" "$tmp/load.sql"
		loaded=$(printf '%s\n%s' "$loaded" "$name")
		awk -F '\t' -v name="$name" -v out="git/$dir" '
			NR > 1 { c++; f += $10; a += $11; d += $12 }
			END { printf "%s: %d own commits, %d files changed, +%d -%d lines -> %s\n", name, c, f, a, d, out }' "$out/commits.tsv"
		if [ "$kind" = clone ] && [ "$KEEP" = 0 ]; then
			rm -rf "$repo_dir"
			say "deleted the clone $repo_dir"
			rmdir "$CLONES" 2>/dev/null || true
		fi
	done
	say "loaded into $db"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
	identities | extract) ;;
	-h | --help | help)
		usage
		exit 0
		;;
	*)
		usage >&2
		exit 2
		;;
esac

CASE='' CLONES='' AUTHOR='' KEEP=0
while [ $# -gt 0 ]; do
	case $1 in
		--case)
			[ $# -ge 2 ] || die "--case needs a folder"
			CASE=$2
			shift 2
			;;
		--clones)
			[ $# -ge 2 ] || die "--clones needs a folder"
			CLONES=$2
			shift 2
			;;
		--author)
			[ $# -ge 2 ] || die "--author needs a pattern"
			AUTHOR=$2
			shift 2
			;;
		--keep-clone)
			KEEP=1
			shift
			;;
		--)
			shift
			break
			;;
		-*) die "unknown option: $1" ;;
		*) break ;;
	esac
done

[ -n "$AUTHOR" ] || die "--author is required"
[ $# -gt 0 ] || die "name at least one repository"
if [ -n "$CASE" ]; then
	[ -d "$CASE" ] || die "case folder not found: $CASE"
	CASE=$(cd "$CASE" && pwd)
	[ -n "$CLONES" ] || CLONES=$HOME/overtime-clones/$(basename "$CASE")
fi
export GIT_HISTORY_AUTHOR=$AUTHOR

if [ "$cmd" = identities ]; then
	cmd_identities "$@"
else
	[ -n "$CASE" ] || die "--case is required"
	cmd_extract "$@"
fi

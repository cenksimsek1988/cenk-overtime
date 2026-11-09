#!/usr/bin/env python3
"""models.py: regression checks on the daily table of an overtime case.

    python models.py --db CASE/master.sqlite --out CASE/work/queries [--model NAME]...

Reads the table `days` of master.sqlite: one row per calendar day of the
window, filled by the analysis (cenk-overtime:analyse, section 8). For each
model it writes into --out:
  model-<name>.sql   the query it read the rows with, and the samples it used
  model-<name>.csv   the rows the model used, with the columns derived from them
  model-<name>.txt   the full output of each fit
  model-<name>.json  estimates, 95% intervals, p-values, counts and a plain reading
and a copy of this script, so the court expert can run it again. Every result
also goes into the table `model_results`. Needs pandas, numpy, statsmodels and
scipy. Exit code 0 when the models ran (some give counts only: too few days, a
zero on one side of a comparison, or event days that match a calendar control
or another event), 1 when the table is missing or incomplete.

Models (NAME):
  event-days  out-of-hours traces per day on release, patch and incident days
              and in the 7 days before a release, against other days with the
              same weekday, month and year. Poisson, or negative binomial when
              the counts vary more than Poisson allows; errors clustered by
              week. Once on all days, once on days with any out-of-hours trace.
  weekends    weekend days with any out-of-hours trace, near a release or a fix
              or not: risk ratio, and Fisher's exact test for small counts.
  clocks      on days with both, the last commit against the last chat message
              and the last sent mail: Spearman correlation and the median gap.
  trend       out-of-hours traces per working day, week by week, over the
              window and between its phases; Newey-West errors over 4 weeks.
"""

import argparse
import hashlib
import json
import math
import os
import shutil
import sqlite3
import sys
import warnings
from datetime import datetime, timezone

try:
    import numpy as np
    import pandas as pd
    import scipy
    import statsmodels
    import statsmodels.api as sm
    from scipy import stats
    from statsmodels.stats.diagnostic import acorr_ljungbox
except ImportError as missing:
    sys.exit("models.py needs pandas, numpy, statsmodels and scipy; %s is missing. "
             "The Tools section of cenk-overtime:start installs them." % missing.name)

MIN_EVENT_DAYS = 5      # fewer days with a term: counts only, no estimate
FEW_EVENT_DAYS = 10     # fewer: the reading calls the estimate indicative
MIN_PAIRS = 10          # days with both clocks
MIN_WEEKS = 12
MIN_PHASE_WEEKS = 4
OVERDISPERSED = 1.5     # Pearson chi-square per degree of freedom of the Poisson fit
PRE_RELEASE_DAYS = 7
WEEK_LAGS = 4           # Newey-West lags of the weekly model
LJUNG_BOX_DAYS = 14

COLUMNS = ["day", "off", "phase", "ooh_traces", "ooh_chat", "ooh_mail", "ooh_commits",
           "last_chat_h", "last_mail_h", "last_commit_h", "release", "patch", "incident", "events_from"]
QUERY = "SELECT " + ", ".join(COLUMNS) + " FROM days ORDER BY day"
MODELS = ["event-days", "weekends", "clocks", "trend"]

RESULTS_DDL = """CREATE TABLE IF NOT EXISTS model_results (
  model     TEXT NOT NULL,  -- event-days, weekends, clocks, trend
  sample    TEXT NOT NULL,  -- all-days, active-days, weekend-days, chat-vs-commit, weeks...
  term      TEXT NOT NULL,  -- release, patch, incident, pre_release, near_release, rho, per_year, phase:<name>
  estimate  REAL,           -- rate ratio, risk ratio or correlation; NULL when skipped
  ci_low    REAL,
  ci_high   REAL,
  p_value   REAL,
  n         INTEGER,        -- days, weeks or day pairs in the sample
  n_event   INTEGER,        -- of which with the term
  method    TEXT,
  reading   TEXT,           -- the result in one plain sentence
  run_at    TEXT,
  PRIMARY KEY (model, sample, term)
)"""

TERM_TEXT = {
    "release": "release days",
    "patch": "patch days",
    "incident": "incident days",
    "pre_release": "days in the week before a release",
}


def fail(message):
    print("models.py: " + message, file=sys.stderr)
    sys.exit(1)


def num(x, digits=6):
    """Rounded, so reruns on other machines write the same files."""
    return None if x is None or not math.isfinite(x) else float("%.*g" % (digits, x))


def ratio(x):
    return "%.2f" % x if x < 10 else "%.1f" % x


def p_text(p):
    return "p < 0.001" if p < 0.001 else "p = %.3f" % p


# Input


def load_days(db):
    if not os.path.isfile(db):
        fail("database not found: " + db)
    con = sqlite3.connect(db)
    try:
        columns = [row[1] for row in con.execute("PRAGMA table_info(days)")]
        if not columns:
            fail("master.sqlite has no table days: run schema.sql of cenk-overtime:start, "
                 "then fill it as cenk-overtime:analyse, section 8 says")
        absent = [c for c in COLUMNS if c not in columns]
        if absent:
            fail("days lacks the columns " + ", ".join(absent) + " (see schema.sql)")
        frame = pd.read_sql_query(QUERY, con)
        try:
            window = dict(con.execute("SELECT key, value FROM case_info WHERE key IN ('window_from', 'window_to')"))
        except sqlite3.OperationalError:
            window = {}
    finally:
        con.close()
    return validate(frame, window)


def validate(frame, window):
    if frame.empty:
        fail("days is empty: fill it with one row per calendar day of the window")
    frame["date"] = pd.to_datetime(frame["day"], format="%Y-%m-%d", errors="coerce")
    bad = frame.loc[frame["date"].isna(), "day"].tolist()
    if bad:
        fail("days.day must be YYYY-MM-DD; not: " + ", ".join(map(str, bad[:5])))
    calendar = pd.date_range(frame["date"].min(), frame["date"].max(), freq="D")
    gaps = calendar.difference(pd.DatetimeIndex(frame["date"]))
    if len(gaps):
        fail("days needs one row per calendar day; %d missing, first %s" % (len(gaps), gaps[0].date()))
    first, last = str(frame["date"].min().date()), str(frame["date"].max().date())
    if window.get("window_from") and window.get("window_to") and \
            (first, last) != (window["window_from"], window["window_to"]):
        fail("days covers %s to %s, but case_info has the window %s to %s"
             % (first, last, window["window_from"], window["window_to"]))
    counts = pd.to_numeric(frame["ooh_traces"], errors="coerce")
    if counts.isna().any() or (counts < 0).any() or (counts % 1 != 0).any():
        fail("days.ooh_traces must be a whole number of 0 or more on every day")
    frame["ooh_traces"] = counts.astype(int)
    for flag in ("release", "patch", "incident"):
        values = pd.to_numeric(frame[flag], errors="coerce")
        if not values.isin([0, 1]).all():
            fail("days.%s must be 0 or 1 on every day" % flag)
        frame[flag] = values.astype(int)
    for column in ("last_chat_h", "last_mail_h", "last_commit_h"):
        frame[column] = pd.to_numeric(frame[column], errors="coerce")
    frame["off"] = frame["off"].where(frame["off"].notna() & (frame["off"].astype(str).str.strip() != ""))
    return frame


def derive(frame):
    """Calendar columns and event windows; rows are consecutive days, so row offsets are day offsets."""
    d = frame.copy()
    d["weekday"] = d["date"].dt.day_of_week
    d["month"] = d["date"].dt.month
    d["year"] = d["date"].dt.year
    d["week"] = d["date"].dt.strftime("%G-W%V")
    d["weekend"] = (d["weekday"] >= 5).astype(int)
    d["active"] = (d["ooh_traces"] > 0).astype(int)
    d["working"] = d["off"].isna().astype(int)
    release = d["release"].to_numpy()
    ahead = np.zeros(len(d), dtype=int)
    for k in range(1, PRE_RELEASE_DAYS + 1):
        if k < len(d):
            ahead[:-k] |= release[k:]
    event = (d["release"] | d["patch"] | d["incident"]).to_numpy()
    d["pre_release"] = (ahead & (1 - event)).astype(int)
    d["near_release"] = (release | ahead).astype(int)
    fix = (d["patch"] | d["incident"]).to_numpy()
    d["near_fix"] = (fix | np.concatenate([[0], fix[:-1]])).astype(int)
    return d


# Fitting


def design(frame, terms, controls):
    parts = [frame[terms].astype(float)] if terms else []
    for column in controls:
        if frame[column].nunique() > 1:
            parts.append(pd.get_dummies(frame[column].astype(str), prefix=column, drop_first=True, dtype=float))
    matrix = pd.concat(parts, axis=1) if parts else pd.DataFrame(index=frame.index)
    return sm.add_constant(matrix, has_constant="add")


def fit_counts(y, X, cov, offset=None):
    """Poisson, or negative binomial when the counts vary more than Poisson allows.

    Returns (result, method, dispersion). Without convergence the negative
    binomial gives way to Poisson with the same robust errors, which stays
    valid for the rate ratios when the counts vary more."""
    poisson = sm.GLM(y, X, family=sm.families.Poisson(), offset=offset).fit()
    dispersion = float(poisson.pearson_chi2 / poisson.df_resid) if poisson.df_resid > 0 else float("nan")
    note = ""
    if dispersion > OVERDISPERSED:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            try:
                nb = sm.NegativeBinomial(y, X, offset=offset).fit(disp=0, maxiter=500, **cov)
                if nb.mle_retvals.get("converged") and np.all(np.isfinite(nb.bse)):
                    return nb, "negative binomial", dispersion
            except (np.linalg.LinAlgError, ValueError):
                pass
        note = " (negative binomial did not converge)"
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        robust = sm.GLM(y, X, family=sm.families.Poisson(), offset=offset).fit(**cov)
    return robust, "Poisson" + note, dispersion


def mean_of(result):
    return np.asarray(result.mu) if hasattr(result, "mu") else np.asarray(result.predict())


def pearson(result, y):
    mu = mean_of(result)
    alpha = float(result.params["alpha"]) if "alpha" in result.params.index else 0.0
    return (np.asarray(y) - mu) / np.sqrt(mu + alpha * mu ** 2)


def rate_ratio(result, term):
    low, high = np.exp(result.conf_int().loc[term].to_numpy())
    return float(np.exp(result.params[term])), float(low), float(high), float(result.pvalues[term])


def week_groups(frame):
    return pd.factorize(frame["week"])[0]


def row(sample, term, estimate, low, high, p, n, n_event, method, reading):
    return {"sample": sample, "term": term, "estimate": num(estimate), "ci_low": num(low), "ci_high": num(high),
            "p_value": num(p), "n": int(n), "n_event": int(n_event), "method": method, "reading": reading}


def skipped(sample, term, n, n_event, reason, reading):
    entry = row(sample, term, None, None, None, None, n, n_event, "not estimated", reading)
    entry["reason"] = reason
    return entry


# Models


def few_days(sample, term, frame):
    n_event = int(frame[term].sum())
    noun = TERM_TEXT[term]
    if not n_event:
        return skipped(sample, term, len(frame), 0, "no such days", "No %s in this sample." % noun)
    reading = "Only %d %s: too few to test. They had on average %.1f out-of-hours traces, other days %.1f." % (
        n_event, noun, frame.loc[frame[term] == 1, "ooh_traces"].mean(), frame.loc[frame[term] == 0, "ooh_traces"].mean())
    return skipped(sample, term, len(frame), n_event, "fewer than %d days" % MIN_EVENT_DAYS, reading)


def no_traces(sample, term, frame):
    """No trace at all on a term's days separates the fit: its ratio runs to 0, with an interval of 0 to 0."""
    n_event = int(frame[term].sum())
    other = frame[frame[term] == 0]
    reading = "The %d %s had no out-of-hours traces, against %d on the %d other days; a ratio cannot be estimated with a zero." % (
        n_event, TERM_TEXT[term], other["ooh_traces"].sum(), len(other))
    return skipped(sample, term, len(frame), n_event, "no out-of-hours trace on these days", reading)


def no_traces_elsewhere(sample, term, frame, terms):
    """No trace outside the terms' days separates the fit the other way: the ratios run to infinity, or the fit fails."""
    n_event = int(frame[term].sum())
    reading = "The %d %s had %d out-of-hours traces, against none on the %d days that were not %s; a ratio cannot be estimated with a zero." % (
        n_event, TERM_TEXT[term], frame.loc[frame[term] == 1, "ooh_traces"].sum(),
        (frame[terms] == 0).all(axis=1).sum(), " or ".join(TERM_TEXT[t] for t in terms))
    return skipped(sample, term, len(frame), n_event, "no out-of-hours trace outside these days", reading)


def same_days(sample, term, frame):
    n_event = int(frame[term].sum())
    other = frame[frame[term] == 0]
    reading = "The %d %s fall on exactly the days of a weekday, month or year, or of another event: their effect cannot be told apart from it. " \
              "They had %d out-of-hours traces, the %d other days %d." % (
                  n_event, TERM_TEXT[term], frame.loc[frame[term] == 1, "ooh_traces"].sum(), len(other), other["ooh_traces"].sum())
    return skipped(sample, term, len(frame), n_event, "cannot be told apart from a control or another term", reading)


def told_apart(frame, terms, controls):
    """The terms that add something to the calendar controls and the terms before them; any other makes the fit singular."""
    if not terms:
        return []
    kept, rank = [], np.linalg.matrix_rank(design(frame, [], controls).to_numpy())
    for term in terms:
        new_rank = np.linalg.matrix_rank(design(frame, kept + [term], controls).to_numpy())
        if new_rank > rank:
            kept, rank = kept + [term], new_rank
    return kept


def event_days(d):
    controls = [c for c in ("weekday", "month", "year") if d[c].nunique() > 1]
    same = "with the same " + ", ".join(controls[:-1]) + (" and " if len(controls) > 1 else "") + controls[-1] \
        if controls else "of the window"
    samples = {"all-days": d[d["working"] == 1], "active-days": d[(d["working"] == 1) & (d["active"] == 1)]}
    results, fits, diagnostics, estimated = [], [], {}, set()
    for sample, frame in samples.items():
        enough = [t for t in TERM_TEXT if frame[t].sum() >= MIN_EVENT_DAYS]
        traced = [t for t in enough if frame.loc[frame[t] == 1, "ooh_traces"].sum() > 0]
        terms = told_apart(frame, traced, controls)
        for term in TERM_TEXT:
            # A term left out on all days is reported once, not again for the active days.
            if term in terms or (sample == "active-days" and term not in estimated):
                continue
            report = few_days if term not in enough else no_traces if term not in traced else same_days
            results.append(report(sample, term, frame))
        # With every trace on the terms' days there is nothing to compare them with, here or on the active days.
        if terms and frame.loc[(frame[terms] == 0).all(axis=1), "ooh_traces"].sum() == 0:
            results.extend(no_traces_elsewhere(sample, term, frame, terms) for term in terms)
            terms = []
        if sample == "all-days":
            estimated = set(terms)
        if not terms:
            break
        X = design(frame, terms, controls)
        groups = week_groups(frame)
        cov = {"cov_type": "cluster", "cov_kwds": {"groups": groups}}
        result, family, dispersion = fit_counts(frame["ooh_traces"], X, cov)
        method = "%s, %s controls, errors clustered by week (%d weeks)" % (family, "/".join(controls) or "no", len(set(groups)))
        lead = "Among days with any out-of-hours trace, " if sample == "active-days" else ""
        for term in terms:
            est, low, high, p = rate_ratio(result, term)
            n_event = int(frame[term].sum())
            noun = TERM_TEXT[term]
            reading = "%s%s had %s times as many out-of-hours traces as other days %s" % (
                lead, noun if lead else noun[0].upper() + noun[1:], ratio(est), same)
            if low <= 1 <= high:
                reading += ", but the data cannot tell this from no difference"
            reading += " (95%% CI %s to %s; %s; %d days, %d %s)." % (
                ratio(low), ratio(high), p_text(p), len(frame), n_event, noun)
            if n_event < FEW_EVENT_DAYS:
                reading += " Few such days: read it as indicative."
            results.append(row(sample, term, est, low, high, p, len(frame), n_event, method, reading))
        info = {"method": method, "pearson_dispersion": num(dispersion)}
        if "alpha" in result.params.index:
            info["alpha"] = num(float(result.params["alpha"]))
        if sample == "all-days" and len(frame) > 2 * LJUNG_BOX_DAYS:
            lb = acorr_ljungbox(pearson(result, frame["ooh_traces"]), lags=[LJUNG_BOX_DAYS], return_df=True)
            info["ljung_box_p_%dd" % LJUNG_BOX_DAYS] = num(float(lb["lb_pvalue"].iloc[0]))
        diagnostics[sample] = info
        fits.append(("event-days, %s: %s" % (sample, method), result, info))
    rows = d.assign(in_all_days=d["working"], in_active_days=d["working"] & d["active"])
    columns = ["day", "off", "ooh_traces", "release", "patch", "incident", "pre_release", "weekday", "month", "year",
               "week", "events_from", "in_all_days", "in_active_days"]
    return {"rows": rows[columns], "fits": fits, "results": results, "diagnostics": diagnostics,
            "samples": ["all-days: off IS NULL", "active-days: off IS NULL AND ooh_traces > 0"]}


def weekends(d):
    frame = d[(d["weekend"] == 1) & (d["working"] == 1)]
    texts = {"near_release": ("Weekend days in the week before a release, or on it,", "near a release"),
             "near_fix": ("Weekend days on or right after a patch or incident", "near a fix")}
    results, fits, diagnostics = [], [], {}
    for term, (subject, short) in texts.items():
        near, other = frame[frame[term] == 1], frame[frame[term] == 0]
        a, b = int(near["active"].sum()), int(other["active"].sum())
        counts = "%d of %d against %d of %d" % (a, len(near), b, len(other))
        if len(near) < MIN_EVENT_DAYS or len(other) < MIN_EVENT_DAYS:
            results.append(skipped("weekend-days", term, len(frame), len(near), "fewer than %d days in a group" % MIN_EVENT_DAYS,
                                   "Weekend days %s had out-of-hours traces on %s other weekend days: too few to test." % (short, counts)))
            continue
        fisher = stats.fisher_exact([[a, len(near) - a], [b, len(other) - b]]).pvalue
        if a == 0 or b == 0:
            results.append(row("weekend-days", term, None, None, None, fisher, len(frame), len(near), "Fisher's exact test",
                               "Weekend days %s had out-of-hours traces on %s other weekend days (Fisher's exact %s); "
                               "a ratio cannot be estimated with a zero." % (short, counts, p_text(fisher))))
            continue
        X = design(frame, [term], [])
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            result = sm.GLM(frame["active"], X, family=sm.families.Poisson()).fit(
                cov_type="cluster", cov_kwds={"groups": week_groups(frame)})
        est, low, high, p = rate_ratio(result, term)
        method = "risk ratio (Poisson with errors clustered by weekend); Fisher's exact test"
        reading = "%s had out-of-hours traces %s times as often as other weekend days (%s" % (subject, ratio(est), counts)
        reading += "; 95%% CI %s to %s; Fisher's exact %s)." % (ratio(low), ratio(high), p_text(fisher))
        if low <= 1 <= high:
            reading = reading[:-1] + "; the data cannot tell this from no difference."
        if len(near) < FEW_EVENT_DAYS:
            reading += " Few such days: read it as indicative."
        entry = row("weekend-days", term, est, low, high, fisher, len(frame), len(near), method, reading)
        entry["p_value_wald"] = num(p)
        results.append(entry)
        diagnostics[term] = {"weekend_days": len(frame), "near": len(near), "worked_near": a, "worked_other": b}
        fits.append(("weekends, %s: %s" % (term, method), result, diagnostics[term]))
    columns = ["day", "weekday", "week", "ooh_traces", "active", "near_release", "near_fix"]
    return {"rows": frame[columns], "fits": fits, "results": results, "diagnostics": diagnostics,
            "samples": ["weekend-days: weekday is Saturday or Sunday AND off IS NULL"]}


def clocks(d):
    names = {"chat": "chat message", "mail": "sent mail", "commit": "commit"}
    frame = d[d["working"] == 1]
    results, diagnostics, pairs = [], {}, []
    for first, second in (("chat", "commit"), ("mail", "commit"), ("chat", "mail")):
        x, y = "last_%s_h" % first, "last_%s_h" % second
        both = frame[["day", x, y]].dropna()
        sample = "%s-vs-%s" % (first, second)
        n = len(both)
        if n < MIN_PAIRS:
            results.append(skipped(sample, "rho", n, n, "fewer than %d days with both" % MIN_PAIRS,
                                   "Only %d days with both a %s and a %s: too few to compare." % (n, names[first], names[second])))
            continue
        rho, p = stats.spearmanr(both[x], both[y])
        rho, p = float(rho), float(p)
        if not math.isfinite(rho):
            results.append(skipped(sample, "rho", n, n, "one clock has the same time every day", "The times do not vary: no correlation to compute."))
            continue
        z, se = math.atanh(max(min(rho, 0.999999), -0.999999)), math.sqrt((1 + rho ** 2 / 2) / (n - 3))
        low, high = math.tanh(z - 1.96 * se), math.tanh(z + 1.96 * se)
        gap = (both[x] - both[y]).abs() * 60
        median_gap, within = float(gap.median()), float((gap <= 60).mean())
        reading = "On the %d days with both, the last %s and the last %s were a median %d minutes apart " \
                  "(within an hour on %d%% of them)" % (n, names[first], names[second], round(median_gap), round(100 * within))
        if low <= 0 <= high:
            reading += "; the data show no clear link between the two (Spearman %.2f, 95%% CI %.2f to %.2f; %s)." % (rho, low, high, p_text(p))
        else:
            reading += "; later ends on one went with later ends on the other (Spearman %.2f, 95%% CI %.2f to %.2f; %s)." % (rho, low, high, p_text(p))
        entry = row(sample, "rho", rho, low, high, p, n, n, "Spearman correlation, Fisher z interval (Bonett-Wright)", reading)
        entry["median_gap_min"], entry["share_within_60_min"] = num(median_gap), num(within)
        results.append(entry)
        diagnostics[sample] = {"days": n, "median_gap_min": num(median_gap), "share_within_60_min": num(within),
                               "mean_difference_min": num(float((both[x] - both[y]).mean() * 60))}
        pairs.append(both.rename(columns={x: "first_h", y: "second_h"}).assign(pair=sample))
    rows = pd.concat(pairs) if pairs else pd.DataFrame(columns=["day", "first_h", "second_h", "pair"])
    return {"rows": rows[["pair", "day", "first_h", "second_h"]], "fits": [], "results": results,
            "diagnostics": diagnostics, "samples": ["each pair: off IS NULL AND both last_*_h are set"]}


def weekly(d):
    frame = d.assign(counted=np.where(d["working"] == 1, d["ooh_traces"], 0))
    weeks = frame.groupby("week", sort=True).agg(start=("date", "min"), working_days=("working", "sum"),
                                                 traces=("counted", "sum"))
    phases = frame[frame["phase"].notna()].groupby("week")["phase"].agg(lambda s: s.mode().iloc[0])
    weeks["phase"] = phases.reindex(weeks.index)
    weeks = weeks[weeks["working_days"] > 0].sort_values("start").reset_index()
    weeks["years"] = (weeks["start"] - d["date"].min()).dt.days / 365.25
    return weeks


def trend(d):
    weeks = weekly(d)
    results, fits, diagnostics = [], [], {}
    n = len(weeks)
    rows = weeks.assign(start=weeks["start"].dt.strftime("%Y-%m-%d"))
    out = {"rows": rows[["week", "start", "working_days", "traces", "phase", "years"]], "fits": fits,
           "results": results, "diagnostics": diagnostics,
           "samples": ["weeks: ISO weeks with at least one day where off IS NULL; traces summed over those days"]}
    if n < MIN_WEEKS:
        results.append(skipped("weeks", "per_year", n, n, "fewer than %d weeks" % MIN_WEEKS,
                               "Only %d weeks: too few for a trend." % n))
        return out
    if not weeks["traces"].sum():
        results.append(skipped("weeks", "per_year", n, n, "no out-of-hours trace in any week",
                               "No out-of-hours traces in any of the %d weeks: no trend to estimate." % n))
        return out
    offset = np.log(weeks["working_days"].to_numpy(dtype=float))
    cov = {"cov_type": "HAC", "cov_kwds": {"maxlags": WEEK_LAGS}}
    result, family, dispersion = fit_counts(weeks["traces"], design(weeks, ["years"], []), cov, offset)
    method = "%s, working days as exposure, Newey-West errors (%d weeks)" % (family, WEEK_LAGS)
    est, low, high, p = rate_ratio(result, "years")
    change = "rose by %d%%" % round((est - 1) * 100) if est >= 1 else "fell by %d%%" % round((1 - est) * 100)
    reading = "Out-of-hours traces per working day %s a year over the window (rate ratio %s per year, 95%% CI %s to %s; %s; %d weeks)" % (
        change, ratio(est), ratio(low), ratio(high), p_text(p), n)
    reading += "; the data cannot tell this from no change." if low <= 1 <= high else "."
    results.append(row("weeks", "per_year", est, low, high, p, n, n, method, reading))
    diagnostics["trend"] = {"method": method, "pearson_dispersion": num(dispersion)}
    if n > 2 * WEEK_LAGS:
        lb = acorr_ljungbox(pearson(result, weeks["traces"]), lags=[WEEK_LAGS], return_df=True)
        diagnostics["trend"]["ljung_box_p_%dw" % WEEK_LAGS] = num(float(lb["lb_pvalue"].iloc[0]))
    fits.append(("trend: " + method, result, diagnostics["trend"]))
    phase_model(weeks, offset, cov, out)
    return out


def phase_model(weeks, offset, cov, out):
    """Each later phase against the first one, without the time trend: the two overlap."""
    named = weeks[weeks["phase"].notna()]
    order = named.groupby("phase")["start"].min().sort_values().index.tolist()
    sizes = named["phase"].value_counts()
    if len(order) < 2:
        return
    if (sizes < MIN_PHASE_WEEKS).any() or len(named) < len(weeks):
        reason = "every week needs a phase, and every phase %d weeks" % MIN_PHASE_WEEKS
        out["results"].append(skipped("weeks", "phases", len(weeks), len(named), reason,
                                      "Phases were not compared: %s." % reason))
        return
    traces = weeks.groupby("phase")["traces"].sum()
    compared = [p for p in order[1:] if traces[p] > 0 and traces[order[0]] > 0]
    for later in order[1:]:
        if later not in compared:
            # A zero on either side separates the fit, as on event days.
            out["results"].append(skipped(
                "weeks", "phase:" + later, len(weeks), int(sizes[later]), "no out-of-hours trace in one of the two phases",
                "The phase '%s' had %d out-of-hours traces in %d weeks, against %d in the %d weeks of '%s'; a ratio cannot be estimated with a zero." % (
                    later, traces[later], sizes[later], traces[order[0]], sizes[order[0]], order[0])))
    if not compared:
        return
    # A phase left out takes its weeks along: among the first phase's they would change what the others are compared with.
    used = weeks["phase"].isin(order[:1] + compared).to_numpy()
    frame = weeks[used].copy()
    dummies = {}
    for later in compared:
        column = "phase_%d" % (order.index(later))
        frame[column] = (frame["phase"] == later).astype(float)
        dummies[column] = later
    result, family, dispersion = fit_counts(frame["traces"], design(frame, list(dummies), []), cov, offset[used])
    method = "%s, working days as exposure, Newey-West errors (%d weeks); reference: %s" % (family, WEEK_LAGS, order[0])
    left_out = ", ".join("'%s'" % p for p in order[1:] if p not in compared)
    if left_out:
        method += "; without the weeks of " + left_out
        out["samples"].append("phases: without the weeks of %s (no out-of-hours trace); any weeks on either side count as adjacent in the Newey-West errors" % left_out)
    for column, later in dummies.items():
        est, low, high, p = rate_ratio(result, column)
        reading = "In the phase '%s' there were %s times as many out-of-hours traces per working day as in '%s' (95%% CI %s to %s; %s; %d and %d weeks)" % (
            later, ratio(est), order[0], ratio(low), ratio(high), p_text(p), sizes[later], sizes[order[0]])
        reading += "; the data cannot tell this from no difference." if low <= 1 <= high else "."
        out["results"].append(row("weeks", "phase:" + later, est, low, high, p, len(frame), int(sizes[later]), method, reading))
    out["diagnostics"]["phases"] = {"method": method, "pearson_dispersion": num(dispersion), "reference": order[0]}
    out["fits"].append(("phases: " + method, result, out["diagnostics"]["phases"]))


RUN = {"event-days": event_days, "weekends": weekends, "clocks": clocks, "trend": trend}


# Output


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def write_model(out_dir, name, model, d):
    base = os.path.join(out_dir, "model-" + name)
    with open(base + ".sql", "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Rows models.py read for the model %s.\n" % name)
        for sample in model["samples"]:
            f.write("-- Sample, applied in models.py: %s\n" % sample)
        f.write(QUERY + ";\n")
    model["rows"].to_csv(base + ".csv", index=False, lineterminator="\n", float_format="%.6g")
    with open(base + ".txt", "w", encoding="utf-8", newline="\n") as f:
        f.write("models.py %s on %d days, %s to %s\n" % (name, len(d), d["day"].iloc[0], d["day"].iloc[-1]))
        for result in model["results"]:
            f.write("\n" + result["reading"] + "\n")
        for title, fit, info in model["fits"]:
            f.write("\n== %s\n%s\n" % (title, fit.summary().as_text()))
            for key, value in info.items():
                f.write("%s: %s\n" % (key, value))
    summary = {
        "model": name,
        "script_sha256": sha256(os.path.abspath(__file__)),
        "libraries": {"python": sys.version.split()[0], "numpy": np.__version__, "pandas": pd.__version__,
                      "scipy": scipy.__version__, "statsmodels": statsmodels.__version__},
        "input": {"table": "days", "rows": len(d), "from": d["day"].iloc[0], "to": d["day"].iloc[-1]},
        "samples": model["samples"],
        "tests": sum(1 for r in model["results"] if r["estimate"] is not None or r["p_value"] is not None),
        "results": model["results"],
        "diagnostics": model["diagnostics"],
        "rerun": "python models.py --db master.sqlite --out <new folder> --model " + name,
    }
    with open(base + ".json", "w", encoding="utf-8", newline="\n") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)
        f.write("\n")


def save_results(db, name, results, run_at):
    con = sqlite3.connect(db)
    try:
        con.execute(RESULTS_DDL)
        con.execute("DELETE FROM model_results WHERE model = ?", (name,))
        con.executemany(
            "INSERT INTO model_results (model, sample, term, estimate, ci_low, ci_high, p_value, n, n_event, method, reading, run_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            [(name, r["sample"], r["term"], r["estimate"], r["ci_low"], r["ci_high"], r["p_value"], r["n"],
              r["n_event"], r["method"], r["reading"], run_at) for r in results])
        con.commit()
    finally:
        con.close()


def copy_script(out_dir):
    target = os.path.join(out_dir, "models.py")
    here = os.path.abspath(__file__)
    if not os.path.exists(target) or not os.path.samefile(here, target):
        shutil.copyfile(here, target)


def main():
    parser = argparse.ArgumentParser(description="Regression checks on the daily table of an overtime case.")
    parser.add_argument("--db", required=True, help="the case's master.sqlite")
    parser.add_argument("--out", required=True, help="folder for the model files, such as work/queries")
    parser.add_argument("--model", action="append", choices=MODELS, help="run only this model (repeatable)")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8", errors="replace", newline="\n")
    d = derive(load_days(args.db))
    os.makedirs(args.out, exist_ok=True)
    run_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    for name in args.model or MODELS:
        model = RUN[name](d)
        write_model(args.out, name, model, d)
        save_results(args.db, name, model["results"], run_at)
        print("== " + name)
        for result in model["results"]:
            print("  " + result["reading"])
    copy_script(args.out)
    print("files in " + args.out + "; results in model_results")


if __name__ == "__main__":
    main()

# Experimental Git consumption

Git consumption is experimental and supported only from a repository tag that
has a corresponding published GitHub Release.

## Rules

1. Never depend on `main`, a workspace path, a branch, or an arbitrary source
   commit.
2. Select one tag/Release whose notes declare a compatible Dartitect cohort.
3. Use that same cohort and tag for every Dartitect package in the dependency
   closure.
4. Copy package versions, Git URLs, refs, paths, and any required overrides from
   the relevant Release notes. Do not derive or guess coordinates from the
   repository tree.
5. If no compatible published GitHub Release exists, there is no supported
   consumption path.

A tag without a GitHub Release is not a documented distribution channel. A
GitHub Release for a different tag or cohort does not authorize mixing package
versions. Repository tools may validate a candidate, but validation does not
create a tag, publish a Release, or authorize consumption.

## Consumer verification

Commit the resolved lockfile, review that every Dartitect package comes from the
documented cohort, and run the consuming application's normal analysis, tests,
and platform builds. Treat a later cohort as a new dependency change and repeat
that review.

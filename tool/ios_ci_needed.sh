#!/usr/bin/env bash
# Reads changed file paths (one per line) on stdin and prints `true` when the
# pr-test `ios` job has to run, `false` when every change is documentation.
# An empty list prints `true`: when the diff can't be computed, run the job.
set -u

seen=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  seen=1
  case "$f" in
    *.md | docs/* | screenshots/* | .claude/*) ;;
    *) echo true; exit 0 ;;
  esac
done

if [ "$seen" = 1 ]; then echo false; else echo true; fi

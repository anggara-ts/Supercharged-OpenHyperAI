# Measuring a performance change in a game

For a change that is meant to save script time (#52): a cache, fewer engine calls, a cheaper check. The rule is in
`AGENTS.md` (Code conventions, "A performance change is measured in a game"). This is how to do it.

## Why a game, and why one game

- **Fewer engine calls are not less time.** A cache adds Lua work of its own. Maintainer, 2026-11-25: "the lua may
  call fewer API but overall CPU usage (API engine vs Lua) should be measured".
- **The tests' stub cannot weigh the two.** Its "engine" is Lua code with made-up costs. For #251 its two runs gave
  opposite answers (table below): interpreted, reusing the lists saved the most; compiled, it cost time. The scripts
  cannot see which of the two the game does.
- **Two games, one before and one after, cannot show it.** Two games of one build differ by 7% to 12% in script time
  (#153). The effects looked for are 1% to 4%.

So the change runs against the old code on neighbouring frames of the same game. `bots/dev/perf_ab.lua` does that:
every frame runs one variant ("arm") for the whole team, a block of frames runs every arm once in a shuffled order,
and `[SHy-AB]` prints each arm's script time per frame with its difference from the old code.

## When it runs

- **Off by default.** Nothing on `main` requires the harness, so an ordinary test game does not load it and prints
  no `[SHy-AB]` line. Every game already has `[SHy-PERF]` and `[SHy-PERFSUM]` for the script time as a whole.
- **Never in the Workshop.** The file is in `bots/dev/`. `tools/export-bots.js` copies that folder for a test game
  and leaves it out of a Workshop copy. A build whose scripts still require it cannot be exported for the Workshop.
- **On in the games that test a measurement PR, and only there.** There is no flag: the PR's `PerfAb.Define` is the
  switch. The PR goes into the tracker like any other (`node tools/verify.js add <pr>`), `tools/test-build.js`
  merges it into `test/next`, and `/prepare-game` says that the build holds an experiment.
- **The other PRs in that game are tested as usual.** Every variant decides the same things as the old code, so the
  game plays as if nothing was switched.

| #251, script time per frame against the old code | stub, interpreted | stub, compiled | games 083 and 084 |
|---|---|---|---|
| Turbo check once per frame | no difference | 1.7% less | 3.1% to 3.7% less: kept |
| hero checks once per frame | 3.5% less | no clear difference | 0.9% to 2.6% less: kept |
| nearby-hero lists once per frame | 10.2% less | 3.7% more | 0.9% to 2.5% more: dropped |

## Steps

1. **Put the change behind a switch.** The old code stays as it is, with one test in front of it.
   ```lua
   local PerfAb = require(GetScriptDirectory() .. "/dev/perf_ab")
   local switch = PerfAb.Define({
       name = "lotus",
       variants = {
           { name = "scan", on = { "scan" } },
           { name = "both", on = { "scan", "count" } },
       },
   })

   if switch.scan then
       -- the new code
   else
       -- the old code, unchanged
   end
   ```
   - One variant per piece alone, and one with all of them when there are several. `off` and `off2` (the old code
     twice) are added by the harness. At most 10 variants at a time.
   - Another file reads the same switches from the module that defined them (`Module.switch`).
   - Define it in a shared module (`bots/lib/...`), which loads once per team at the start. A definition that
     arrives later starts the totals again.
   - A change with its own self-check calls `PerfAb.Stop("<why>")` when the check fails: every switch goes off.
2. **List the file** in `MEASURING` in `tests/test_perf_ab.lua` (the test that no bot script requires the harness),
   with the issue number.
3. **Check outside the game that no decision changes** (LuaJIT, from the repo root, about 20 seconds per run):
   ```
   luajit tests/decision_trace.lua run local/perf/off  --arm off
   luajit tests/decision_trace.lua run local/perf/scan --arm lotus.scan
   luajit tests/decision_trace.lua compare local/perf/off local/perf/scan
   ```
   - Every arm must say "decisions: the same". The engine-call counts below that line say how many calls the variant
     saves; they are not a time.
   - `off` must be the old code: run the tool in a checkout of `origin/main` too (`git worktree add ../main
     origin/main`) and compare. Only `GameTime` may differ, by the harness's one call per timed entry point.
   - Put the numbers in the PR.
4. **Open the PR as a draft** with "Measurement build: do not merge as it is" as its first line. Its "How to verify in
   game" list (the arm names are the PR's own):
   ```
   - [ ] `[SHy-AB] defined exp=lotus` prints once per bot team <!-- expect: seen>=1 -->
   - [ ] `[SHy-AB] arm=lotus.both` prints about every 5 minutes for both teams <!-- expect: seen>=6 -->
   - [ ] Manual: `[SHy-AB] arm=off2` on the last line of each team has z and sign between -3 and 3
   - [ ] `[SHy-AB] stopped` does not print <!-- expect: absent -->
   - [ ] Manual: no `[SHy-ERROR]` line that names perf_ab or the changed files
   - [ ] Manual: the last `[SHy-AB]` line of every arm and team is posted on the issue
   - [ ] Manual, maintainer only: the keep or drop decision is recorded on the issue
   ```
5. **Play two games** with different heroes (`/prepare-game`; the test build takes drafts too).
6. **Read the last line of every arm and team** and post them on the issue card:
   - `off2` first. It is the old code against itself: z and sign must be between -3 and 3. If not, nothing else is
     read before that is explained.
   - z or sign under -3: faster than the old code. Over 3: slower. In between: no difference that can be told.
   - `over8=`, `over16=` and `max=` must be no worse: the long frames are what a player sees.
   - A piece stays when it is faster for both teams in both games.
7. **The maintainer decides** which pieces stay. Record it on the issue card, quoted.
8. **Take the experiment out**: the `PerfAb.Define`, every switch test, the code path that lost, and the `MEASURING`
   entry. What stays is plain code, always on. One more game confirms it, then the PR merges. A build that still has
   an experiment is not merged.

## The line

```
[SHy-AB] t=3810 weaver arm=turbo frames=19500 ms/frame=2.3019 d=-0.0791 se=0.0165 z=-4.8 pct=-3.3 faster=9187
slower=8746 sign=-3.3 blocks=19500 over2=8137 over4=2425 over8=200 over16=3 max=26.5 calls=773293 slow=98
kb/frame=95.7 gc=17116 jit=na tick=0.0153
```

(game 084, one line in the log; the version of #252 also printed `on=`.) The fields are explained at the top of
`bots/dev/perf_ab.lua`. In short: `ms/frame=` is the team's script time per frame in this arm, `d=` its mean
difference from the `off` frame of the same block, `se=` the standard error of `d`, `z=` their ratio, `pct=` `d` as a
share of `off`, and `faster=` / `slower=` / `sign=` the same comparison by count.

## What it cannot tell

- **Each team has its own Lua state**, so each team measures by itself and prints its own lines. They are two
  samples of one game, not two games.
- **Whether the game compiles the scripts.** `jit=` was `na` in games 083 and 084: the scripts cannot see it.
- **What switching costs.** A variant runs one frame at a time. A change that only pays off after several frames in a
  row (a cache that lives longer than a frame) is not measured fairly this way.
- **A frame nobody timed.** Only the entry points wrapped by `Perf.Wrap` count.

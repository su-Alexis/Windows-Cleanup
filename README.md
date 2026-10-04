# Windows Cleanup

A Windows batch script that scans first, shows you what it found, and only then
asks what to delete. Nothing is removed before you pick an option.

---

## Usage

Double-click it, or run it from a command line. It needs administrator rights and
elevates itself.

It works in three phases:

1. **Scan** — measures the temp locations, lists not-responding applications, and
   checks which browsers are running. Nothing is changed.
2. **Menu** — shows the totals and waits for your choice.
3. **Act** — does only what you picked.

```
    [1]  Do everything   Close the hung apps above, delete everything
                         above, empty the Recycle Bin for good, run
                         Disk Cleanup, then trim memory.
                         Your Downloads are NOT touched.

    [2]  Trim only       Free memory only - nothing is deleted

    [3]  Keep browsers   Same as [1], but browser memory left alone

    [4]  Kill hung only  Force-close the not-responding apps listed
                         above. Unsaved work in them is lost.

    [5]  Clean + Downloads
                         Everything in [1] PLUS Downloads older than
                         N days, sent to the Recycle Bin

    [6]  Exit            Change nothing
```

Anything that is not `1`–`6` re-asks quietly. After ten unusable answers it exits
without changing anything.

## What it will and will not touch

**Downloads are never touched unless you explicitly pick `[5]`**, and even then
only files older than the cutoff, and they go to the **Recycle Bin** rather than
being deleted outright — so that choice is recoverable.

Option `[1]` empties the Recycle Bin for good. That is not recoverable, which is
why it is spelled out on the menu rather than hidden in a summary.

Option `[4]` force-closes applications. Unsaved work in them is lost. If the
script cannot read an answer to that prompt, it **leaves the applications
running** rather than guessing — that is the safe side of the question.

## What it writes

A `cleanup.log` beside the script, trimmed to its last 300 lines on each run so it
does not grow without bound. Its working files are also created beside the script
and removed as it goes.

Because every path it uses is relative to the script's own folder, you can keep a
copy wherever you like and its log stays with it.

## Design notes

- Scan before menu before act: you see the numbers before you commit to anything.
- The dangerous options are labelled on the menu, not buried.
- Downloads go to the Recycle Bin. The Recycle Bin itself is only emptied when you
  choose an option that says so.
- Prompts re-ask quietly on a mistyped key rather than beeping, and give up after
  ten unusable answers. The force-close prompt fails safe to *not* closing things.
- Disk Cleanup is invoked through the built-in Windows handler rather than deleting
  system locations directly.

## Caveats

- Emptying the Recycle Bin is permanent.
- Force-closing an application loses unsaved work in it.
- Clearing temp directories can sign you out of some applications or clear their
  caches, which is normal and self-healing.
- Trimming memory asks Windows to release working sets; applications may be
  briefly slower afterwards as they page back in.

## Requirements

Windows 10 or 11. Administrator rights (it elevates itself). No dependencies.

## License

MIT - see [LICENSE](LICENSE).

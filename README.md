# Windows Cleanup

A Windows batch script that scans first, shows you what it found, and only then
asks what to delete. Nothing is removed before you pick an option.

This is the standalone copy of the `cleanup_main.bat` that
[winGG10&11](https://github.com/su-Alexis/winGG10-11) writes to the Desktop. The two
are kept byte-identical: if they ever differ, the copy embedded in winGG10&11 is the
current one.

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

## What it cleans

The same fixed list is used twice, once to measure and once to clean. Only the
*contents* of each folder are removed, never the folder itself.

| Target | Folder |
|---|---|
| User temp | `%TEMP%` (only if it is a `Temp` or `Tmp` folder, see below) |
| User temp (alt) | `%LOCALAPPDATA%\Temp` |
| System temp | `%SystemRoot%\Temp` |
| Windows Update cache | `%SystemRoot%\SoftwareDistribution\Download` |
| Delivery Optimization | `%SystemRoot%\SoftwareDistribution\DeliveryOptimization` |
| Crash dumps | `%LOCALAPPDATA%\CrashDumps` |
| Error reports | `%ProgramData%\Microsoft\Windows\WER\ReportQueue` and `ReportArchive` |
| Thumbnail/icon cache | `*cache_*.db` in `%LOCALAPPDATA%\Microsoft\Windows\Explorer` |

It also flushes the DNS cache and starts Windows' idle-maintenance tasks in the
background. Disk Cleanup runs with the handlers you tick in its own list.

### Guards

- **`%TEMP%` is checked first.** It is the only target whose whole path a user or
  program can redirect, so it is cleaned only when its last folder is named `Temp`
  or `Tmp`. Anything else (a custom scratch folder, a per-session `\Temp\2`) is
  logged as `REFUSED` and left alone. `%LOCALAPPDATA%\Temp` is cleaned either way.
- **The delete routine refuses** an empty path, a drive root, and the Windows,
  System32, Users, Program Files, ProgramData, profile, AppData and LocalAppData
  folders themselves, in case an environment variable ever resolves to one of them.
- Browser profiles are not on the target list, so bookmarks, passwords and history
  are not touched. If a browser is running, the scan warns you because `%TEMP%` can
  hold an in-progress download.

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
- Only fixed cache and temp folders are deleted directly. Everything else Windows
  keeps (old installs, update leftovers, and so on) goes through Disk Cleanup's own
  handlers, which you tick before it runs.

## Caveats

- Emptying the Recycle Bin is permanent.
- Force-closing an application loses unsaved work in it.
- Clearing temp directories can sign you out of some applications or clear their
  caches, which is normal and self-healing.
- Trimming memory asks Windows to release working sets; applications may be
  briefly slower afterwards as they page back in.

## A note on antivirus

An earlier revision listed the browser profile folders by name in the refuse list
and said so on screen. Embedded in winGG10&11, that version was flagged by Microsoft
Defender (through AMSI) as `Trojan:BAT/CryptoDrainer.C!MTB`, which we believe is a
false positive. Those entries could never match (only the fixed targets above are
ever passed in), so they were removed, and the flagged and fixed versions were
tested side by side. This copy is the fixed version.

## Related tools

- [winGG10&11](https://github.com/su-Alexis/winGG10-11): the Windows setup script
  that deploys this and the two tools below.
- [Network Refresh](https://github.com/su-Alexis/Network-Refresh)
  (`net-reset-lite.bat`): clears network caches and renews leases, no reboot.
- [Network Stack Reset](https://github.com/su-Alexis/Network-Stack-Reset)
  (`net-reset-reboot.bat`): full TCP/IP and Winsock reset, needs a reboot.

## Requirements

Windows 10 or 11. Administrator rights (it elevates itself). No dependencies.

## License

MIT - see [LICENSE](LICENSE).

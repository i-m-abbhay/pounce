# Contributing

Thanks for helping out. pounce is a single PowerShell script, so changes stay small and easy to review.

## Reporting bugs

[Open an issue](../../issues/new/choose) using the bug template. Include:

- your Windows version and terminal (Windows Terminal, Cursor, VS Code, ...)
- what you expected, and what happened instead
- any error output from running the script by hand (see "Try it" in the README)

## Asking for macOS or Linux support

Use the platform request template, and say which OS, desktop environment and terminal you use. Knowing who needs which platform decides what gets ported first.

## Pull requests

- Keep `pounce.ps1` **ASCII-only**. Windows PowerShell 5.1 reads files without a BOM as ANSI, so non-ASCII characters break. Build any special characters from code points, e.g. `[char]0x2715`.
- Target Windows PowerShell 5.1 (`powershell.exe`), not only PowerShell 7.
- Check that the script parses:
  ```powershell
  $e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile("$PWD\pounce.ps1", [ref]$null, [ref]$e); $e
  ```
- Try both events with `$env:POUNCE_FORCE = '1'` (see the README), and run `-Pick` if you touched mascots.
- If your change affects how it looks, add a screenshot.

## New mascots

Built-in mascots live in the `$sprites` table in `pounce.ps1`. Use `#` for body, `o` for eyes, and `.` for empty cells; the last row is the feet. A sprite should be about 14 columns wide, have eyes, and have feet in the last row. Only submit original art; no brand characters.

## License

By contributing, you agree that your contributions are licensed under the MIT License.

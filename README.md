# LogSn🐽ut

This program is quite simple to use, and faster than many log utilities (Because it uses the system's `grep` instead of dozens of libs and packages - It takes 8 seconds to load and filter a 1,000,000 line log file on a mid-spec laptop).

Usage: **logsnout.sh [conf | logfile]**

Once viewing the file, the following commands are available:

- **Search**: Press `Space` to enter a regex to filter the results.
- **Exclude**: Press `Tab` to enter a regex to exclude from the search.
- Navigate with the arrow keys, PgUp and PgDown, Home and End, or the mouse scrollwheel.
- Press `Q` or `Ctrl+C` to exit.
- Press `G` to go to a specific line.
- Press `F` to use Find mode. Enter a search regex, then cycle results with PgUp and PgDown.
- Press `?` for help.
- Mode toggling keys:
  - `P`: Power scroll (mouse wheel scrolls 1% of the file at a time instead of 3 lines)
  - `L`: Line wrap
  - `B`: Tabulate ( Line up fields in rows - only if line wrap is off )
  - `C`: Case sensitivity
  - `E`: Error
  - `W`: Warning
  - `I`: Info
  - `D`: Debug
  - `O`: Other

The `conf` argument lets you edit the config file to change the regexes available for syntax highlighting and shortcut macros.

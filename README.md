# dopack

**Collect every user-written file needed to run a Stata do-file or ado-command.**

`dopack` reads a main do-file (or an ado-file) *statically* — the code is never run — and follows everything that would run:

- do-files called with `do`, `run` and `include`, also inside loops and nested do-files;
- user-written commands (ado-files on PERSONAL, PLUS, SITE, OLDPLACE, the working directory or folders added with `adopath`), followed recursively, with their help files;
- companion files: help includes (`.ihlp`) and family help files (`mycmd_postestimation`), dialogs (`.dlg`, `.idlg`, child dialogs, `db`/`view dialog`), classes (`.class`, incl. parents and member classes), Mata (`.mata`, `.mo`, and the user `.mlib` libraries of the Mata functions the code calls, found with `mata which`), plugins, Java `.jar` files, Python scripts and modules, business calendars (`.stbcal`), graph recordings (`.grec`), graph schemes, `findfile` targets, files run by ado-files, `predict`/`estat` subcommands, and every file of packages installed with `net install`/`ssc install` (from `stata.trk`);
- changes of the working directory (`cd`, `chdir`) and of the ado-path (`adopath`, `sysdir set`).

All files that are not part of the Stata installation are copied to an empty folder, with the do-file tree kept intact (so relative paths still work; scripts and calendars used by the do-files are mirrored the same way) and the ado-files in a subfolder `ado/`. A `readme.md` is written that states the purpose of the code, how to run it, every file in the package and every working-directory change. Absolute paths and anything that could not be resolved statically are flagged. Data files are not collected.

## Installation

```stata
net install dopack, from("https://raw.githubusercontent.com/szabobarnaKI/dopack/main/") replace
help dopack
```

Requires Stata 16 or later.

## Examples

```stata
* see what would be collected, copy nothing
dopack using "C:/projects/study/master.do", dryrun

* build the package
dopack using "C:/projects/study/master.do", to("C:/share/study_code") ///
    purpose("Main analyses of the study.")

* skip the Mata library lookup (mata which)
dopack using "C:/projects/study/master.do", dryrun nomatalibs

* package a single user-written command with everything it needs
dopack using "C:/ado/personal/mycmd.ado", to("C:/share/mycmd")

* an ado-file named without a path: working directory first, then the ado-path
dopack using mycmd.ado, to("C:/share/mycmd")
```

## Limitations

The code is read, not run. Macros, `foreach`/`forvalues` loops, `=` expressions and extended macro functions are resolved where possible (expressions are evaluated in an empty frame); paths that depend on data in memory or on results of estimation commands stay unresolved and are reported as warnings. Both branches of `if`/`else` are followed. When a command line starts with a macro that cannot be resolved (for example `` `=cond(...,"quietly","")' mycmd ``), the word after it is also looked up. Ado-files are found along the ado-path as it is when `dopack` runs, so a command whose folder is not on the ado-path cannot be collected; commands that were not found are listed, separately for the do-files (`r(notfound)`) and for the code inside the collected ado-files (`r(notfound_ado)`). Abbreviations of built-in commands may appear in these lists. Code inside dynamic documents (`dyndoc`, `dyntext`, `markstat`) is not followed; the source file is collected and a note asks to check it by hand. Run `dopack` without `quietly`, otherwise the Mata library lookup cannot read the answers of `mata which` (a warning says so).

## Author

Barna Szabo, Karolinska Institutet (written with Claude).

## License

MIT — see [LICENSE](LICENSE).

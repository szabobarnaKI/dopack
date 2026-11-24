# dopack

**Collect every user-written file needed to run a Stata do-file or ado-command.**

`dopack` reads a main do-file (or an ado-file) *statically* — the code is never run — and follows everything that would run:

- do-files called with `do`, `run` and `include`, also inside loops and nested do-files;
- user-written commands (ado-files on PERSONAL, PLUS, SITE, OLDPLACE, the working directory or folders added with `adopath`), followed recursively, with their help files;
- companion files: `.ihlp`, `.dlg`, `.mata`, `.class`, `.mo`, `l<name>.mlib`, `findfile` targets, files run by ado-files, `predict`/`estat` subcommands, graph schemes, and every file of packages installed with `net install`/`ssc install` (from `stata.trk`);
- changes of the working directory (`cd`, `chdir`) and of the ado-path (`adopath`, `sysdir set`).

All files that are not part of the Stata installation are copied to an empty folder, with the do-file tree kept intact (so relative paths still work) and the ado-files in a subfolder `ado/`. A `readme.md` is written that states the purpose of the code, how to run it, every file in the package and every working-directory change. Absolute paths and anything that could not be resolved statically are flagged. Data files are not collected.

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

* package a single user-written command with everything it needs
dopack using "C:/ado/personal/mycmd.ado", to("C:/share/mycmd")
```

## Limitations

The code is read, not run. Macros, `foreach`/`forvalues` loops, `=` expressions and extended macro functions are resolved where possible (expressions are evaluated in an empty frame); paths that depend on data in memory or on results of estimation commands stay unresolved and are reported as warnings. Both branches of `if`/`else` are followed. Abbreviations of built-in commands may appear in the list of commands that were not found.

## Author

Barna Szabo, Karolinska Institutet (written with Claude).

## License

MIT — see [LICENSE](LICENSE).

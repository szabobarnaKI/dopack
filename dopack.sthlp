{smcl}
{* *! version 0.1.0  21nov2026}{...}
{title:Title}

{phang}
{bf:dopack} {hline 2} Collect every user-written file needed to run a do-file or an ado-command


{title:Syntax}

{p 8 16 2}
{cmd:dopack} {cmd:using} {it:filename}{cmd:,} {opt to(folder)} [{it:options}]

{p 8 16 2}
{cmd:dopack} {cmd:using} {it:filename}{cmd:,} {opt dry:run} [{it:options}]

{pstd}
{it:filename} is the main do-file, or an ado-file. If {it:filename} has no
extension and does not exist, {cmd:.do} is added.

{synoptset 22}{...}
{synopthdr}
{synoptline}
{synopt:{opt to(folder)}}folder that receives the files; required unless {opt dryrun}{p_end}
{synopt:{opt replace}}empty {it:folder} first if it is not empty{p_end}
{synopt:{opt dry:run}}report what would be collected; copy nothing{p_end}
{synopt:{opt pur:pose(text)}}purpose of the code, written to {cmd:readme.md}{p_end}
{synopt:{opt ti:tle(text)}}title of {cmd:readme.md}; default is the name of the main file{p_end}
{synopt:{opt start:dir(folder)}}working directory when the main do-file starts; default is the folder of the main file{p_end}
{synopt:{opt root(folder)}}top folder of the copied do-file tree; default is the deepest folder that holds all do-files{p_end}
{synopt:{opt max:visits(#)}}stop after # do-file visits; default 5000{p_end}
{synoptline}


{title:Description}

{pstd}
{cmd:dopack} reads the main file and, without running anything, follows the
code that would run: do-files called with {cmd:do}, {cmd:run} and
{cmd:include} (also inside loops and in other do-files), and the commands
the code uses. Every file that is not part of the Stata installation is
copied to {it:folder}, together with a {cmd:readme.md} that states the
purpose of the code and how to run it.

{pstd}
What is collected:

{p 8 12 2}- do-files reached from the main file; their folder structure is
recreated below {it:folder} relative to a common root folder, so relative
{cmd:cd}, {cmd:do} and {cmd:run} paths keep working;{p_end}
{p 8 12 2}- user-written ado-files (from PERSONAL, PLUS, SITE, OLDPLACE, the
working directory or folders added with {cmd:adopath}), followed
recursively, with their help files ({cmd:.sthlp}, {cmd:.hlp}); these go to
the subfolder {cmd:ado} ({cmd:_ado} if the do-file tree already has a folder
{cmd:ado});{p_end}
{p 8 12 2}- companion files: files with the same name as an ado-file
({cmd:.ihlp}, {cmd:.dlg}, {cmd:.mata}, {cmd:.class}, {cmd:.mo}),
{cmd:l}{it:name}{cmd:.mlib}, files located with {cmd:findfile}, files run or
included by ado-files, {cmd:predict}/{cmd:estat} subcommands named in
{cmd:ereturn local predict} and {cmd:ereturn local estat_cmd}, graph schemes
named in {cmd:set scheme} or {cmd:scheme()}, and, for packages installed
with {cmd:net install} or {cmd:ssc install}, every file of the package as
listed in {cmd:stata.trk}.{p_end}

{pstd}
Data files are not collected.

{pstd}
Working-directory changes ({cmd:cd}, {cmd:chdir}) are followed while reading,
so later relative paths are resolved correctly, and they are listed on screen
and in {cmd:readme.md} together with the folder they point to in the package.
Absolute paths in the code are flagged, because they must be edited before
the code runs elsewhere. Changes of the ado-path ({cmd:adopath +},
{cmd:adopath ++}, {cmd:sysdir set}) are followed too.

{pstd}
{it:folder} must be empty or new. It may not contain any of the files to be
collected, the current working directory, your home folder or a Stata
system folder; {opt replace} never deletes such a folder.


{title:How the code is read}

{pstd}
{cmd:dopack} reads the code statically. Comments, {cmd:///} continuation
lines and {cmd:#delimit ;} are handled. Local and global macros are
followed: {cmd:local}/{cmd:global} definitions with text, {cmd:=}
expressions and extended functions (such as {cmd::dir} and {cmd::env}),
{cmd:args} of called do-files, {cmd:c(pwd)} (the tracked working directory)
and other {cmd:c()} values, globals already defined in your Stata session,
and {cmd:foreach}/{cmd:forvalues} loops (each iteration is followed).
Expressions are evaluated in an empty frame, so anything that depends on
the data in memory stays unresolved.

{pstd}
Both branches of {cmd:if}/{cmd:else} are followed, and loop bodies whose
values cannot be determined are read once. A do-file called with a path
that cannot be determined is reported as a warning; such files must be
added by hand. Commands inside {cmd:program define} blocks are collected,
but {cmd:cd} inside a program definition is not applied.

{pstd}
Command names that are neither built-in nor found as ado-files are listed
at the end; abbreviations of built-in commands (for example {cmd:gen}) also
appear there.


{title:Stored results}

{pstd}
{cmd:dopack} stores the following in {cmd:r()}:

{synoptset 16 tabbed}{...}
{p2col 5 16 20 2: Scalars}{p_end}
{synopt:{cmd:r(n_do)}}number of do-files{p_end}
{synopt:{cmd:r(n_ado)}}number of ado-files{p_end}
{synopt:{cmd:r(n_other)}}number of other files (help, companions){p_end}
{synopt:{cmd:r(n_cd)}}number of working-directory changes{p_end}
{synopt:{cmd:r(n_unres)}}number of items that could not be resolved{p_end}
{synopt:{cmd:r(n_warn)}}number of warnings{p_end}
{synopt:{cmd:r(n_copied)}}number of files written, including {cmd:readme.md}{p_end}

{p2col 5 16 20 2: Macros}{p_end}
{synopt:{cmd:r(mainfile)}}main file{p_end}
{synopt:{cmd:r(root)}}root folder of the do-file tree{p_end}
{synopt:{cmd:r(startdir)}}assumed working directory at the start{p_end}
{synopt:{cmd:r(target)}}target folder{p_end}
{synopt:{cmd:r(dofiles)}}do-files, relative to the root{p_end}
{synopt:{cmd:r(adofiles)}}names of the ado-files{p_end}
{synopt:{cmd:r(otherfiles)}}names of the other files{p_end}
{synopt:{cmd:r(notfound)}}commands found neither as built-in nor as ado-file{p_end}


{title:Examples}

{phang2}{cmd:. dopack using "C:/projects/study/master.do", dryrun}{p_end}
{phang2}{cmd:. dopack using "C:/projects/study/master.do", to("C:/share/study_code") purpose("Main analyses of the study.")}{p_end}
{phang2}{cmd:. dopack using master.do, to(../package) replace startdir(C:/projects/study)}{p_end}
{phang2}{cmd:. dopack using "C:/ado/personal/mycmd.ado", to("C:/share/mycmd")}{p_end}


{title:Author}

{pstd}
Barna Szabo, Karolinska Institutet (written with Claude).
{p_end}

{smcl}
{* *! version 0.2.1  26nov2026}{...}
{title:Title}

{phang}
{bf:dopack} {hline 2} Collect every user-written file needed to run a do-file or an ado-command


{title:Syntax}

{p 8 16 2}
{cmd:dopack} {cmd:using} {it:filename}{cmd:,} {opt to(folder)} [{it:options}]

{p 8 16 2}
{cmd:dopack} {cmd:using} {it:filename}{cmd:,} {opt dry:run} [{it:options}]

{pstd}
{it:filename} is the main do-file, or an ado-file. A relative
{it:filename} is taken from the working directory. If {it:filename} has no
extension and does not exist, {cmd:.do} and then {cmd:.ado} are added. An
ado-file named without a path (for example {cmd:mycmd.ado} or {cmd:mycmd})
that is not in the working directory is searched along the ado-path, as
{cmd:findfile} does.

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
{synopt:{opt nomata:libs}}do not look up the libraries of the Mata functions the code calls{p_end}
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
({cmd:.ihlp}, {cmd:.dlg}, {cmd:.idlg}, {cmd:.mata}, {cmd:.class}, {cmd:.mo},
{cmd:.plugin}), {cmd:l}{it:name}{cmd:.mlib}, the dialog {it:name}{cmd:.dlg}
also when it lies in another folder of the ado-path, files located with
{cmd:findfile}, files run or included by ado-files (do-files run by an
ado-file are read like the ado-file), {cmd:predict}/{cmd:estat} subcommands
named in {cmd:ereturn local predict} and {cmd:ereturn local estat_cmd}, and,
for packages installed with {cmd:net install} or {cmd:ssc install}, every
file of the package as listed in {cmd:stata.trk};{p_end}
{p 8 12 2}- dialog files: dialogs opened with {cmd:db} {it:name},
{cmd:view dialog} {it:name} or a {cmd:window menu} item; inside dialog files,
{cmd:INCLUDE} files ({cmd:.idlg}), child dialogs ({cmd:create CHILD}) and the
user-written command the dialog runs (first word of a {cmd:put} string);{p_end}
{p 8 12 2}- help files: {cmd:INCLUDE help} files ({cmd:.ihlp}), and help files
and dialogs of the same command family linked from a help file (in the same
folder, with a name that starts with the name of the linking help file, such
as {it:mycmd}{cmd:_postestimation.sthlp});{p_end}
{p 8 12 2}- class files ({cmd:.class}): classes created with
{cmd:.}{it:classname}{cmd:.new}, member variables of a class type and parent
classes named in {cmd:inherit()}, followed recursively; the member programs
in a class file are read like an ado-file;{p_end}
{p 8 12 2}- Mata: the functions called in {cmd:mata:} blocks, {cmd:mata:}
lines and {cmd:.mata} files; a function stored in {it:name}{cmd:.mo} is
collected, and the library ({cmd:.mlib}) of every other function is looked
up with {cmd:mata which} (see below);{p_end}
{p 8 12 2}- plugins ({cmd:program} {it:name}{cmd:, plugin}
[{cmd:using(}{it:file}{cmd:)}]), Java archives named in {cmd:javacall ..., jars()},
Python scripts run with {cmd:python script} and Python modules imported in
{cmd:python:} code (when the module {it:name}{cmd:.py} lies on the ado-path),
business calendars ({cmd:%tb}{it:name} formats, {cmd:bcal load}), graph
recordings ({cmd:play()}, {cmd:graph play}), graph schemes named in
{cmd:set scheme} or {cmd:scheme()} and the schemes they {cmd:#include}, and
source files of {cmd:dyndoc}, {cmd:dyntext} and {cmd:markstat} (the Stata code
inside them is not followed).{p_end}

{pstd}
Files used by the do-files and found relative to the working directory (a
Python script, a business calendar, a {cmd:dyndoc} source, ...) keep their
place in the folder tree; all other files go to the subfolder {cmd:ado}.

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
but {cmd:cd} inside a program definition is not applied. Text blocks of
{cmd:putdocx}/{cmd:putpdf textblock}, {cmd:input} data and {cmd:java:} blocks
are skipped; {cmd:mata:} blocks are read only for the functions they call and
{cmd:python:} blocks only for the modules they import.

{pstd}
{ul:Mata libraries.} Which library holds a Mata function cannot be read from
the {cmd:.mlib} file, so {cmd:dopack} asks Stata: for each function that the
code calls but does not define, it runs {cmd:mata which}, and collects the
library if it is not part of Stata. The answers are printed on screen
(built-in functions are skipped). Only libraries indexed in the current
session ({cmd:mata mlib index}) are found. When {cmd:dopack} is run
{cmd:quietly}, the answers cannot be read and a warning says so; option
{opt nomatalibs} skips this step.

{pstd}
When a command line starts with a macro that cannot be resolved, such as
{cmd:`=cond(...,"quietly","")' mycmd ...}, the word after the macro is also
looked up and collected if it is a user-written ado-file.

{pstd}
Ado-files are searched along the ado-path at the time {cmd:dopack} runs
(including folders added with {cmd:adopath}, also folders whose names
contain blanks) and, for an ado-file given as input, in its own folder.
A command whose ado-file is not on the ado-path when {cmd:dopack} runs
cannot be collected; it is listed as not found.

{pstd}
Command names that are neither built-in nor found as ado-files are listed
at the end, separately for the do-files and for the code inside the
collected ado-files; abbreviations of built-in commands (for example
{cmd:gen}) also appear there.


{title:Stored results}

{pstd}
{cmd:dopack} stores the following in {cmd:r()}:

{synoptset 16 tabbed}{...}
{p2col 5 16 20 2: Scalars}{p_end}
{synopt:{cmd:r(n_do)}}number of do-files{p_end}
{synopt:{cmd:r(n_ado)}}number of ado-files{p_end}
{synopt:{cmd:r(n_other)}}number of other files in the {cmd:ado} folder (help, dialog, class, Mata and other companion files){p_end}
{synopt:{cmd:r(n_script)}}number of other files used by the do-files and kept in the folder tree{p_end}
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
{synopt:{cmd:r(scriptfiles)}}files used by the do-files and kept in the folder tree, relative to the root{p_end}
{synopt:{cmd:r(notfound)}}commands in the do-files found neither as built-in nor as ado-file{p_end}
{synopt:{cmd:r(notfound_ado)}}the same for commands called inside the collected ado-files{p_end}


{title:Examples}

{phang2}{cmd:. dopack using "C:/projects/study/master.do", dryrun}{p_end}
{phang2}{cmd:. dopack using "C:/projects/study/master.do", to("C:/share/study_code") purpose("Main analyses of the study.")}{p_end}
{phang2}{cmd:. dopack using master.do, to(../package) replace startdir(C:/projects/study)}{p_end}
{phang2}{cmd:. dopack using "C:/ado/personal/mycmd.ado", to("C:/share/mycmd")}{p_end}
{phang2}{cmd:. dopack using mycmd.ado, to("C:/share/mycmd")}{space 2}(working directory first, then the ado-path){p_end}


{title:Requirements}

{pstd}
Stata 16 or later (frames are used).


{title:Installation}

{phang2}{cmd:. net install dopack, from("https://raw.githubusercontent.com/szabobarnaKI/dopack/main/") replace}{p_end}


{title:Author}

{pstd}
Barna Szabo, Karolinska Institutet (written with Claude).{break}
Source and issues: {browse "https://github.com/szabobarnaKI/dopack"}
{p_end}

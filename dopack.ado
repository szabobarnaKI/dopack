*! version 0.2.1  26nov2026
*! dopack: collect every user-written file needed to run a do-file or an ado-command
*! Static analysis (the code is never executed). Szabo B & Claude.
program define dopack, rclass
    version 16
    syntax using/ [, TO(string) REPLACE DRYrun PURpose(string) TItle(string) ///
        STARTdir(string) ROOT(string) MAXvisits(integer 5000) noMATAlibs]

    di as txt "dopack 0.2.1 (static analysis; the code is not run)"

    if `"`to'"' == "" & "`dryrun'" == "" {
        di as err "option to() is required unless dryrun is specified"
        exit 198
    }
    if `maxvisits' < 1 {
        di as err "maxvisits() must be positive"
        exit 198
    }

    * ---- locate the main file ------------------------------------------
    * as given (relative to the working directory); without an extension
    * name.do, then name.ado; an ado-file named without a path that is not
    * in the working directory is then searched along the ado-path
    local mainfile `"`using'"'
    local nopath = !strpos(`"`mainfile'"', "/") & !strpos(`"`mainfile'"', char(92)) & !strpos(`"`mainfile'"', ":")
    local hasext = ustrregexm(`"`mainfile'"', "[.][A-Za-z0-9]+" + char(36))
    local isado = (lower(substr(`"`mainfile'"', -4, .)) == ".ado")
    local where ""
    capture confirm file `"`mainfile'"'
    local rc = _rc
    if `rc' & !`hasext' {
        capture confirm file `"`mainfile'.do"'
        if !_rc {
            local mainfile `"`mainfile'.do"'
            local rc 0
        }
        else {
            local mainfile `"`mainfile'.ado"'
            local isado 1
            capture confirm file `"`mainfile'"'
            local rc = _rc
        }
    }
    if `rc' & `isado' & `nopath' {
        capture findfile `"`mainfile'"'
        if !_rc {
            local mainfile `"`r(fn)'"'
            local where "found along the ado-path"
            local rc 0
        }
    }
    if `rc' {
        di as err `"file `using' not found"'
        if `isado' & `nopath' di as err "(searched in the working directory and along the ado-path)"
        exit 601
    }
    if "`where'" != "" di as txt `"`using' `where': `mainfile'"'

    local realpwd `"`c(pwd)'"'

    * ---- run the analysis in an empty frame -----------------------------
    * expressions in macro definitions are evaluated with Stata; an empty
    * frame makes anything that refers to variables fail (-> unresolved)
    local curfr `"`c(frame)'"'
    tempname fr
    frame create `fr'
    frame change `fr'
    capture noisily mata: dp_main()
    local rc = _rc
    * Mata functions called by the code: find the libraries they come from.
    * mata which (a Mata command: mata: mata which f()) prints its answer only, so it is captured in a log; &f()
    * fails silently for built-in functions and functions that do not exist
    local dp_mlog ""
    local dp_mnok 0
    if !`rc' & "`matalibs'" == "" & `"`dp_mfns'"' != "" {
        tempfile mlog
        local nw : word count `dp_mfns'
        di as txt _n "Looking up the Mata functions called by the code (`nw' names; mata which):"
        capture log close __dpml
        capture noisily {
            quietly log using `"`mlog'"', text replace name(__dpml)
            foreach f of local dp_mfns {
                capture mata: __dpp = &`f'()
                if !_rc {
                    local ++dp_mnok
                    capture noisily mata: mata which `f'()
                }
            }
        }
        local rc = _rc
        capture log close __dpml
        capture mata: mata drop __dpp
        local dp_mlog `"`mlog'"'
    }
    if !`rc' {
        capture noisily mata: dp_main2()
        local rc = _rc
    }
    capture mata: rmexternal("__dp_S")
    frame change `curfr'
    capture frame drop `fr'
    if `rc' exit `rc'

    * ---- commands that were not found anywhere ---------------------------
    local nf ""
    foreach c of local dp_nf {
        capture quietly which `c'
        if _rc local nf `nf' `c'
    }
    if `"`nf'"' != "" {
        di as txt _n "Commands not found as built-in or ado-file"
        di as txt "(abbreviated built-in commands also appear here; check for missing packages):"
        di as res `"  `nf'"'
    }
    local nfado ""
    foreach c of local dp_nfado {
        capture quietly which `c'
        if _rc local nfado `nfado' `c'
    }
    if `"`nfado'"' != "" {
        di as txt _n "Commands called inside the collected ado-files but not found as built-in or ado-file"
        di as txt "(may also be abbreviated built-ins, or programs defined at run time; check for missing files):"
        di as res `"  `nfado'"'
    }

    return scalar n_do      = `dp_ndo'
    return scalar n_ado     = `dp_nado'
    return scalar n_other   = `dp_noth'
    return scalar n_cd      = `dp_ncd'
    return scalar n_unres   = `dp_nunres'
    return scalar n_warn    = `dp_nwarn'
    return scalar n_copied  = `dp_ncopied'
    return scalar n_script  = `dp_nscr'
    return local  notfound  `"`nf'"'
    return local  notfound_ado `"`nfado'"'
    return local  adofiles  `"`dp_ados'"'
    return local  otherfiles `"`dp_others'"'
    return local  scriptfiles `"`dp_scripts'"'
    return local  dofiles   `"`dp_dofiles'"'
    return local  startdir  `"`dp_startdir'"'
    return local  root      `"`dp_root'"'
    return local  target    `"`dp_target'"'
    return local  mainfile  `"`dp_main'"'
end


mata:

struct dp_st {
    real scalar win, pathsig, visits, maxvisits, abort, inprog, nunres
    string scalar cwd, sysstata, home, curraw, startdir, mainado, mainf, realpwd
    string rowvector apath, apath0
    transmorphic scalar sysdirs, globals, defined, dos, ados, oths, cache
    transmorphic scalar notfound, notfado, trkdone, trkmap, pkgfiles, pkgname
    transmorphic scalar mfn, mdef, done, mirs
    string colvector dolist, adolist, adopkg, othlist, othkind, stack
    string colvector mirlist, mirkind
    string colvector cdfile, cdline, cdraw, cddir, cdstat
    string colvector wfile, wline, wmsg, nfile, nline, nmsg
}

// ------------------------------------------------------------------ strings

string scalar dp_Q()
{
    return(char(34))
}

string scalar dp_B()
{
    return(char(96))
}

string scalar dp_A()
{
    return(char(39))
}

string scalar dp_M1()
{
    return(char(1))
}

string scalar dp_M2()
{
    return(char(2))
}

// position just after the marker that starts at position 1 of s (markers can nest)
real scalar dp_skipmark(string scalar s)
{
    real scalar i, d
    string scalar ch

    d = 0
    for (i=1; i<=strlen(s); i++) {
        ch = substr(s, i, 1)
        if (ch == dp_M1()) d++
        if (ch == dp_M2()) {
            d--
            if (d == 0) return(i + 1)
        }
    }
    return(strlen(s) + 1)
}

string scalar dp_show(string scalar s)
{
    return(subinstr(subinstr(s, dp_M1(), dp_B(), .), dp_M2(), dp_A(), .))
}

real scalar dp_abbr(string scalar w, string scalar full, real scalar minlen)
{
    if (strlen(w) < minlen | strlen(w) > strlen(full)) return(0)
    return(substr(full, 1, strlen(w)) == w)
}

string rowvector dp_split(string scalar s, string scalar sep)
{
    string rowvector r
    string scalar t
    real scalar pos

    r = J(1, 0, "")
    t = s
    pos = strpos(t, sep)
    while (pos > 0) {
        r = r, substr(t, 1, pos-1)
        t = substr(t, pos+strlen(sep), .)
        pos = strpos(t, sep)
    }
    r = r, t
    return(r)
}

string scalar dp_joinv(string rowvector v, string scalar sep)
{
    string scalar r
    real scalar i

    r = ""
    for (i=1; i<=cols(v); i++) {
        if (i > 1) r = r + sep
        r = r + v[i]
    }
    return(r)
}

// first token of s; quotes (simple and compound) bind; rest gets the remainder
string scalar dp_gettok(string scalar s0, string scalar rest, real scalar stopc)
{
    string scalar s, Q, B, A, ch, tok
    real scalar n, i, d, e, j

    Q = dp_Q(); B = dp_B(); A = dp_A()
    s = strltrim(s0)
    n = strlen(s)
    if (n == 0) {
        rest = ""
        return("")
    }
    e = n
    if (substr(s, 1, 2) == B + Q) {
        d = 0
        i = 1
        while (i <= n) {
            if (substr(s, i, 2) == B + Q) {
                d++
                i = i + 2
                continue
            }
            if (substr(s, i, 2) == Q + A) {
                d--
                i = i + 2
                if (d == 0) break
                continue
            }
            i++
        }
        e = min((i - 1, n))
    }
    else if (substr(s, 1, 1) == Q) {
        j = strpos(substr(s, 2, .), Q)
        if (j > 0) e = j + 1
    }
    else {
        for (i=1; i<=n; i++) {
            ch = substr(s, i, 1)
            if (ch == " " | (stopc & ch == ",")) {
                e = i - 1
                break
            }
        }
    }
    tok = substr(s, 1, e)
    rest = substr(s, e+1, .)
    return(tok)
}

string scalar dp_unq(string scalar s)
{
    string scalar t, Q, B, A
    real scalar n

    Q = dp_Q(); B = dp_B(); A = dp_A()
    t = strtrim(s)
    n = strlen(t)
    if (n >= 4) {
        if (substr(t, 1, 2) == B + Q & substr(t, n-1, 2) == Q + A) return(substr(t, 3, n-4))
    }
    if (n >= 2) {
        if (substr(t, 1, 1) == Q & substr(t, n, 1) == Q) return(substr(t, 2, n-2))
    }
    return(t)
}

string rowvector dp_toklist(string scalar s)
{
    string rowvector r
    string scalar rest, nxt, t

    r = J(1, 0, "")
    rest = s
    while (1) {
        t = dp_gettok(rest, nxt, 0)
        if (t == "") break
        r = r, dp_unq(t)
        rest = nxt
    }
    return(r)
}

// position of the first ch outside quotes, brackets and unresolved-macro markers (0 if none)
real scalar dp_topchar(string scalar s, string scalar ch)
{
    string scalar cc, c2, Q, B, A
    real scalar i, n, inq, cq, dep, mk

    Q = dp_Q(); B = dp_B(); A = dp_A()
    n = strlen(s)
    inq = 0; cq = 0; dep = 0; mk = 0
    for (i=1; i<=n; i++) {
        cc = substr(s, i, 1)
        c2 = substr(s, i, 2)
        if (cc == dp_M1()) {
            mk++
            continue
        }
        if (cc == dp_M2()) {
            if (mk > 0) mk--
            continue
        }
        if (mk > 0) continue
        if (inq) {
            if (cc == Q) inq = 0
            continue
        }
        if (cq > 0) {
            if (c2 == B + Q) cq++
            if (c2 == Q + A) cq--
            if (c2 == B + Q | c2 == Q + A) i++
            continue
        }
        if (c2 == B + Q) {
            cq = 1
            i++
            continue
        }
        if (cc == Q) {
            inq = 1
            continue
        }
        if (cc == "(" | cc == "[") dep++
        if (cc == ")" | cc == "]") dep--
        if (dep == 0 & cc == ch) return(i)
    }
    return(0)
}

// ------------------------------------------------------------------ paths

string scalar dp_norm(string scalar p0)
{
    string scalar p, pre, out, sg
    string rowvector segs, st
    real scalar i, k, popok

    p = strtrim(subinstr(p0, char(92), "/", .))
    if (p == "") return("")
    pre = ""
    if (substr(p, 1, 2) == "//") {
        pre = "//"
        p = substr(p, 3, .)
    }
    else if (substr(p, 1, 1) == "/") {
        pre = "/"
        p = substr(p, 2, .)
    }
    else if (ustrregexm(p, "^[A-Za-z]:")) {
        pre = substr(p, 1, 2) + "/"
        p = substr(p, 3, .)
    }
    segs = dp_split(p, "/")
    st = J(1, 0, "")
    for (i=1; i<=cols(segs); i++) {
        sg = segs[i]
        if (sg == "" | sg == ".") continue
        if (sg != "..") {
            st = st, sg
            continue
        }
        k = cols(st)
        popok = 0
        if (k > 0) popok = (st[k] != "..")
        if (popok & k == 1) st = J(1, 0, "")
        else if (popok) st = st[1..k-1]
        else if (pre == "") st = st, ".."
    }
    out = pre + dp_joinv(st, "/")
    if (out == "") out = "."
    return(out)
}

real scalar dp_isabs(string scalar p)
{
    string scalar q

    q = subinstr(strtrim(p), char(92), "/", .)
    if (substr(q, 1, 1) == "/" | substr(q, 1, 1) == "~") return(1)
    return(ustrregexm(q, "^[A-Za-z]:"))
}

string scalar dp_path(struct dp_st scalar S, string scalar base, string scalar p)
{
    string scalar q

    q = strtrim(p)
    if (substr(q, 1, 1) == "~") q = S.home + substr(q, 2, .)
    if (dp_isabs(q)) return(dp_norm(q))
    return(dp_norm(base + "/" + q))
}

string scalar dp_key(struct dp_st scalar S, string scalar p)
{
    if (S.win) return(strlower(p))
    return(p)
}

real scalar dp_under(struct dp_st scalar S, string scalar p, string scalar d)
{
    string scalar kp, kd

    kd = dp_key(S, d)
    if (kd == "" | kd == ".") return(0)
    if (substr(kd, strlen(kd), 1) != "/") kd = kd + "/"
    kp = dp_key(S, p) + "/"
    return(substr(kp, 1, strlen(kd)) == kd)
}

string scalar dp_dirname(string scalar p)
{
    string scalar d
    real scalar i

    for (i=strlen(p); i>=1; i--) {
        if (substr(p, i, 1) == "/") break
    }
    if (i < 1) return(".")
    if (i == 1) return("/")
    d = substr(p, 1, i-1)
    if (ustrregexm(d, "^[A-Za-z]:") & strlen(d) == 2) d = d + "/"
    return(d)
}

string scalar dp_basename(string scalar p)
{
    real scalar i

    for (i=strlen(p); i>=1; i--) {
        if (substr(p, i, 1) == "/") break
    }
    return(substr(p, i+1, .))
}

string scalar dp_ext(string scalar p)
{
    string scalar b
    real scalar i

    b = dp_basename(subinstr(p, char(92), "/", .))
    for (i=strlen(b); i>=1; i--) {
        if (substr(b, i, 1) == ".") break
    }
    if (i < 1) return("")
    return(strlower(substr(b, i+1, .)))
}

string scalar dp_noext(string scalar b)
{
    real scalar i

    for (i=strlen(b); i>=1; i--) {
        if (substr(b, i, 1) == ".") break
    }
    if (i < 1) return(b)
    return(substr(b, 1, i-1))
}

// split an absolute normalized path into prefix + segments
string rowvector dp_segs(string scalar p, string scalar pre)
{
    string scalar q

    q = p
    pre = ""
    if (substr(q, 1, 2) == "//") pre = "//"
    else if (substr(q, 1, 1) == "/") pre = "/"
    else if (ustrregexm(q, "^[A-Za-z]:/")) pre = substr(q, 1, 3)
    q = substr(q, strlen(pre)+1, .)
    if (q == "") return(J(1, 0, ""))
    return(dp_split(q, "/"))
}

string scalar dp_common(struct dp_st scalar S, string colvector ps)
{
    string rowvector a, b
    string scalar pa, pb
    real scalar i, k, m

    if (rows(ps) == 0) return("")
    a = dp_segs(ps[1], pa)
    k = cols(a)
    for (i=2; i<=rows(ps); i++) {
        b = dp_segs(ps[i], pb)
        if (dp_key(S, pa) != dp_key(S, pb)) return("")
        k = min((k, cols(b)))
        for (m=1; m<=k; m++) {
            if (dp_key(S, a[m]) != dp_key(S, b[m])) break
        }
        k = m - 1
    }
    if (k == 0) return(pa)
    return(pa + dp_joinv(a[1..k], "/"))
}

// relative path from directory 'from' to file/dir 'to' (both absolute)
string scalar dp_relpath(struct dp_st scalar S, string scalar from, string scalar to)
{
    string rowvector a, b, r
    string scalar pa, pb
    real scalar k, m

    a = dp_segs(from, pa)
    b = dp_segs(to, pb)
    if (dp_key(S, pa) != dp_key(S, pb)) return(to)
    k = min((cols(a), cols(b)))
    for (m=1; m<=k; m++) {
        if (dp_key(S, a[m]) != dp_key(S, b[m])) break
    }
    k = m - 1
    r = J(1, cols(a) - k, "..")
    if (cols(b) > k) r = r, b[k+1..cols(b)]
    if (cols(r) == 0) return(".")
    return(dp_joinv(r, "/"))
}

// path of p inside the package (relative to root), or under _external/
string scalar dp_relin(struct dp_st scalar S, string scalar p, string scalar root)
{
    string scalar r

    if (root != "" & dp_under(S, p, root)) {
        if (dp_key(S, p) == dp_key(S, root)) return("")
        if (substr(root, strlen(root), 1) == "/") return(substr(p, strlen(root)+1, .))
        return(substr(p, strlen(root)+2, .))
    }
    r = subinstr(subinstr(p, ":", "", .), "//", "/", .)
    while (substr(r, 1, 1) == "/") r = substr(r, 2, .)
    return("_external/" + r)
}

// ------------------------------------------------------------------ messages

void dp_warn(struct dp_st scalar S, string scalar file, real scalar ln, string scalar msg)
{
    real scalar i

    for (i=1; i<=rows(S.wmsg); i++) {
        if (S.wmsg[i] == msg & S.wfile[i] == file & S.wline[i] == strofreal(ln)) return
    }
    S.wfile = S.wfile \ file
    S.wline = S.wline \ strofreal(ln)
    S.wmsg = S.wmsg \ msg
}

void dp_note(struct dp_st scalar S, string scalar file, real scalar ln, string scalar msg)
{
    S.nfile = S.nfile \ file
    S.nline = S.nline \ strofreal(ln)
    S.nmsg = S.nmsg \ msg
}

// ------------------------------------------------------------------ macros

string scalar dp_globval(struct dp_st scalar S, string scalar nm, real scalar f)
{
    string scalar v

    f = 1
    if (asarray_contains(S.globals, nm)) return(asarray(S.globals, nm))
    v = st_global(nm)
    if (v != "") return(v)
    f = 0
    return("")
}

string scalar dp_cval(struct dp_st scalar S, string scalar cn)
{
    string scalar cw
    real scalar rc

    if (cn == "pwd") return(S.cwd)
    if (substr(cn, 1, 7) == "sysdir_") {
        cw = strupper(substr(cn, 8, .))
        if (asarray_contains(S.sysdirs, cw)) return(asarray(S.sysdirs, cw) + "/")
    }
    rc = _stata("local __dpv " + dp_B() + "c(" + cn + ")" + dp_A(), 1)
    if (rc) return("")
    return(st_local("__dpv"))
}

string scalar dp_eval(struct dp_st scalar S, string scalar expr, real scalar f)
{
    string scalar e, Q
    real scalar rc

    f = 0
    if (strpos(expr, dp_M1())) return("")
    Q = dp_Q()
    e = subinstr(expr, "c(pwd)", Q + S.cwd + Q, .)
    e = subinstr(e, "c(" + Q + "pwd" + Q + ")", Q + S.cwd + Q, .)
    rc = _stata("local __dpv = " + e, 1, 1)
    if (rc) return("")
    f = 1
    return(st_local("__dpv"))
}

string scalar dp_extfn(struct dp_st scalar S, string scalar r0, real scalar f)
{
    string scalar r, tok, rest, d, Q
    real scalar rc

    f = 0
    Q = dp_Q()
    r = strtrim(r0)
    if (strpos(r, dp_M1())) return("")
    if (ustrregexm(r, "^dir\s")) {
        tok = dp_gettok(substr(r, 4, .), rest, 0)
        d = dp_path(S, S.cwd, dp_unq(tok))
        r = "dir " + Q + d + Q + " " + strtrim(rest)
    }
    rc = _stata("local __dpv : " + r, 1, 1)
    if (rc) return("")
    f = 1
    return(st_local("__dpv"))
}

string scalar dp_macval(struct dp_st scalar S, string scalar nm, transmorphic scalar L, real scalar f)
{
    string scalar cn, base

    f = 1
    if (asarray_contains(L, nm)) return(asarray(L, nm))
    if (substr(nm, 1, 1) == "=") return(dp_eval(S, substr(nm, 2, .), f))
    if (substr(nm, 1, 1) == ":") return(dp_extfn(S, substr(nm, 2, .), f))
    if (ustrregexm(nm, "^c\(([A-Za-z_0-9]+)\)")) {
        cn = ustrregexs(1)
        if (strlen(nm) == strlen(cn) + 3) return(dp_cval(S, cn))
    }
    base = subinstr(subinstr(nm, "+", "", .), "-", "", .)
    if (base != nm & asarray_contains(L, base)) return(asarray(L, base))
    f = 0
    return("")
}

// expand local and global macros; unresolved ones are kept between markers
string scalar dp_expand(struct dp_st scalar S, string scalar s0, transmorphic scalar L)
{
    string scalar s, cc, nm, v, Q, B, A, D, M1, M2
    real rowvector stk
    real scalar i, o, f, j, e

    Q = dp_Q(); B = dp_B(); A = dp_A(); D = char(36)
    M1 = dp_M1(); M2 = dp_M2()
    s = s0
    // stk: positions of open macro references (>0) and open compound quotes (<0)
    stk = J(1, 0, .)
    i = 1
    while (i <= strlen(s)) {
        cc = substr(s, i, 1)
        if (cc == B) {
            if (substr(s, i+1, 1) == Q) {
                stk = stk, -i
                i = i + 2
            }
            else {
                stk = stk, i
                i++
            }
            continue
        }
        if (cc != A | cols(stk) == 0) {
            i++
            continue
        }
        o = stk[cols(stk)]
        if (o < 0) {
            // apostrophe inside a compound-quoted string: closes it only after a double quote
            if (i > 1) {
                if (substr(s, i-1, 1) == Q) {
                    if (cols(stk) > 1) stk = stk[1..cols(stk)-1]
                    else stk = J(1, 0, .)
                }
            }
            i++
            continue
        }
        if (cols(stk) > 1) stk = stk[1..cols(stk)-1]
        else stk = J(1, 0, .)
        nm = substr(s, o+1, i-o-1)
        v = dp_macval(S, nm, L, f)
        if (!f) v = M1 + nm + M2
        s = substr(s, 1, o-1) + v + substr(s, i+1, .)
        i = o + strlen(v)
    }
    // globals
    i = 1
    while (i <= strlen(s)) {
        if (substr(s, i, 1) != D) {
            i++
            continue
        }
        nm = ""
        e = i
        if (substr(s, i+1, 1) == "{") {
            j = strpos(substr(s, i+2, .), "}")
            if (j > 0) {
                nm = substr(s, i+2, j-1)
                e = i + 1 + j
            }
        }
        else if (ustrregexm(substr(s, i+1, .), "^[A-Za-z_][A-Za-z0-9_]*")) {
            nm = ustrregexs(0)
            e = i + strlen(nm)
        }
        if (nm == "") {
            i++
            continue
        }
        v = dp_globval(S, nm, f)
        if (!f) v = M1 + D + nm + M2
        s = substr(s, 1, i-1) + v + substr(s, e+1, .)
        i = i + strlen(v)
    }
    return(s)
}

// ------------------------------------------------------------------ preprocessing

real scalar dp_endscont(string scalar s)
{
    string scalar t
    real scalar n

    t = strrtrim(s)
    n = strlen(t)
    if (n < 3) return(0)
    if (substr(t, n-2, 3) != "///") return(0)
    if (n == 3) return(1)
    return(substr(t, n-3, 1) == " ")
}

void dp_emit(string colvector cmds, real colvector lnos, string scalar buf, real scalar bl)
{
    string scalar t

    t = strtrim(buf)
    if (t != "") {
        cmds = cmds \ t
        lnos = lnos \ bl
    }
}

// split raw lines into commands: comments removed, /// joined, #delimit handled
void dp_prep(string colvector raw, string colvector cmds, real colvector lnos)
{
    real scalar mode, bc, inq, cq, cont, starc, li, i, n, bl, skipnext, isline
    string scalar s, buf, ch, c2, t, Q, B, A, CB, CE

    Q = dp_Q(); B = dp_B(); A = dp_A()
    CB = "/" + "*"
    CE = "*" + "/"
    cmds = J(0, 1, "")
    lnos = J(0, 1, .)
    mode = 0; bc = 0; inq = 0; cq = 0; cont = 0; starc = 0
    buf = ""; bl = 1; skipnext = 0
    for (li=1; li<=rows(raw); li++) {
        s = raw[li]
        n = strlen(s)
        if (skipnext) {
            skipnext = dp_endscont(s)
            continue
        }
        if (bc == 0 & inq == 0 & cq == 0 & strtrim(buf) == "" & !cont & !starc) {
            t = strtrim(s)
            if (ustrregexm(t, "^#d[a-z]*\s+(;|cr)")) {
                mode = (ustrregexs(1) == ";")
                buf = ""
                continue
            }
            if (mode == 0 & substr(t, 1, 1) == "*") {
                skipnext = dp_endscont(s)
                continue
            }
        }
        i = 1
        while (i <= n) {
            ch = substr(s, i, 1)
            c2 = substr(s, i, 2)
            if (bc > 0) {
                if (c2 == CE) bc--
                if (c2 == CB) bc++
                if (c2 == CE | c2 == CB) i = i + 2
                else i++
                continue
            }
            if (starc) {
                if (ch == ";") {
                    starc = 0
                    buf = ""
                }
                i++
                continue
            }
            if (inq) {
                buf = buf + ch
                if (ch == Q) inq = 0
                i++
                continue
            }
            if (cq > 0) {
                if (c2 == B + Q) cq++
                if (c2 == Q + A) cq--
                if (c2 == B + Q | c2 == Q + A) {
                    buf = buf + c2
                    i = i + 2
                }
                else {
                    buf = buf + ch
                    i++
                }
                continue
            }
            if (strtrim(buf) == "" & ch != " ") {
                bl = li
                if (mode == 1 & ch == "*") {
                    starc = 1
                    i++
                    continue
                }
            }
            if (c2 == B + Q) {
                cq = 1
                buf = buf + c2
                i = i + 2
                continue
            }
            if (ch == Q) {
                inq = 1
                buf = buf + ch
                i++
                continue
            }
            if (c2 == CB) {
                bc = 1
                i = i + 2
                continue
            }
            isline = 0
            if (c2 == "//") {
                if (i == 1) isline = 1
                else isline = (substr(s, i-1, 1) == " ")
            }
            if (isline) {
                cont = (substr(s, i, 3) == "///")
                break
            }
            if (mode == 1 & ch == ";") {
                dp_emit(cmds, lnos, buf, bl)
                buf = ""
                i++
                continue
            }
            buf = buf + ch
            i++
        }
        // end of physical line
        if (mode == 1) {
            cont = 0
            buf = buf + " "
            continue
        }
        if (cont | bc > 0) {
            cont = 0
            buf = buf + " "
            continue
        }
        inq = 0
        cq = 0
        dp_emit(cmds, lnos, buf, bl)
        buf = ""
    }
    dp_emit(cmds, lnos, buf, bl)
}

// ------------------------------------------------------------------ file lists

void dp_adddo(struct dp_st scalar S, string scalar p)
{
    string scalar k

    k = dp_key(S, p)
    if (asarray_contains(S.dos, k)) return
    asarray(S.dos, k, 1)
    S.dolist = S.dolist \ p
}

string scalar dp_kind(string scalar ext)
{
    if (ext == "sthlp" | ext == "hlp") return("help file")
    if (ext == "ihlp") return("help include file")
    if (ext == "dlg") return("dialog file")
    if (ext == "idlg") return("dialog include file")
    if (ext == "mata") return("Mata source")
    if (ext == "mo") return("Mata object")
    if (ext == "mlib") return("Mata library")
    if (ext == "class") return("class file")
    if (ext == "scheme") return("graph scheme")
    if (ext == "style") return("graph style")
    if (ext == "do") return("do-file used by an ado-file")
    if (ext == "plugin") return("plugin")
    if (ext == "jar") return("Java archive")
    if (ext == "py") return("Python module")
    if (ext == "stbcal") return("business calendar")
    if (ext == "grec") return("graph recording")
    return("companion file")
}

void dp_addother(struct dp_st scalar S, string scalar p, string scalar kind)
{
    string scalar k

    if (dp_ext(p) == "ado") {
        dp_addado(S, p, dp_noext(dp_basename(p)))
        return
    }
    k = dp_key(S, p)
    if (asarray_contains(S.oths, k)) return
    asarray(S.oths, k, 1)
    S.othlist = S.othlist \ p
    S.othkind = S.othkind \ kind
    dp_companion(S, p)
}

string rowvector dp_adodirs(struct dp_st scalar S)
{
    string rowvector r
    string scalar e, u, d
    real scalar i

    r = J(1, 0, "")
    for (i=1; i<=cols(S.apath); i++) {
        e = dp_unq(strtrim(S.apath[i]))
        if (e == "") continue
        u = strupper(e)
        if (asarray_contains(S.sysdirs, u)) d = asarray(S.sysdirs, u)
        else if (e == ".") d = S.cwd
        else d = dp_path(S, S.cwd, e)
        r = r, dp_norm(d)
    }
    return(r)
}

// search fn in dirs (and their letter subfolders); "" if not found
string scalar dp_findin(struct dp_st scalar S, string scalar fn, string rowvector dirs)
{
    string scalar lt, p
    real scalar i

    lt = strlower(substr(fn, 1, 1))
    for (i=1; i<=cols(dirs); i++) {
        p = dirs[i] + "/" + fn
        if (fileexists(p)) return(dp_norm(p))
        p = dirs[i] + "/" + lt + "/" + fn
        if (fileexists(p)) return(dp_norm(p))
    }
    return("")
}

string scalar dp_findany(struct dp_st scalar S, string scalar fn)
{
    return(dp_findin(S, fn, dp_adodirs(S)))
}

// ------------------------------------------------------------------ companion files

// user-written file fn: in folder d0 (if given), else along the ado-path; "" if absent or official
string scalar dp_finduser(struct dp_st scalar S, string scalar fn, string scalar d0)
{
    string scalar f

    if (d0 != "") {
        if (fileexists(d0 + "/" + fn)) return(dp_norm(d0 + "/" + fn))
    }
    f = dp_findany(S, fn)
    if (f == "") return("")
    if (dp_under(S, f, S.sysstata)) return("")
    return(f)
}

// group g of every match of re in s
string rowvector dp_allmatch(string scalar s0, string scalar re, real scalar g)
{
    string rowvector r
    string scalar s, m
    real scalar p

    r = J(1, 0, "")
    s = s0
    while (ustrregexm(s, re)) {
        m = ustrregexs(0)
        r = r, ustrregexs(g)
        p = strpos(s, m)
        if (p == 0 | m == "") break
        s = substr(s, p + strlen(m), .)
    }
    return(r)
}

string colvector dp_readlines(string scalar path)
{
    string colvector raw

    raw = cat(path)
    if (rows(raw) == 0) return(raw)
    raw = subinstr(raw, char(13), "", .)
    raw = subinstr(raw, char(9), " ", .)
    if (substr(raw[1], 1, 3) == char(239) + char(187) + char(191)) raw[1] = substr(raw[1], 4, .)
    return(raw)
}

// once per key: returns 1 the first time
real scalar dp_first(struct dp_st scalar S, string scalar key)
{
    if (asarray_contains(S.done, key)) return(0)
    asarray(S.done, key, 1)
    return(1)
}

// files needed by the files that were just collected
void dp_companion(struct dp_st scalar S, string scalar p)
{
    string scalar e
    transmorphic scalar L2

    e = dp_ext(p)
    if (e == "dlg" | e == "idlg") dp_scandlg(S, p)
    else if (e == "sthlp" | e == "hlp" | e == "ihlp") dp_scanhelp(S, p)
    else if (e == "scheme") dp_scanscheme(S, p)
    else if (e == "mata") dp_matalines(S, dp_readlines(p), p)
    else if (e == "py") dp_pylines(S, dp_readlines(p), p)
    else if (e == "class") {
        L2 = asarray_create()
        dp_parsefile(S, p, 1, L2)
    }
}

// a file used by a do-file (mode 0) that was found relative to the working
// directory keeps its place in the folder tree; anything else goes to ado/
void dp_addfile(struct dp_st scalar S, string scalar p, string scalar kind, real scalar mode, real scalar viapath)
{
    string scalar k

    if (mode == 1 | viapath | dp_under(S, p, S.sysstata)) {
        if (!dp_under(S, p, S.sysstata)) dp_addother(S, p, kind)
        return
    }
    k = dp_key(S, p)
    if (asarray_contains(S.mirs, k) | asarray_contains(S.dos, k)) return
    asarray(S.mirs, k, 1)
    S.mirlist = S.mirlist \ p
    S.mirkind = S.mirkind \ kind
    dp_companion(S, p)
}

// a file named in the code: relative to the working directory, else (no folder
// given) along the ado-path; returns 1 if found
real scalar dp_usefile(struct dp_st scalar S, string scalar p0, string scalar kind, real scalar ln, string scalar file, real scalar mode, string scalar what)
{
    string scalar p, full, f2

    p = dp_unq(p0)
    if (p == "") return(0)
    if (strpos(p, dp_M1())) {
        if (mode == 0) {
            dp_warn(S, file, ln, what + " could not be resolved statically: " + dp_show(p))
            S.nunres = S.nunres + 1
        }
        return(0)
    }
    full = dp_path(S, S.cwd, p)
    if (fileexists(full)) {
        dp_addfile(S, full, kind, mode, 0)
        return(1)
    }
    if (!strpos(subinstr(p, char(92), "/", .), "/")) {
        f2 = dp_findany(S, p)
        if (f2 != "") {
            dp_addfile(S, f2, kind, mode, 1)
            return(1)
        }
    }
    if (mode == 0) dp_warn(S, file, ln, what + " not found: " + full)
    return(0)
}

// dialog files: INCLUDE name (name.idlg), create CHILD name, view dialog name,
// and the command a dialog runs (put "cmd ...")
void dp_scandlg(struct dp_st scalar S, string scalar p)
{
    string colvector raw
    string scalar t, d, re
    transmorphic scalar L2
    real scalar i

    raw = dp_readlines(p)
    d = dp_dirname(p)
    L2 = asarray_create()
    re = "^put\s+" + dp_Q() + "\s*([A-Za-z_][A-Za-z0-9_]*)[ " + dp_Q() + "]"
    for (i=1; i<=rows(raw); i++) {
        t = strtrim(raw[i])
        if (substr(t, 1, 2) == "//" | substr(t, 1, 1) == "*") continue
        if (ustrregexm(t, "^INCLUDE\s+([A-Za-z_][A-Za-z0-9_]*)")) dp_dlgfile(S, ustrregexs(1) + ".idlg", d)
        if (ustrregexm(t, "create\s+CHILD\s+([A-Za-z_][A-Za-z0-9_]*)")) dp_dlgfile(S, ustrregexs(1) + ".dlg", d)
        if (ustrregexm(t, "view\s+dialog\s+([A-Za-z_][A-Za-z0-9_]*)")) dp_dlgfile(S, ustrregexs(1) + ".dlg", d)
        if (ustrregexm(t, re)) dp_command(S, ustrregexs(1), i, p, L2, 2)
    }
}

void dp_dlgfile(struct dp_st scalar S, string scalar fn, string scalar d)
{
    string scalar f

    f = dp_finduser(S, fn, d)
    if (f != "") dp_addother(S, f, dp_kind(dp_ext(f)))
}

// help files: INCLUDE help name (name.ihlp); links to help files and dialogs of
// the same command family (name starts with the name of this help file)
void dp_scanhelp(struct dp_st scalar S, string scalar p)
{
    string colvector raw
    string rowvector nms
    string scalar t, d, b, f, nm
    real scalar i, j

    raw = dp_readlines(p)
    d = dp_dirname(p)
    b = strlower(dp_noext(dp_basename(p)))
    for (i=1; i<=rows(raw); i++) {
        t = strtrim(raw[i])
        if (ustrregexm(t, "^INCLUDE\s+help\s+([A-Za-z_][A-Za-z0-9_]*)")) {
            f = dp_finduser(S, ustrregexs(1) + ".ihlp", d)
            if (f != "") dp_addother(S, f, "help include file")
        }
        if (!strpos(t, "{")) continue
        nms = dp_allmatch(t, "[{](help|helpb|view|dialog)\s+([A-Za-z_][A-Za-z0-9_]*)", 0)
        for (j=1; j<=cols(nms); j++) {
            if (!ustrregexm(nms[j], "^[{](help|helpb|view|dialog)\s+([A-Za-z_][A-Za-z0-9_]*)")) continue
            nm = ustrregexs(2)
            if (strlower(nm) == b | substr(strlower(nm), 1, strlen(b)) != b) continue
            if (ustrregexs(1) == "dialog") {
                if (fileexists(d + "/" + nm + ".dlg")) dp_addother(S, dp_norm(d + "/" + nm + ".dlg"), "dialog file")
                continue
            }
            if (fileexists(d + "/" + nm + ".sthlp")) dp_addother(S, dp_norm(d + "/" + nm + ".sthlp"), "help file")
            else if (fileexists(d + "/" + nm + ".hlp")) dp_addother(S, dp_norm(d + "/" + nm + ".hlp"), "help file")
        }
    }
}

// graph schemes: #include name (scheme-name.scheme)
void dp_scanscheme(struct dp_st scalar S, string scalar p)
{
    string colvector raw
    real scalar i

    raw = dp_readlines(p)
    for (i=1; i<=rows(raw); i++) {
        if (ustrregexm(strtrim(raw[i]), "^#include\s+([A-Za-z0-9_-]+)")) dp_scheme(S, ustrregexs(1))
    }
}

// class name used in the code (.name.new, member declarations, inherit())
void dp_classref(struct dp_st scalar S, string scalar nm)
{
    string scalar f

    if (nm == "Super" | nm == "Global" | nm == "Local" | nm == "double" | nm == "string" | nm == "array") return
    if (!ustrregexm(nm, "^[A-Za-z_][A-Za-z0-9_]*" + char(36))) return
    if (!dp_first(S, "class:" + nm + "|" + strofreal(S.pathsig) + "|" + S.cwd)) return
    f = dp_finduser(S, nm + ".class", "")
    if (f != "") dp_addother(S, f, "class file")
}

// class definition block: class name { declarations }, inherit(names)
void dp_classdecl(struct dp_st scalar S, string colvector cmds, real scalar i, real scalar j, real scalar i1)
{
    string rowvector tk
    string scalar t, ty
    real scalar k, m

    for (k=i+1; k<=min((j-1, rows(cmds))); k++) {
        tk = tokens(subinstr(strtrim(cmds[k]), "=", " = ", .))
        if (cols(tk) < 2) continue
        ty = tk[1]
        if (strpos(ty, ":")) continue
        if (ty == "class" & cols(tk) >= 3) ty = tk[2]
        dp_classref(S, ty)
    }
    if (j > i1 | j > rows(cmds)) return
    t = cmds[j]
    if (ustrregexm(t, "inherit\(([^)]*)\)")) {
        tk = tokens(ustrregexs(1))
        for (m=1; m<=cols(tk); m++) dp_classref(S, tk[m])
    }
}

// Mata code: remember the functions called and the functions/structures defined
void dp_matalines(struct dp_st scalar S, string colvector lines, string scalar file)
{
    string scalar s, c, c2, t, Q, B, A, CB, CE, ln, nm, KW, DEF
    string rowvector nms
    real scalar i, k, n, bc, inq, p, j, isdef

    Q = dp_Q(); B = dp_B(); A = dp_A()
    CB = "/" + "*"
    CE = "*" + "/"
    KW = " if else for while do return switch case goto pointer real string numeric transmorphic matrix scalar vector rowvector colvector complex void struct class function mata end break continue version external local static final public private protected virtual pragma extends "
    DEF = "^((static|final|public|private|protected|virtual|external)\s+)*(real|string|numeric|transmorphic|pointer|struct|class|void|complex|function)\b"
    bc = 0
    for (i=1; i<=rows(lines); i++) {
        s = lines[i]
        n = strlen(s)
        t = ""
        inq = 0
        k = 1
        while (k <= n) {
            c = substr(s, k, 1)
            c2 = substr(s, k, 2)
            if (bc) {
                if (c2 == CE) {
                    bc = 0
                    k = k + 2
                }
                else k++
                continue
            }
            if (inq) {
                if (c == Q) inq = 0
                k++
                continue
            }
            if (c2 == CB) {
                bc = 1
                k = k + 2
                continue
            }
            if (c2 == "//") break
            if (c2 == B + Q) {
                p = strpos(substr(s, k+2, .), Q + A)
                if (p == 0) break
                t = t + " "
                k = k + p + 3
                continue
            }
            if (c == Q) {
                inq = 1
                t = t + " "
                k++
                continue
            }
            t = t + c
            k++
        }
        ln = strtrim(t)
        if (ln == "") continue
        if (ustrregexm(ln, "^(struct|class)\s+([A-Za-z_][A-Za-z0-9_]*)\s*([{]|extends)")) asarray(S.mdef, ustrregexs(2), 1)
        isdef = ustrregexm(ln, DEF)
        nms = dp_allmatch(ln, "(^|[^A-Za-z0-9_.>])([A-Za-z_][A-Za-z0-9_]*)\s*\(", 2)
        for (j=1; j<=cols(nms); j++) {
            nm = nms[j]
            if (strpos(KW, " " + nm + " ")) continue
            if (isdef) {
                asarray(S.mdef, nm, 1)
                isdef = 0
                continue
            }
            if (!asarray_contains(S.mfn, nm)) asarray(S.mfn, nm, file)
        }
    }
}

// Python code: modules imported (import a, b / from a import x)
void dp_pylines(struct dp_st scalar S, string colvector lines, string scalar file)
{
    string rowvector parts
    string scalar t, m
    real scalar i, j

    for (i=1; i<=rows(lines); i++) {
        t = strtrim(lines[i])
        if (ustrregexm(t, "^import\s+(.+)")) {
            parts = dp_split(ustrregexs(1), ",")
            for (j=1; j<=cols(parts); j++) {
                if (ustrregexm(strtrim(parts[j]), "^([A-Za-z_][A-Za-z0-9_]*)")) dp_pymod(S, ustrregexs(1))
            }
        }
        else if (ustrregexm(t, "^from\s+([A-Za-z_][A-Za-z0-9_]*)[ .]")) dp_pymod(S, ustrregexs(1))
    }
}

void dp_pymod(struct dp_st scalar S, string scalar m)
{
    string scalar f

    if (!dp_first(S, "py:" + m + "|" + strofreal(S.pathsig) + "|" + S.cwd)) return
    f = dp_finduser(S, m + ".py", "")
    if (f != "") dp_addother(S, f, "Python module")
}

// business calendar name (%tbname, bcal load name): working directory, then ado-path
void dp_bcal(struct dp_st scalar S, string scalar nm, real scalar mode)
{
    string scalar f

    if (!dp_first(S, "bcal:" + nm + "|" + strofreal(S.pathsig) + "|" + S.cwd)) return
    f = dp_norm(S.cwd + "/" + nm + ".stbcal")
    if (fileexists(f)) {
        dp_addfile(S, f, "business calendar", mode, 0)
        return
    }
    f = dp_finduser(S, nm + ".stbcal", "")
    if (f != "") dp_addother(S, f, "business calendar")
}

// graph recording (play(name), graph play name): working directory, then each
// folder of the ado-path and its grec subfolder
void dp_grec(struct dp_st scalar S, string scalar nm, real scalar mode)
{
    string rowvector dirs
    string scalar f, fn
    real scalar i

    if (!dp_first(S, "grec:" + nm + "|" + strofreal(S.pathsig) + "|" + S.cwd)) return
    fn = nm + ".grec"
    f = dp_norm(S.cwd + "/" + fn)
    if (fileexists(f)) {
        dp_addfile(S, f, "graph recording", mode, 0)
        return
    }
    f = dp_finduser(S, fn, "")
    if (f == "") {
        dirs = dp_adodirs(S)
        for (i=1; i<=cols(dirs); i++) {
            if (!fileexists(dirs[i] + "/grec/" + fn)) continue
            f = dp_norm(dirs[i] + "/grec/" + fn)
            break
        }
    }
    if (f != "") {
        if (!dp_under(S, f, S.sysstata)) dp_addother(S, f, "graph recording")
    }
}

// .classname.new anywhere in a command
void dp_classscan(struct dp_st scalar S, string scalar s)
{
    string rowvector nms
    real scalar j

    if (!strpos(s, ".new")) return
    nms = dp_allmatch(s, "(^|[^A-Za-z0-9_.])[.]([A-Za-z_][A-Za-z0-9_]*)[.]new\b", 2)
    for (j=1; j<=cols(nms); j++) dp_classref(S, nms[j])
}

// a library or object file of Mata functions, with its package
void dp_addlib(struct dp_st scalar S, string scalar f, string scalar kind)
{
    string scalar pk

    dp_addother(S, f, kind)
    pk = dp_pkg(S, f)
}

// Mata functions called but not defined in the collected code: name.mo files now,
// the rest is looked up with mata which by the ado (see dp_main2)
void dp_matafinal(struct dp_st scalar S)
{
    string colvector k
    string scalar l, f
    real scalar i

    k = asarray_keys(S.mfn)
    if (rows(k) > 1) k = sort(k, 1)
    l = ""
    for (i=1; i<=rows(k); i++) {
        if (asarray_contains(S.mdef, k[i])) continue
        f = dp_finduser(S, k[i] + ".mo", "")
        if (f != "") {
            dp_addlib(S, f, "Mata object")
            continue
        }
        l = l + " " + k[i]
    }
    st_local("dp_mfns", strtrim(l))
}

// one answer of mata which: "  name():  source"
void dp_matasrc(struct dp_st scalar S, string scalar nm, string scalar src)
{
    string scalar tok, rest, f, lib

    tok = dp_unq(dp_gettok(src, rest, 0))
    if (tok == "") return
    if (dp_ext(tok) == "mo") {
        if (dp_isabs(tok)) f = dp_norm(tok)
        else f = dp_finduser(S, dp_basename(subinstr(tok, char(92), "/", .)), "")
        if (f == "") return
        if (fileexists(f) & !dp_under(S, f, S.sysstata)) dp_addlib(S, f, "Mata object")
        return
    }
    lib = dp_basename(subinstr(tok, char(92), "/", .))
    if (dp_ext(lib) == "mlib") lib = dp_noext(lib)
    if (!ustrregexm(lib, "^l[A-Za-z0-9_]+" + char(36))) return
    f = dp_findany(S, lib + ".mlib")
    if (f == "") {
        dp_warn(S, "", 0, "Mata function " + nm + "() comes from library " + lib + ", which was not found along the ado-path")
        return
    }
    if (dp_under(S, f, S.sysstata)) return
    dp_addlib(S, f, "Mata library")
}

// ------------------------------------------------------------------ packages

void dp_trk(struct dp_st scalar S, string scalar d)
{
    string colvector lines, files
    string scalar t, c1, r, f, nm, pid
    real scalar i, j, idx

    asarray(S.trkdone, dp_key(S, d), 1)
    lines = cat(d + "/stata.trk")
    files = J(0, 1, "")
    nm = ""
    idx = 0
    for (i=1; i<=rows(lines); i++) {
        t = strtrim(subinstr(lines[i], char(13), "", .))
        c1 = substr(t, 1, 2)
        if (c1 == "N ") nm = strtrim(substr(t, 3, .))
        if (c1 == "f " | c1 == "F ") {
            r = strtrim(substr(t, 3, .))
            if (dp_isabs(r)) f = dp_norm(r)
            else f = dp_norm(d + "/" + r)
            files = files \ f
        }
        if (t != "e") continue
        idx++
        pid = d + "|" + strofreal(idx)
        asarray(S.pkgfiles, pid, files)
        asarray(S.pkgname, pid, subinstr(nm, ".pkg", "", .))
        for (j=1; j<=rows(files); j++) asarray(S.trkmap, dp_key(S, files[j]), pid)
        files = J(0, 1, "")
        nm = ""
    }
}

// add every file of the installed package that p belongs to; returns package name
string scalar dp_pkg(struct dp_st scalar S, string scalar p)
{
    string scalar d, pid
    string colvector files
    string rowvector cands
    real scalar i, j

    d = dp_dirname(p)
    cands = (d, dp_dirname(d))
    for (i=1; i<=2; i++) {
        if (!fileexists(cands[i] + "/stata.trk")) continue
        if (!asarray_contains(S.trkdone, dp_key(S, cands[i]))) dp_trk(S, cands[i])
        if (!asarray_contains(S.trkmap, dp_key(S, p))) continue
        pid = asarray(S.trkmap, dp_key(S, p))
        files = asarray(S.pkgfiles, pid)
        for (j=1; j<=rows(files); j++) {
            if (fileexists(files[j])) dp_addother(S, files[j], dp_kind(dp_ext(files[j])))
        }
        return(asarray(S.pkgname, pid))
    }
    return("")
}

// ------------------------------------------------------------------ ado-files

void dp_addado(struct dp_st scalar S, string scalar p, string scalar nm)
{
    string scalar k, d, q, pk
    string rowvector exts
    transmorphic scalar L2
    real scalar i, idx, hashelp, hasdlg

    k = dp_key(S, p)
    if (asarray_contains(S.ados, k)) return
    asarray(S.ados, k, 1)
    S.adolist = S.adolist \ p
    S.adopkg = S.adopkg \ ""
    idx = rows(S.adolist)
    d = dp_dirname(p)
    exts = ("sthlp", "hlp", "ihlp", "dlg", "idlg", "mata", "class", "mo", "plugin")
    hashelp = 0
    hasdlg = 0
    for (i=1; i<=cols(exts); i++) {
        q = d + "/" + nm + "." + exts[i]
        if (!fileexists(q)) continue
        dp_addother(S, dp_norm(q), dp_kind(exts[i]))
        if (i <= 2) hashelp = 1
        if (i == 4) hasdlg = 1
    }
    // the dialog of the command (db name) may sit in another folder of the ado-path
    if (!hasdlg) {
        q = dp_finduser(S, nm + ".dlg", "")
        if (q != "") dp_addother(S, q, "dialog file")
    }
    q = d + "/l" + nm + ".mlib"
    if (fileexists(q)) dp_addother(S, dp_norm(q), "Mata library")
    if (!hashelp) {
        q = dp_findany(S, nm + ".sthlp")
        if (q == "") q = dp_findany(S, nm + ".hlp")
        if (q != "" & !dp_under(S, q, S.sysstata)) dp_addother(S, q, "help file")
    }
    pk = dp_pkg(S, p)
    S.adopkg[idx] = pk
    L2 = asarray_create()
    asarray(L2, "prog:" + nm, 1)
    dp_parsefile(S, p, 1, L2)
}

string scalar dp_findado(struct dp_st scalar S, string scalar w)
{
    string scalar p

    p = dp_findany(S, w + ".ado")
    if (p == "") return("")
    if (dp_under(S, p, S.sysstata)) return("SYS")
    return(p)
}

void dp_command(struct dp_st scalar S, string scalar w, real scalar ln, string scalar file, transmorphic scalar L, real scalar mode)
{
    string scalar key, p

    if (strlen(w) > 32) return
    if (asarray_contains(L, "prog:" + w)) return
    if (asarray_contains(S.defined, w)) return
    key = w + "|" + strofreal(S.pathsig) + "|" + S.cwd
    if (asarray_contains(S.cache, key)) p = asarray(S.cache, key)
    else {
        p = dp_findado(S, w)
        asarray(S.cache, key, p)
    }
    if (p == "SYS") return
    if (p == "") {
        if (mode == 0 & !asarray_contains(S.notfound, w)) asarray(S.notfound, w, file + ":" + strofreal(ln))
        if (mode == 1 & !asarray_contains(S.notfado, w)) asarray(S.notfado, w, file + ":" + strofreal(ln))
        return
    }
    dp_addado(S, p, w)
}

// ------------------------------------------------------------------ commands

void dp_cdrec(struct dp_st scalar S, string scalar file, real scalar ln, string scalar d, string scalar st)
{
    S.cdfile = S.cdfile \ file
    S.cdline = S.cdline \ strofreal(ln)
    S.cdraw = S.cdraw \ S.curraw
    S.cddir = S.cddir \ d
    S.cdstat = S.cdstat \ st
}

// is the path written after the command word in the unexpanded code absolute?
real scalar dp_rawabs(struct dp_st scalar S, string scalar re)
{
    string scalar rest, tok

    if (!ustrregexm(S.curraw, re)) return(0)
    tok = dp_gettok(ustrregexs(3), rest, 0)
    return(dp_isabs(dp_unq(tok)))
}

void dp_cd(struct dp_st scalar S, string scalar a, real scalar ln, string scalar file, real scalar mode)
{
    string scalar p, nd, st

    if (mode == 1) return
    p = dp_unq(a)
    if (p == "") return
    if (strpos(p, dp_M1())) {
        dp_cdrec(S, file, ln, "", "unresolved")
        dp_warn(S, file, ln, "cd target could not be resolved statically: " + dp_show(p) + "; later relative paths may be wrong")
        S.nunres = S.nunres + 1
        return
    }
    nd = dp_path(S, S.cwd, p)
    if (S.inprog) {
        dp_cdrec(S, file, ln, nd, "inside a program definition; not followed")
        return
    }
    if (dp_rawabs(S, "(^|[\s:])(cd|chdir)\s+(.*)")) st = "absolute path"
    else st = "relative path"
    if (!direxists(nd)) st = st + "; directory does not exist"
    S.cwd = nd
    S.pathsig = S.pathsig + 1
    dp_cdrec(S, file, ln, nd, st)
}

void dp_docall(struct dp_st scalar S, string scalar a0, string scalar kind, real scalar ln, string scalar file, transmorphic scalar L, real scalar mode)
{
    string scalar a, tok, rest, p, args, full, f2, k
    string rowvector toks
    transmorphic scalar L2
    real scalar pc, j, isnew

    a = strtrim(a0)
    pc = dp_topchar(a, ",")
    if (pc > 0) a = strtrim(substr(a, 1, pc-1))
    tok = dp_gettok(a, rest, 0)
    p = dp_unq(tok)
    args = strtrim(rest)
    if (p == "") return
    if (strpos(p, dp_M1())) {
        dp_warn(S, file, ln, kind + " target could not be resolved statically: " + dp_show(p))
        S.nunres = S.nunres + 1
        return
    }
    if (dp_ext(p) == "") p = p + ".do"
    full = dp_path(S, S.cwd, p)
    if (!fileexists(full) & !strpos(subinstr(p, char(92), "/", .), "/")) {
        f2 = dp_findany(S, p)
        if (f2 != "") full = f2
    }
    if (!fileexists(full)) {
        dp_warn(S, file, ln, kind + " target not found: " + full)
        return
    }
    if (dp_under(S, full, S.sysstata)) return
    if (dp_ext(full) == "ado") {
        dp_addado(S, full, dp_noext(dp_basename(full)))
        return
    }
    if (mode == 1) {
        // a do-file run by an ado-file is read like the ado-file
        isnew = !asarray_contains(S.oths, dp_key(S, full))
        dp_addother(S, full, dp_kind(dp_ext(full)))
        if (isnew & dp_ext(full) == "do") {
            L2 = asarray_create()
            dp_parsefile(S, full, 1, L2)
        }
        return
    }
    if (dp_rawabs(S, "(^|[\s:])(do|run|include)\s+(.*)")) dp_note(S, file, ln, "absolute path in " + kind + ": " + S.curraw)
    dp_adddo(S, full)
    k = dp_key(S, full)
    for (j=1; j<=rows(S.stack); j++) {
        if (S.stack[j] != k) continue
        dp_warn(S, file, ln, "recursive call of " + full + " not followed")
        return
    }
    S.visits = S.visits + 1
    if (S.visits > S.maxvisits) {
        if (!S.abort) dp_warn(S, file, ln, "more than maxvisits() file visits; analysis stopped")
        S.abort = 1
        return
    }
    if (kind == "include") {
        dp_parsefile(S, full, 0, L)
        return
    }
    L2 = asarray_create()
    asarray(L2, "0", args)
    toks = dp_toklist(args)
    for (j=1; j<=cols(toks); j++) asarray(L2, strofreal(j), toks[j])
    dp_parsefile(S, full, 0, L2)
}

void dp_assign(struct dp_st scalar S, string scalar s, transmorphic scalar L)
{
    string scalar kw, r, nm, rhs, base, v
    real scalar isg, f, x

    if (!ustrregexm(s, "^(loc|loca|local|gl|glo|glob|globa|global)\s+(.*)")) return
    kw = ustrregexs(1)
    r = ustrregexs(2)
    isg = (substr(kw, 1, 1) == "g")
    if (!ustrregexm(r, "^([+-]*[A-Za-z_][A-Za-z0-9_]*[+-]*)(.*)")) return
    nm = ustrregexs(1)
    rhs = strtrim(ustrregexs(2))
    if (strpos(nm, "+") | strpos(nm, "-")) {
        base = subinstr(subinstr(nm, "+", "", .), "-", "", .)
        if (isg | !asarray_contains(L, base)) return
        x = strtoreal(asarray(L, base))
        if (x >= .) return
        if (strpos(nm, "+")) x = x + 1
        else x = x - 1
        asarray(L, base, strofreal(x, "%21.0g"))
        return
    }
    if (substr(rhs, 1, 1) == "=") {
        v = dp_eval(S, substr(rhs, 2, .), f)
        if (!f) v = dp_M1() + "=" + strtrim(substr(rhs, 2, .)) + dp_M2()
    }
    else if (substr(rhs, 1, 1) == ":") {
        v = dp_extfn(S, substr(rhs, 2, .), f)
        if (!f) v = dp_M1() + ":" + strtrim(substr(rhs, 2, .)) + dp_M2()
    }
    else v = dp_unq(rhs)
    if (isg) asarray(S.globals, nm, v)
    else asarray(L, nm, v)
}

void dp_adopath(struct dp_st scalar S, string scalar a0, real scalar ln, string scalar file)
{
    string scalar a, d, e, u
    string rowvector np
    real scalar op, i, pos

    a = strtrim(a0)
    op = 0
    if (substr(a, 1, 2) == "++") op = 2
    else if (substr(a, 1, 1) == "+") op = 1
    else if (substr(a, 1, 1) == "-") op = 3
    if (op == 0) return
    if (op == 2) d = dp_unq(strtrim(substr(a, 3, .)))
    else d = dp_unq(strtrim(substr(a, 2, .)))
    if (strpos(d, dp_M1())) {
        dp_warn(S, file, ln, "adopath change could not be resolved statically: " + S.curraw)
        S.nunres = S.nunres + 1
        return
    }
    u = strupper(d)
    if (asarray_contains(S.sysdirs, u)) e = u
    else if (d == ".") e = "."
    else e = dp_path(S, S.cwd, d)
    if (op == 1) S.apath = S.apath, e
    if (op == 2) S.apath = e, S.apath
    if (op == 3) {
        pos = strtoreal(d)
        np = J(1, 0, "")
        for (i=1; i<=cols(S.apath); i++) {
            if (pos < . & i == pos) continue
            if (pos >= . & dp_key(S, S.apath[i]) == dp_key(S, e)) continue
            np = np, S.apath[i]
        }
        S.apath = np
    }
    S.pathsig = S.pathsig + 1
    dp_note(S, file, ln, "the code changes the ado-path: " + S.curraw)
}

void dp_sysdir(struct dp_st scalar S, string scalar a, real scalar ln, string scalar file)
{
    string scalar cw, d

    if (!ustrregexm(strtrim(a), "^set\s+([A-Za-z]+)\s+(.+)")) return
    cw = strupper(ustrregexs(1))
    d = dp_unq(ustrregexs(2))
    if (strpos(d, dp_M1())) {
        dp_warn(S, file, ln, "sysdir change could not be resolved statically: " + S.curraw)
        S.nunres = S.nunres + 1
        return
    }
    asarray(S.sysdirs, cw, dp_path(S, S.cwd, d))
    S.pathsig = S.pathsig + 1
    dp_note(S, file, ln, "the code changes a system directory: " + S.curraw)
}

void dp_findfile(struct dp_st scalar S, string scalar a0, real scalar ln, string scalar file, transmorphic scalar L)
{
    string scalar a, opts, fn, pl, e, u, f
    string rowvector parts, dirs
    real scalar pc, i

    a = strtrim(a0)
    opts = ""
    pc = dp_topchar(a, ",")
    if (pc > 0) {
        opts = substr(a, pc+1, .)
        a = strtrim(substr(a, 1, pc-1))
    }
    fn = dp_unq(a)
    if (fn == "") return
    if (strpos(fn, dp_M1())) {
        dp_warn(S, file, ln, "findfile target could not be resolved statically: " + dp_show(fn))
        S.nunres = S.nunres + 1
        return
    }
    if (ustrregexm(opts, "path\(([^)]*)\)")) {
        pl = dp_unq(ustrregexs(1))
        parts = dp_split(pl, ";")
        dirs = J(1, 0, "")
        for (i=1; i<=cols(parts); i++) {
            e = strtrim(dp_unq(parts[i]))
            if (e == "") continue
            u = strupper(e)
            if (asarray_contains(S.sysdirs, u)) dirs = dirs, asarray(S.sysdirs, u)
            else dirs = dirs, dp_path(S, S.cwd, e)
        }
    }
    else dirs = dp_adodirs(S)
    f = dp_findin(S, fn, dirs)
    if (f == "") {
        dp_note(S, file, ln, "findfile target not found: " + fn)
        return
    }
    asarray(L, "r(fn)", f)
    if (!dp_under(S, f, S.sysstata)) dp_addother(S, f, dp_kind(dp_ext(f)))
}

void dp_scheme(struct dp_st scalar S, string scalar nm)
{
    string scalar f

    f = dp_findany(S, "scheme-" + nm + ".scheme")
    if (f == "") return
    if (!dp_under(S, f, S.sysstata)) dp_addother(S, f, "graph scheme")
}

// single-line "if exp command": look for do/run/include/cd after the condition
void dp_iftail(struct dp_st scalar S, string scalar s, real scalar ln, string scalar file, transmorphic scalar L, real scalar mode, real scalar depth)
{
    string scalar ch, c2, t, Q, B, A, re
    real scalar i, n, inq, cq, dep, mk

    Q = dp_Q(); B = dp_B(); A = dp_A()
    re = "^((cap|capt|captu|captur|capture|qui|quie|quiet|quietl|quietly|n|no|noi|nois|noisi|noisil|noisily)\s+)*(do|run|include|cd|chdir)\s"
    n = strlen(s)
    inq = 0; cq = 0; dep = 0; mk = 0
    for (i=3; i<=n; i++) {
        ch = substr(s, i, 1)
        c2 = substr(s, i, 2)
        if (ch == dp_M1()) {
            mk++
            continue
        }
        if (ch == dp_M2()) {
            if (mk > 0) mk--
            continue
        }
        if (mk > 0) continue
        if (inq) {
            if (ch == Q) inq = 0
            continue
        }
        if (cq > 0) {
            if (c2 == B + Q) cq++
            if (c2 == Q + A) cq--
            if (c2 == B + Q | c2 == Q + A) i++
            continue
        }
        if (c2 == B + Q) {
            cq = 1
            i++
            continue
        }
        if (ch == Q) {
            inq = 1
            continue
        }
        if (ch == "(" | ch == "[") dep++
        if (ch == ")" | ch == "]") dep--
        if (ch != " " | dep != 0) continue
        t = strtrim(substr(s, i+1, .))
        if (!ustrregexm(t + " ", re)) continue
        dp_cmd2(S, t, ln, file, L, mode, depth+1)
        return
    }
}

void dp_cmd2(struct dp_st scalar S, string scalar s0, real scalar ln, string scalar file, transmorphic scalar L, real scalar mode, real scalar depth)
{
    string scalar s, w, a, nx, t, nm, Q, t2, fn, tok, rest
    string rowvector nms
    real scalar pos, j, ok

    Q = dp_Q()
    if (depth > 20) return
    s = strtrim(s0)
    // strip capture/quietly/noisily (any order, with or without colon)
    while (ustrregexm(s, "^([A-Za-z_][A-Za-z0-9_]*)")) {
        w = ustrregexs(1)
        if (!(dp_abbr(w, "capture", 3) | dp_abbr(w, "quietly", 3) | dp_abbr(w, "noisily", 1))) break
        if (!(substr(s, strlen(w)+1, 1) == " " | substr(s, strlen(w)+1, 1) == ":")) break
        s = strtrim(substr(s, strlen(w)+1, .))
        if (substr(s, 1, 1) == ":") s = strtrim(substr(s, 2, .))
    }
    if (s == "") return
    if (substr(s, 1, 1) == dp_M1()) {
        if (mode == 0) {
            dp_warn(S, file, ln, "command name comes from an unresolved macro: " + dp_show(s))
            S.nunres = S.nunres + 1
        }
        // the macro may be a prefix (e.g. quietly or nothing): probe the next word
        t = substr(s, dp_skipmark(s), .)
        if (ustrregexm(t, "^ +([A-Za-z_][A-Za-z0-9_]*)( |,|" + char(36) + ")")) dp_command(S, ustrregexs(1), ln, file, L, 2)
        return
    }
    if (!ustrregexm(s, "^([A-Za-z_][A-Za-z0-9_]*)")) return
    w = ustrregexs(1)
    a = substr(s, strlen(w)+1, .)
    nx = substr(a, 1, 1)
    if (!(nx == "" | nx == " " | nx == "," | nx == ":" | nx == Q | nx == "(")) return

    if (w == "do" | w == "run" | w == "include") {
        dp_docall(S, a, w, ln, file, L, mode)
        return
    }
    if (w == "mata") {
        t = strtrim(a)
        if (substr(t, 1, 1) == ":") t = strtrim(substr(t, 2, .))
        if (t != "") dp_matalines(S, t, file)
        return
    }
    if (w == "python") {
        t = strtrim(a)
        if (substr(t, 1, 1) == ":") t = strtrim(substr(t, 2, .))
        if (ustrregexm(t, "^script\s+(.*)")) {
            t = ustrregexs(1)
            pos = dp_topchar(t, ",")
            if (pos > 0) t = substr(t, 1, pos-1)
            ok = dp_usefile(S, dp_gettok(t, rest, 0), "Python script", ln, file, mode, "python script file")
        }
        else if (t != "") dp_pylines(S, t, file)
        return
    }
    if (w == "java") return
    if (w == "javacall") {
        if (ustrregexm(a, "jars\(([^)]*)\)")) {
            nms = dp_split(ustrregexs(1), ";")
            for (j=1; j<=cols(nms); j++) {
                t = strtrim(dp_unq(strtrim(nms[j])))
                if (t != "") ok = dp_usefile(S, t, "Java archive", ln, file, mode, "jar file")
            }
        }
        return
    }
    if (w == "db") {
        if (ustrregexm(a, "^\s+([A-Za-z_][A-Za-z0-9_]*)")) dp_dbcall(S, ustrregexs(1), ln, file, L)
        return
    }
    if (w == "window") {
        nms = dp_allmatch(a, "(^|[^A-Za-z0-9_])db\s+([A-Za-z_][A-Za-z0-9_]*)", 2)
        for (j=1; j<=cols(nms); j++) dp_dbcall(S, nms[j], ln, file, L)
        return
    }
    if (w == "view") {
        if (ustrregexm(a, "^\s+dialog\s+([A-Za-z_][A-Za-z0-9_]*)")) dp_dbcall(S, ustrregexs(1), ln, file, L)
        return
    }
    if (w == "bcal") {
        if (ustrregexm(a, "^\s+(load|des[a-z]*)\s+([A-Za-z_][A-Za-z0-9_]*)")) dp_bcal(S, ustrregexs(2), mode)
        return
    }
    if (w == "dyndoc" | w == "dyntext" | w == "markstat") {
        t = strtrim(a)
        if (w == "markstat") {
            if (ustrregexm(t, "^using\s+(.*)")) t = ustrregexs(1)
            else t = ""
        }
        pos = dp_topchar(t, ",")
        if (pos > 0) t = substr(t, 1, pos-1)
        tok = dp_unq(dp_gettok(t, rest, 0))
        if (tok != "") {
            if (w == "markstat" & dp_ext(tok) == "") tok = tok + ".stmd"
            ok = dp_usefile(S, tok, "dynamic document source", ln, file, mode, w + " source file")
            if (ok & mode == 0) dp_note(S, file, ln, "the Stata code inside " + tok + " (" + w + ") was not followed; check it by hand")
        }
        if (w == "markstat") dp_command(S, w, ln, file, L, mode)
        return
    }
    if (dp_abbr(w, "graph", 2)) {
        if (ustrregexm(a, "^\s+play\s+([A-Za-z_][A-Za-z0-9_]*)")) dp_grec(S, ustrregexs(1), mode)
    }
    if (w == "cd" | w == "chdir") {
        dp_cd(S, a, ln, file, mode)
        return
    }
    if (w == "adopath") {
        dp_adopath(S, a, ln, file)
        return
    }
    if (w == "sysdir") {
        dp_sysdir(S, a, ln, file)
        return
    }
    if (dp_abbr(w, "local", 3) | dp_abbr(w, "global", 2)) {
        dp_assign(S, s, L)
        return
    }
    if (w == "tempfile" | w == "tempname" | w == "tempvar") {
        nms = tokens(a)
        for (j=1; j<=cols(nms); j++) asarray(L, nms[j], "__dptmp_" + nms[j])
        return
    }
    if (w == "args") {
        nms = tokens(a)
        for (j=1; j<=cols(nms); j++) {
            if (!S.inprog & asarray_contains(L, strofreal(j))) asarray(L, nms[j], asarray(L, strofreal(j)))
            else if (asarray_contains(L, nms[j])) asarray_remove(L, nms[j])
        }
        return
    }
    if (w == "findfile") {
        dp_findfile(S, a, ln, file, L)
        return
    }
    if (dp_abbr(w, "program", 2)) {
        t = strtrim(a)
        if (ustrregexm(t, "^((de|def|defi|defin|define)\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*,(.*)")) {
            nm = ustrregexs(3)
            t2 = ustrregexs(4)
            if (ustrregexm(t2, "(^|[ ,])plugin\b")) {
                // plugin definition: no body; the plugin file is name.plugin or using()
                fn = nm + ".plugin"
                if (ustrregexm(t2, "using\(([^)]*)\)")) fn = ustrregexs(1)
                ok = dp_usefile(S, fn, "plugin", ln, file, mode, "plugin file")
                return
            }
        }
        if (!ustrregexm(t, "^(drop|dir|list)(\s|,|" + char(36) + ")")) S.inprog = 1
        return
    }
    if (w == "end") {
        S.inprog = 0
        return
    }
    if (w == "set") {
        if (ustrregexm(a, "^\s+scheme\s+([A-Za-z0-9_]+)")) dp_scheme(S, ustrregexs(1))
        return
    }
    if (dp_abbr(w, "ereturn", 4)) {
        if (ustrregexm(a, "^\s+(loc|loca|local)\s+(predict|estat_cmd)\s+(.+)")) {
            nm = dp_unq(strtrim(ustrregexs(3)))
            if (ustrregexm(nm, "^[A-Za-z_][A-Za-z0-9_]*" + char(36))) dp_command(S, nm, ln, file, L, mode)
        }
        return
    }
    if (w == "ssc" | w == "net" | w == "ado") {
        if (ustrregexm(a, "^\s+(inst|insta|instal|install|update|get)(\s|,|" + char(36) + ")")) {
            if (mode == 0) dp_warn(S, file, ln, "the code installs or updates packages at run time: " + S.curraw)
        }
        return
    }
    if (w == "if") {
        dp_iftail(S, s, ln, file, L, mode, depth)
        return
    }
    if (w == "else") {
        t = strtrim(a)
        if (t != "") dp_cmd2(S, t, ln, file, L, mode, depth+1)
        return
    }
    if (w == "foreach" | w == "forvalues" | w == "while" | dp_abbr(w, "forvalues", 4)) return
    if (ustrregexm(s, "scheme\(\s*([A-Za-z0-9_]+)")) dp_scheme(S, ustrregexs(1))
    if (ustrregexm(s, "(^|[^A-Za-z0-9_])play\(\s*([A-Za-z_][A-Za-z0-9_]*)")) dp_grec(S, ustrregexs(2), mode)
    dp_command(S, w, ln, file, L, mode)
    // a colon after these words is part of their syntax, not a prefix
    if (w == "mata" | w == "python" | w == "java" | w == "gettoken" | w == "_parse" | w == "tokenize" | w == "merge") return
    pos = dp_topchar(s, ":")
    if (pos > 0) dp_cmd2(S, substr(s, pos+1, .), ln, file, L, mode, depth+1)
}

// db name, window menu ... "db name", view dialog name: the dialog and its command
void dp_dbcall(struct dp_st scalar S, string scalar nm, real scalar ln, string scalar file, transmorphic scalar L)
{
    dp_dlgfile(S, nm + ".dlg", "")
    dp_command(S, nm, ln, file, L, 2)
}

void dp_cmd(struct dp_st scalar S, string scalar cc, real scalar ln, string scalar file, transmorphic scalar L, real scalar mode)
{
    string scalar s
    string rowvector nms
    real scalar j

    S.curraw = cc
    s = dp_expand(S, cc, L)
    dp_classscan(S, s)
    if (strpos(s, "%tb")) {
        nms = dp_allmatch(s, "%tb([A-Za-z_][A-Za-z0-9_]*)", 1)
        for (j=1; j<=cols(nms); j++) dp_bcal(S, nms[j], mode)
    }
    dp_cmd2(S, s, ln, file, L, mode, 0)
}

// ------------------------------------------------------------------ blocks

real scalar dp_isblock(string scalar cc)
{
    string scalar t

    t = cc
    if (substr(t, strlen(t), 1) == ":") t = strtrim(substr(t, 1, strlen(t)-1))
    if (t == "mata") return(1)
    if (t == "python") return(2)
    if (t == "java") return(3)
    if (cc == "input") return(4)
    if (ustrregexm(cc, "^(inp|inpu|input)[ ,]")) return(4)
    return(0)
}

real scalar dp_findend(string colvector cmds, real scalar i, real scalar i1)
{
    real scalar k

    for (k=i+1; k<=i1; k++) {
        if (strtrim(cmds[k]) == "end") return(k)
    }
    return(i1)
}

// index of the command that closes the block opened at i (i1+1 if none)
real scalar dp_match(string colvector cmds, real scalar i, real scalar i1)
{
    string scalar t
    real scalar k, depth

    depth = 1
    for (k=i+1; k<=i1; k++) {
        t = strtrim(cmds[k])
        if (substr(t, 1, 1) == "}") depth--
        if (depth == 0) return(k)
        if (substr(t, strlen(t), 1) == "{") depth++
    }
    return(i1 + 1)
}

real scalar dp_after(string colvector cmds, real scalar j, real scalar i1)
{
    string scalar t

    if (j > i1) return(j)
    t = strtrim(cmds[j])
    if (t != "}" & substr(t, strlen(t), 1) == "{") return(j)
    return(j + 1)
}

string rowvector dp_numlist(string scalar r, real scalar ok)
{
    real scalar rc

    ok = 0
    if (strpos(r, dp_M1()) | strtrim(r) == "") return(J(1, 0, ""))
    rc = _stata("numlist " + dp_Q() + strtrim(r) + dp_Q(), 1, 1)
    if (rc) return(J(1, 0, ""))
    ok = 1
    return(tokens(st_global("r(numlist)")))
}

void dp_block(struct dp_st scalar S, string colvector cmds, real colvector lnos, real scalar i, real scalar j, string scalar hdr, string scalar file, transmorphic scalar L, real scalar mode)
{
    string scalar h, v, how, r, nm
    string rowvector vals
    real scalar b0, b1, ok, f, k, quiet

    b0 = i + 1
    b1 = min((j - 1, rows(cmds)))
    S.curraw = hdr
    h = dp_expand(S, hdr, L)
    h = strtrim(substr(h, 1, strlen(h) - 1))
    ok = 0
    quiet = 0
    v = ""
    vals = J(1, 0, "")
    if (ustrregexm(h, "^foreach\s+([A-Za-z_][A-Za-z0-9_]*)\s+(in|of)(\s+|" + char(36) + ")(.*)")) {
        v = ustrregexs(1)
        how = ustrregexs(2)
        r = strtrim(ustrregexs(4))
        if (how == "in") {
            vals = dp_toklist(r)
            ok = 1
        }
        else if (ustrregexm(r, "^(loc|loca|local)\s+([A-Za-z_][A-Za-z0-9_]*)")) {
            nm = ustrregexs(2)
            ok = asarray_contains(L, nm)
            if (ok) vals = dp_toklist(asarray(L, nm))
        }
        else if (ustrregexm(r, "^(gl|glo|glob|globa|global)\s+([A-Za-z_][A-Za-z0-9_]*)")) {
            vals = dp_toklist(dp_globval(S, ustrregexs(2), f))
            ok = f
        }
        else if (ustrregexm(r, "^(numlist)\s+(.*)")) vals = dp_numlist(ustrregexs(2), ok)
        else if (ustrregexm(r, "^(varlist|newlist)\s")) quiet = 1
    }
    else if (ustrregexm(h, "^forv[a-z]*\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)")) {
        v = ustrregexs(1)
        vals = dp_numlist(ustrregexs(2), ok)
    }
    if (b0 > b1) return
    if (v == "") {
        dp_run(S, cmds, lnos, b0, b1, file, L, mode)
        return
    }
    if (!ok) {
        if (asarray_contains(L, v)) asarray_remove(L, v)
        if (mode == 0 & !quiet) dp_warn(S, file, lnos[i], "loop values could not be resolved statically: " + dp_show(h))
        dp_run(S, cmds, lnos, b0, b1, file, L, mode)
        return
    }
    for (k=1; k<=cols(vals); k++) {
        if (S.abort) return
        asarray(L, v, vals[k])
        dp_run(S, cmds, lnos, b0, b1, file, L, mode)
    }
}

void dp_run(struct dp_st scalar S, string colvector cmds, real colvector lnos, real scalar i0, real scalar i1, string scalar file, transmorphic scalar L, real scalar mode)
{
    real scalar i, j, bk
    string scalar cc, h, TB

    TB = "^((cap|capt|captu|captur|capture|qui|quie|quiet|quietl|quietly|n|no|noi|nois|noisi|noisil|noisily)\s+)*(putdocx|putpdf)\s+textblock\s+"
    i = i0
    while (i <= i1) {
        if (S.abort) return
        cc = strtrim(cmds[i])
        bk = dp_isblock(cc)
        if (bk) {
            // mata: and python: blocks are read for the functions and modules they use
            j = dp_findend(cmds, i, i1)
            if (j > i + 1 & bk == 1) dp_matalines(S, cmds[|i+1 \ j-1|], file)
            if (j > i + 1 & bk == 2) dp_pylines(S, cmds[|i+1 \ j-1|], file)
            i = j + 1
            continue
        }
        if (substr(cc, strlen(cc), 1) == "{" & ustrregexm(cc, "^class\s+[A-Za-z_]")) {
            // class definition (.class file): member types and parents are classes
            j = dp_match(cmds, i, i1)
            dp_classdecl(S, cmds, i, j, i1)
            i = j + 1
            continue
        }
        if (ustrregexm(cc, TB + "(begin|append)")) {
            // text of a putdocx/putpdf text block is not code
            for (j=i+1; j<=i1; j++) {
                if (ustrregexm(cmds[j], TB + "end")) break
            }
            i = j + 1
            continue
        }
        if (substr(cc, strlen(cc), 1) == "{") {
            j = dp_match(cmds, i, i1)
            h = cc
            if (substr(h, 1, 1) == "}") h = strtrim(substr(h, 2, .))
            dp_block(S, cmds, lnos, i, j, h, file, L, mode)
            i = dp_after(cmds, j, i1)
            continue
        }
        if (substr(cc, 1, 1) != "}") dp_cmd(S, cc, lnos[i], file, L, mode)
        i++
    }
}

void dp_parsefile(struct dp_st scalar S, string scalar path, real scalar mode, transmorphic scalar L)
{
    string colvector raw, cmds
    real colvector lnos
    real scalar i, saved
    string scalar re, nm

    raw = cat(path)
    if (rows(raw) == 0) return
    raw = subinstr(raw, char(13), "", .)
    raw = subinstr(raw, char(9), " ", .)
    if (substr(raw[1], 1, 3) == char(239) + char(187) + char(191)) raw[1] = substr(raw[1], 4, .)
    dp_prep(raw, cmds, lnos)
    // pre-pass: programs defined in this file
    re = "^(pr|pro|prog|progr|progra|program)\s+((de|def|defi|defin|define)\s+)?([A-Za-z_][A-Za-z0-9_]*)"
    for (i=1; i<=rows(cmds); i++) {
        if (!ustrregexm(cmds[i], re)) continue
        nm = ustrregexs(4)
        if (nm == "drop" | nm == "dir" | nm == "list" | nm == "define") continue
        asarray(L, "prog:" + nm, 1)
        if (mode == 0) asarray(S.defined, nm, 1)
    }
    saved = S.inprog
    S.inprog = 0
    S.stack = S.stack \ dp_key(S, path)
    dp_run(S, cmds, lnos, 1, rows(cmds), path, L, mode)
    if (rows(S.stack) > 1) S.stack = S.stack[1..rows(S.stack)-1]
    else S.stack = J(0, 1, "")
    S.inprog = saved
}

// ------------------------------------------------------------------ main

void dp_init(struct dp_st scalar S)
{
    string scalar h
    string rowvector cw
    real scalar i, rc

    S.win = (c("os") == "Windows")
    S.sysstata = dp_norm(c("sysdir_stata"))
    S.sysdirs = asarray_create()
    cw = ("stata", "base", "site", "plus", "personal", "oldplace")
    for (i=1; i<=cols(cw); i++) asarray(S.sysdirs, strupper(cw[i]), dp_norm(c("sysdir_" + cw[i])))
    S.apath = dp_split(c("adopath"), ";")
    for (i=1; i<=cols(S.apath); i++) S.apath[i] = dp_unq(strtrim(S.apath[i]))
    S.apath0 = S.apath
    rc = _stata("local __dpv : env USERPROFILE", 1, 1)
    h = st_local("__dpv")
    if (h == "") {
        rc = _stata("local __dpv : env HOME", 1, 1)
        h = st_local("__dpv")
    }
    S.home = dp_norm(h)
    S.globals = asarray_create()
    S.defined = asarray_create()
    S.dos = asarray_create()
    S.ados = asarray_create()
    S.oths = asarray_create()
    S.cache = asarray_create()
    S.notfound = asarray_create()
    S.notfado = asarray_create()
    S.trkdone = asarray_create()
    S.trkmap = asarray_create()
    S.pkgfiles = asarray_create()
    S.pkgname = asarray_create()
    S.mfn = asarray_create()
    S.mdef = asarray_create()
    S.done = asarray_create()
    S.mirs = asarray_create()
    S.mirlist = J(0, 1, ""); S.mirkind = J(0, 1, "")
    S.dolist = J(0, 1, ""); S.adolist = J(0, 1, ""); S.adopkg = J(0, 1, "")
    S.othlist = J(0, 1, ""); S.othkind = J(0, 1, ""); S.stack = J(0, 1, "")
    S.cdfile = J(0, 1, ""); S.cdline = J(0, 1, ""); S.cdraw = J(0, 1, "")
    S.cddir = J(0, 1, ""); S.cdstat = J(0, 1, "")
    S.wfile = J(0, 1, ""); S.wline = J(0, 1, ""); S.wmsg = J(0, 1, "")
    S.nfile = J(0, 1, ""); S.nline = J(0, 1, ""); S.nmsg = J(0, 1, "")
    S.pathsig = 0; S.visits = 0; S.abort = 0; S.inprog = 0; S.nunres = 0
    S.curraw = ""; S.mainado = ""; S.mainf = ""; S.realpwd = ""
}

void dp_main()
{
    struct dp_st scalar S
    transmorphic scalar L
    string scalar mainf, realpwd, sd
    pointer() scalar px

    dp_init(S)
    realpwd = dp_norm(st_local("realpwd"))
    mainf = dp_path(S, realpwd, st_local("mainfile"))
    S.maxvisits = strtoreal(st_local("maxvisits"))
    sd = st_local("startdir")
    if (sd != "") sd = dp_path(S, realpwd, sd)
    else sd = dp_dirname(mainf)
    if (!direxists(sd)) {
        errprintf("startdir() %s not found\n", sd)
        exit(601)
    }
    S.cwd = sd
    S.startdir = sd
    if (dp_ext(mainf) == "ado") {
        S.mainado = dp_noext(dp_basename(mainf))
        S.curraw = ""
        dp_addado(S, mainf, S.mainado)
    }
    else {
        dp_adddo(S, mainf)
        S.visits = 1
        L = asarray_create()
        asarray(L, "0", "")
        dp_parsefile(S, mainf, 0, L)
    }
    S.mainf = mainf
    S.realpwd = realpwd
    dp_matafinal(S)
    // the ado now looks up the remaining Mata functions with mata which; the
    // state is kept in an external until dp_main2() continues
    rmexternal("__dp_S")
    px = crexternal("__dp_S")
    *px = S
}

void dp_main2()
{
    struct dp_st scalar S
    pointer() scalar px
    string colvector lines
    string scalar lg
    real scalar i, nok, nfound

    px = findexternal("__dp_S")
    if (px == NULL) {
        errprintf("dopack: internal state not found\n")
        exit(498)
    }
    S = *px
    rmexternal("__dp_S")
    lg = st_local("dp_mlog")
    nok = strtoreal(st_local("dp_mnok"))
    if (lg != "") {
        // libraries are searched along the ado-path of the session, where mata which found them
        S.apath = S.apath0
        S.cwd = S.realpwd
        S.pathsig = S.pathsig + 1
        lines = J(0, 1, "")
        if (fileexists(lg)) lines = cat(lg)
        nfound = 0
        for (i=1; i<=rows(lines); i++) {
            if (!ustrregexm(lines[i], "^\s*([A-Za-z_][A-Za-z0-9_]*)\(\):\s+(.*)")) continue
            nfound++
            dp_matasrc(S, ustrregexs(1), strtrim(ustrregexs(2)))
        }
        if (nok > 0 & nfound == 0) dp_warn(S, "", 0, "the Mata libraries used by the code could not be looked up (mata which gave no output; was dopack run quietly?)")
    }
    dp_finish(S, S.mainf, S.realpwd)
}

// ------------------------------------------------------------------ output

string scalar dp_code(string scalar s)
{
    string scalar t

    t = subinstr(s, "|", char(92) + "|", .)
    if (strpos(t, dp_B())) return(dp_B() + dp_B() + " " + t + " " + dp_B() + dp_B())
    return(dp_B() + t + dp_B())
}

void dp_mkdirs0(string scalar d)
{
    string scalar p
    real scalar rc

    if (direxists(d)) return
    p = dp_dirname(d)
    if (p != d & p != "." & p != "") dp_mkdirs0(p)
    rc = _mkdir(d)
}

void dp_mkdirs(string scalar d)
{
    dp_mkdirs0(d)
    if (!direxists(d)) {
        errprintf("could not create folder %s\n", d)
        exit(693)
    }
}

void dp_rmcontents(string scalar d)
{
    string colvector fs, ds
    real scalar i, rc
    string scalar b

    fs = dir(d, "files", "*", 1)
    for (i=1; i<=rows(fs); i++) rc = _unlink(fs[i])
    ds = dir(d, "dirs", "*", 1)
    for (i=1; i<=rows(ds); i++) {
        b = dp_basename(subinstr(ds[i], char(92), "/", .))
        if (b == "." | b == "..") continue
        dp_rmcontents(ds[i])
        rc = _rmdir(ds[i])
    }
}

real scalar dp_nentries(string scalar d)
{
    return(rows(dir(d, "files", "*")) + rows(dir(d, "dirs", "*")))
}

void dp_copy(string scalar src, string scalar dst)
{
    real scalar rc

    dp_mkdirs(dp_dirname(dst))
    rc = _stata("copy " + dp_Q() + src + dp_Q() + " " + dp_Q() + dst + dp_Q() + ", replace", 1, 1)
    if (rc) {
        errprintf("could not copy %s to %s\n", src, dst)
        exit(rc)
    }
}

// refuse targets that would destroy sources or system folders
void dp_checktarget(struct dp_st scalar S, string scalar tgt, string colvector srcs, string scalar realpwd)
{
    string colvector prot
    string rowvector k
    real scalar i

    if (dp_dirname(tgt) == tgt) {
        errprintf("to() must not be the root of a drive\n")
        exit(498)
    }
    for (i=1; i<=rows(srcs); i++) {
        if (!dp_under(S, srcs[i], tgt)) continue
        errprintf("to() %s contains a file that would be collected (%s)\n", tgt, srcs[i])
        exit(498)
    }
    k = asarray_keys(S.sysdirs)'
    prot = realpwd \ S.home
    for (i=1; i<=cols(k); i++) prot = prot \ asarray(S.sysdirs, k[i])
    for (i=1; i<=rows(prot); i++) {
        if (prot[i] == "" | prot[i] == ".") continue
        if (!dp_under(S, prot[i], tgt)) continue
        errprintf("to() %s is, or contains, a protected folder (%s)\n", tgt, prot[i])
        exit(498)
    }
}

void dp_finish(struct dp_st scalar S, string scalar mainf, string scalar realpwd)
{
    string colvector drel, xrel, F, Fkind, Fpkg, Fdest, R, srcs, keys
    string scalar root, adodir, tgt, Q, title, purpose, srel, mrel, s, kd, nfl, dfl, afl, ofl, xfl, FN
    real colvector skip
    real scalar nd, na, no, nx, i, ncop, isado, rc, hasmlib, hasgrec
    transmorphic scalar seen

    Q = dp_Q()
    FN = dp_B() + dp_B() + dp_B()
    nd = rows(S.dolist)
    na = rows(S.adolist)
    no = rows(S.othlist)
    nx = rows(S.mirlist)
    isado = (S.mainado != "")

    // ---- package layout
    if (st_local("root") != "") root = dp_path(S, realpwd, st_local("root"))
    else if (nd > 0) {
        srcs = S.startdir
        for (i=1; i<=nd; i++) srcs = srcs \ dp_dirname(S.dolist[i])
        for (i=1; i<=nx; i++) srcs = srcs \ dp_dirname(S.mirlist[i])
        root = dp_common(S, srcs)
    }
    else root = ""
    drel = J(nd, 1, "")
    for (i=1; i<=nd; i++) drel[i] = dp_relin(S, S.dolist[i], root)
    xrel = J(nx, 1, "")
    for (i=1; i<=nx; i++) xrel[i] = dp_relin(S, S.mirlist[i], root)
    adodir = "ado"
    for (i=1; i<=nd; i++) {
        if (substr(dp_key(S, drel[i]), 1, 4) == "ado/") adodir = "_ado"
    }
    for (i=1; i<=nx; i++) {
        if (substr(dp_key(S, xrel[i]), 1, 4) == "ado/") adodir = "_ado"
    }
    F = S.adolist \ S.othlist
    Fkind = J(na, 1, "ado-file") \ S.othkind
    Fpkg = S.adopkg \ J(no, 1, "")
    Fdest = J(rows(F), 1, "")
    skip = J(rows(F), 1, 0)
    seen = asarray_create()
    hasmlib = 0
    hasgrec = 0
    for (i=1; i<=rows(F); i++) {
        if (dp_ext(F[i]) == "mlib") hasmlib = 1
        if (dp_ext(F[i]) == "grec") hasgrec = 1
        Fdest[i] = adodir + "/" + dp_basename(F[i])
        kd = dp_key(S, Fdest[i])
        if (asarray_contains(seen, kd)) {
            skip[i] = 1
            dp_warn(S, "", 0, "two files share the name " + dp_basename(F[i]) + "; only the first was kept, skipped: " + F[i])
        }
        else asarray(seen, kd, 1)
    }

    // ---- screen report
    printf("\n{txt}Main file:  ")
    display(mainf, 1)
    if (root != "") {
        printf("{txt}Root:       ")
        display(root, 1)
    }
    if (!isado) {
        printf("{txt}Start dir:  ")
        display(S.startdir, 1)
    }
    printf("\n{txt}do-files (%g):\n", nd)
    for (i=1; i<=nd; i++) display("    " + drel[i], 1)
    if (nx > 0) {
        printf("{txt}other files used by the do-files, kept in the folder tree (%g):\n", nx)
        for (i=1; i<=nx; i++) display("    " + xrel[i] + "   (" + S.mirkind[i] + ")", 1)
    }
    printf("{txt}ado-files (%g):\n", na)
    for (i=1; i<=na; i++) {
        s = "    " + dp_basename(S.adolist[i])
        if (S.adopkg[i] != "") s = s + "   [package " + S.adopkg[i] + "]"
        display(s + "   <- " + S.adolist[i], 1)
    }
    printf("{txt}other files (%g):\n", no)
    for (i=1; i<=no; i++) display("    " + dp_basename(S.othlist[i]) + "   (" + S.othkind[i] + ")   <- " + S.othlist[i], 1)
    printf("{txt}working-directory changes (%g):\n", rows(S.cdfile))
    for (i=1; i<=rows(S.cdfile); i++) {
        display("    " + dp_relin(S, S.cdfile[i], root) + ":" + S.cdline[i] + "   " + S.cdraw[i] + "   -> " + S.cddir[i] + "   [" + S.cdstat[i] + "]", 1)
    }
    if (rows(S.nmsg) > 0) {
        printf("{txt}notes (%g):\n", rows(S.nmsg))
        for (i=1; i<=rows(S.nmsg); i++) display("    " + dp_relin(S, S.nfile[i], root) + ":" + S.nline[i] + "   " + S.nmsg[i], 1)
    }
    if (rows(S.wmsg) > 0) {
        printf("{err}warnings (%g):\n", rows(S.wmsg))
        for (i=1; i<=rows(S.wmsg); i++) {
            if (S.wfile[i] != "") display("    " + dp_relin(S, S.wfile[i], root) + ":" + S.wline[i] + "   " + dp_show(S.wmsg[i]), 1)
            else display("    " + dp_show(S.wmsg[i]), 1)
        }
    }
    displayflush()

    // ---- results back to Stata
    dfl = ""
    for (i=1; i<=nd; i++) dfl = dfl + (i > 1 ? " " : "") + Q + drel[i] + Q
    afl = ""
    for (i=1; i<=na; i++) afl = afl + (i > 1 ? " " : "") + dp_noext(dp_basename(S.adolist[i]))
    ofl = ""
    for (i=1; i<=no; i++) ofl = ofl + (i > 1 ? " " : "") + Q + dp_basename(S.othlist[i]) + Q
    xfl = ""
    for (i=1; i<=nx; i++) xfl = xfl + (i > 1 ? " " : "") + Q + xrel[i] + Q
    keys = asarray_keys(S.notfound)
    if (rows(keys) > 1) keys = sort(keys, 1)
    nfl = ""
    for (i=1; i<=rows(keys); i++) nfl = nfl + " " + keys[i]
    st_local("dp_ndo", strofreal(nd))
    st_local("dp_nado", strofreal(na))
    st_local("dp_noth", strofreal(no))
    st_local("dp_ncd", strofreal(rows(S.cdfile)))
    st_local("dp_nunres", strofreal(S.nunres))
    st_local("dp_nwarn", strofreal(rows(S.wmsg)))
    st_local("dp_ncopied", "0")
    st_local("dp_dofiles", dfl)
    st_local("dp_ados", afl)
    st_local("dp_others", ofl)
    st_local("dp_scripts", xfl)
    st_local("dp_nscr", strofreal(nx))
    st_local("dp_nf", strtrim(nfl))
    keys = asarray_keys(S.notfado)
    if (rows(keys) > 1) keys = sort(keys, 1)
    nfl = ""
    for (i=1; i<=rows(keys); i++) nfl = nfl + " " + keys[i]
    st_local("dp_nfado", strtrim(nfl))
    st_local("dp_root", root)
    st_local("dp_startdir", S.startdir)
    st_local("dp_main", mainf)
    st_local("dp_target", "")
    if (st_local("dryrun") != "") {
        printf("\n{txt}dryrun: nothing was copied.\n")
        return
    }

    // ---- target folder
    tgt = dp_path(S, realpwd, st_local("to"))
    if (fileexists(tgt) & !direxists(tgt)) {
        errprintf("to() %s is a file, not a folder\n", tgt)
        exit(602)
    }
    srcs = S.dolist \ S.mirlist \ F
    dp_checktarget(S, tgt, srcs, realpwd)
    if (direxists(tgt)) {
        if (dp_nentries(tgt) > 0) {
            if (st_local("replace") == "") {
                errprintf("to() %s is not empty; specify replace to empty it first\n", tgt)
                exit(602)
            }
            dp_rmcontents(tgt)
            if (dp_nentries(tgt) > 0) {
                errprintf("could not empty %s\n", tgt)
                exit(693)
            }
        }
    }
    else dp_mkdirs(tgt)

    // ---- copy
    ncop = 0
    for (i=1; i<=nd; i++) {
        dp_copy(S.dolist[i], tgt + "/" + drel[i])
        ncop++
    }
    for (i=1; i<=nx; i++) {
        dp_copy(S.mirlist[i], tgt + "/" + xrel[i])
        ncop++
    }
    for (i=1; i<=rows(F); i++) {
        if (skip[i]) continue
        dp_copy(F[i], tgt + "/" + Fdest[i])
        ncop++
    }

    // ---- readme.md
    title = st_local("title")
    if (title == "") title = dp_noext(dp_basename(mainf))
    purpose = st_local("purpose")
    if (purpose == "") purpose = "_TODO: describe what this code does, which data it needs and what it produces._"
    R = "# " + title \ "" \ "## Purpose" \ "" \ purpose \ "" \ "## How to run" \ ""
    if (isado) {
        R = R \ ("This folder contains the user-written command " + dp_code(S.mainado) + " and every user-written file it needs.") \ ""
        R = R \ "1. Copy this whole folder to the new computer." \ "2. In Stata, make the commands available and open the help file:" \ ""
        R = R \ (FN + "stata") \ ("adopath ++ " + Q + "<PACKAGE>/" + adodir + Q)
        if (hasmlib) R = R \ "mata mlib index"
        R = R \ ("help " + S.mainado) \ FN \ ""
    }
    else {
        srel = dp_relin(S, S.startdir, root)
        mrel = dp_relpath(S, S.startdir, mainf)
        R = R \ ("The main file is " + dp_code(drel[1]) + ". Run it as follows.") \ ""
        R = R \ "1. Copy this whole folder to the new computer; keep the subfolders as they are."
        if (rows(F) > 0) {
            R = R \ "2. Make the bundled user-written commands available:" \ ""
            R = R \ ("   " + FN + "stata") \ ("   adopath ++ " + Q + "<PACKAGE>/" + adodir + Q)
            if (hasmlib) R = R \ "   mata mlib index"
            R = R \ ("   " + FN) \ ""
            R = R \ "3. Set the working directory and run the main file:"
        }
        else R = R \ "2. Set the working directory and run the main file:"
        R = R \ "" \ ("   " + FN + "stata") \ ("   cd " + Q + "<PACKAGE>" + (srel != "" ? "/" + srel : "") + Q) \ ("   do " + Q + mrel + Q) \ ("   " + FN) \ ""
        if (substr(srel, 1, 10) == "_external/") R = R \ ("   The working directory at the start lies outside the folder that holds the code; adjust the " + dp_code("cd") + " line.") \ ""
        R = R \ "Data files and other inputs read by the code are **not** included." \ ""
    }
    R = R \ (dp_code("<PACKAGE>") + " stands for the location of this folder on your computer.") \ ""
    if (hasmlib) R = R \ ("The Mata libraries (" + dp_code(".mlib") + ") are found after " + dp_code("mata mlib index") + ".") \ ""
    if (hasgrec) R = R \ ("If Stata does not find a graph recording (" + dp_code(".grec") + "), copy it to the " + dp_code("grec") + " folder of your PERSONAL ado-folder (type " + dp_code("sysdir") + " to see where that is).") \ ""
    R = R \ "## Files" \ "" \ "| File | Type |" \ "|---|---|"
    for (i=1; i<=nd; i++) R = R \ ("| " + dp_code(drel[i]) + " | do-file" + (i == 1 ? " (main)" : "") + " |")
    for (i=1; i<=nx; i++) R = R \ ("| " + dp_code(xrel[i]) + " | " + S.mirkind[i] + " |")
    for (i=1; i<=rows(F); i++) {
        if (skip[i]) continue
        s = Fkind[i]
        if (Fpkg[i] != "") s = s + " (package " + Fpkg[i] + ")"
        R = R \ ("| " + dp_code(Fdest[i]) + " | " + s + " |")
    }
    R = R \ ("| " + dp_code("readme.md") + " | this file |") \ ""
    if (rows(S.cdfile) > 0) {
        R = R \ "## Working-directory changes" \ ""
        R = R \ "The code changes the working directory as listed below (read from the code in the order it would run; the code itself was not run)." \ ""
        R = R \ "| Where | Command | Directory | In this package |" \ "|---|---|---|---|"
        for (i=1; i<=rows(S.cdfile); i++) {
            s = "| " + dp_code(dp_relin(S, S.cdfile[i], root)) + ", line " + S.cdline[i] + " | " + dp_code(S.cdraw[i]) + " | "
            if (S.cddir[i] == "") s = s + "unresolved | ? |"
            else if (root != "" & dp_under(S, S.cddir[i], root)) {
                kd = dp_relin(S, S.cddir[i], root)
                s = s + dp_code(S.cddir[i]) + " | " + dp_code("<PACKAGE>" + (kd != "" ? "/" + kd : "")) + (strpos(S.cdstat[i], "absolute") ? " (absolute path in the code: edit it)" : "") + " |"
            }
            else s = s + dp_code(S.cddir[i]) + " | outside this package |"
            R = R \ s
        }
        R = R \ ""
    }
    if (rows(S.nmsg) + rows(S.wmsg) > 0) {
        R = R \ "## Notes" \ ""
        for (i=1; i<=rows(S.nmsg); i++) R = R \ ("- " + dp_code(dp_relin(S, S.nfile[i], root)) + ", line " + S.nline[i] + ": " + subinstr(subinstr(S.nmsg[i], "|", char(92) + "|", .), dp_B(), char(92) + dp_B(), .))
        for (i=1; i<=rows(S.wmsg); i++) {
            s = subinstr(subinstr(dp_show(S.wmsg[i]), dp_B(), char(92) + dp_B(), .), "|", char(92) + "|", .)
            if (S.wfile[i] != "") s = dp_code(dp_relin(S, S.wfile[i], root)) + ", line " + S.wline[i] + ": " + s
            R = R \ ("- " + s)
        }
        R = R \ ""
    }
    R = R \ ("_Assembled by dopack 0.2.1 on " + c("current_date") + " with Stata " + strofreal(c("stata_version")) + " by static reading of the code._")
    dp_writelines(tgt + "/readme.md", R)
    ncop++

    st_local("dp_ncopied", strofreal(ncop))
    st_local("dp_target", tgt)
    printf("\n{txt}Copied %g files (including readme.md) to ", ncop)
    display(tgt, 1)
}

void dp_writelines(string scalar path, string colvector R)
{
    real scalar fh, i

    if (fileexists(path)) unlink(path)
    fh = fopen(path, "w")
    for (i=1; i<=rows(R); i++) fput(fh, R[i])
    fclose(fh)
}

end

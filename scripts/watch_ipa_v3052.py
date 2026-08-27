#!/usr/bin/env python3
"""Watch CI run (head_sha 3b43825) and download the built IPA artifact for 轻聊 v3.0.52."""
import sys, time, json, os, zipfile, urllib.request, re, subprocess

REPO = "lxm20060513-svg/qingliao-ios"
SHA = "3b43825"
OUT = "/opt/data/qingliao-3.0.52-unsigned.ipa"
GIT_CWD = "/opt/data/qingliao_ios"

def get_token():
    r = subprocess.run(["git","remote","get-url","origin"], capture_output=True, text=True, cwd=GIT_CWD)
    m = re.search(r'://[^:]*:([^@]*)@', r.stdout.strip())
    return m.group(1) if m else None

def api(path, token):
    req = urllib.request.Request(f"https://api.github.com{path}", headers={
        "Authorization": f"token {token}", "Accept": "application/vnd.github+json",
        "User-Agent": "hermes-watch"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())

TOK = get_token()
if not TOK:
    print("ERROR no token"); sys.exit(1)

run_id = None
for attempt in range(80):  # 80*30s=40min
    try:
        data = api("/repos/%s/actions/runs?per_page=5" % REPO, TOK)
    except Exception as e:
        print("[%d] API err %s" % (attempt, e)); time.sleep(30); continue
    for run in data.get("workflow_runs", []):
        if run["head_sha"].startswith(SHA):
            run_id = run["id"]; st = run["status"]; concl = run.get("conclusion","")
            print("[%d] run=%s status=%s concl=%s" % (attempt, run_id, st, concl), flush=True)
            if st == "completed":
                if concl == "success":
                    print("CI SUCCESS, downloading artifact", flush=True)
                    arts = api("/repos/%s/actions/runs/%s/artifacts" % (REPO, run_id), TOK)
                    art = None
                    for a in arts.get("artifacts", []):
                        if a["name"] == "qingliao-2.0-unsigned-ipa":
                            art = a; break
                    if not art and arts.get("artifacts"):
                        art = arts["artifacts"][0]
                    if not art:
                        print("ERROR no artifact"); sys.exit(1)
                    dl = urllib.request.Request("https://api.github.com/repos/%s/actions/artifacts/%s/zip"
                                                % (REPO, art["id"]), headers={
                        "Authorization": "token %s" % TOK, "Accept":"application/vnd.github+json",
                        "User-Agent":"hermes-watch"})
                    with urllib.request.urlopen(dl, timeout=300) as resp:
                        zdata = resp.read()
                    zpath = "/opt/data/ipa_artifact.tmp.zip"
                    with open(zpath,"wb") as f: f.write(zdata)
                    # extract the inner .ipa
                    with zipfile.ZipFile(zpath) as z:
                        ipa = [n for n in z.namelist() if n.endswith(".ipa")]
                        if not ipa:
                            print("ERROR no .ipa inside artifact; names=", z.namelist()); sys.exit(1)
                        with z.open(ipa[0]) as fsrc, open(OUT,"wb") as fdst:
                            fdst.write(fsrc.read())
                    size = os.path.getsize(OUT)
                    # verify version
                    ver = "?"
                    try:
                        with zipfile.ZipFile(OUT) as z:
                            import plistlib
                            pl = plistlib.loads(z.read("Payload/Qingliao.app/Info.plist"))
                            ver = pl.get("CFBundleShortVersionString"); bld = pl.get("CFBundleVersion")
                    except Exception as e:
                        ver = "verify-err:" + str(e); bld = ""
                    print("DONE out=%s size=%s version=%s build=%s" % (OUT, size, ver, bld), flush=True)
                    sys.exit(0)
                else:
                    print("CI FAILED: %s" % concl); sys.exit(1)
            break
    time.sleep(30)
print("TIMEOUT"); sys.exit(1)
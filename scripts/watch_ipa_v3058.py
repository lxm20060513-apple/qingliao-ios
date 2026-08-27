#!/usr/bin/env python3
"""Watch CI (SHA 02d5181) → download built IPA (release asset) for 轻聊 v3.0.58."""
import sys, time, json, os, zipfile, plistlib, urllib.request, re, subprocess, hashlib
REPO="lxm20060513-svg/qingliao-ios"; SHA="02d5181"
OUT="/opt/data/qingliao-3.0.58-unsigned.ipa"; GIT_CWD="/opt/data/qingliao_ios"; WANT="3.0.58"
def get_token():
    r=subprocess.run(["git","remote","get-url","origin"],capture_output=True,text=True,cwd=GIT_CWD)
    return re.search(r'://[^:]*:([^@]*)@', r.stdout.strip()).group(1)
def api(path,tok):
    q=urllib.request.Request("https://api.github.com"+path,headers={"Authorization":"token "+tok,"User-Agent":"hermes"})
    with urllib.request.urlopen(q,timeout=30) as r: return json.loads(r.read())
tok=get_token()
for attempt in range(90):
    try: data=api("/repos/%s/actions/runs?per_page=6"%REPO,tok)
    except Exception as e: print("[%d] api err %s"%(attempt,e),flush=True); time.sleep(30); continue
    for run in data.get("workflow_runs",[]):
        if run["head_sha"].startswith(SHA):
            st=run["status"]; rc=run.get("conclusion","")
            print("[%d] run=%s %s %s"%(attempt,run["id"],st,rc),flush=True)
            if st=="completed":
                if rc!="success": print("CI FAILED %s"%rc,flush=True); sys.exit(1)
                rels=api("/repos/%s/releases?per_page=2"%REPO,tok)
                best=None
                for rel in rels:
                    for a in rel.get("assets",[]):
                        if a["name"].endswith(".ipa"):
                            if best is None or a["created_at"]>best[0]: best=(a["created_at"],a["browser_download_url"],a["name"])
                if best is None: print("ERROR no release asset",flush=True); sys.exit(1)
                raw=None
                for a2 in range(8):
                    try:
                        q=urllib.request.Request(best[1],headers={"User-Agent":"hermes","Accept":"application/octet-stream"})
                        with urllib.request.urlopen(q,timeout=300) as r: raw=r.read(); break
                    except Exception as e:
                        print("  dl retry %d err %s"%(a2,type(e).__name__),flush=True); time.sleep(5)
                if raw is None: print("DOWNLOAD FAILED",flush=True); sys.exit(1)
                open(OUT,"wb").write(raw)
                with zipfile.ZipFile(OUT) as z:
                    pl=plistlib.loads(z.read("Payload/Qingliao.app/Info.plist"))
                ver=pl.get('CFBundleShortVersionString')
                print("af asset=%s ver=%s build=%s size=%d md5=%s"%(best[2],ver,pl.get('CFBundleVersion'),len(raw),hashlib.md5(raw).hexdigest()),flush=True)
                if ver!=WANT:
                    print("VER MISMATCH want=%s got=%s keep waiting"%(WANT,ver),flush=True); time.sleep(30); break
                print("DONE out=%s"%OUT,flush=True); sys.exit(0)
            break
    time.sleep(30)
print("TIMEOUT",flush=True); sys.exit(1)
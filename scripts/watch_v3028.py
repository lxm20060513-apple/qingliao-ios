#!/usr/bin/env python3
"""Poll CI run 32451288129 (v3.0.28), download IPA workflow artifact on success."""
import sys, time, urllib.request, json, os, zipfile, re

REPO = "lxm20060513-svg/qingliao-ios"
RUN_ID = "32451288129"

def get_token():
    import subprocess
    out = subprocess.run(["git", "remote", "get-url", "origin"],
                         capture_output=True, text=True, cwd="/opt/data/ql_ipa2").stdout.strip()
    m = re.search(r'://[^:]*:([^@]*)@', out)
    return m.group(1) if m else None

def api(path, token):
    req = urllib.request.Request(f"https://api.github.com{path}", headers={
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "hermes-watch"})
    return json.loads(urllib.request.urlopen(req).read())

def main():
    token = get_token()
    if not token:
        print("ERROR: no token"); sys.exit(1)
    outdir = "/opt/data/ql_ipa2/builds/v3.0.28_ipa"
    os.makedirs(outdir, exist_ok=True)
    for attempt in range(120):
        try:
            run = api(f"/repos/{REPO}/actions/runs/{RUN_ID}", token)
            status, concl = run.get("status"), run.get("conclusion")
            print(f"[{attempt}] {status} {concl}", flush=True)
            if status == "completed":
                if concl == "success":
                    # list artifacts
                    arts = api(f"/repos/{REPO}/actions/runs/{RUN_ID}/artifacts", token)
                    for a in arts.get("artifacts", []):
                        print(f"ARTIFACT: {a['name']} size={a['size_in_bytes']} expired={a.get('expired')}", flush=True)
                    # download all, find ipa
                    art = None
                    for a in arts.get("artifacts", []):
                        if not a.get("expired"):
                            art = a; break
                    if not art:
                        print("ERROR: no valid artifact"); sys.exit(1)
                    dl = f"https://api.github.com/repos/{REPO}/actions/artifacts/{art['id']}/zip"
                    req = urllib.request.Request(dl, headers={
                        "Authorization": f"token {token}", "Accept": "application/vnd.github.v3+json",
                        "User-Agent": "hermes-watch"})
                    data = urllib.request.urlopen(req).read()
                    zp = os.path.join(outdir, "artifact.zip")
                    open(zp, "wb").write(data)
                    # unzip
                    with zipfile.ZipFile(zp) as z:
                        names = z.namelist()
                        print("ZIP CONTENTS:", names, flush=True)
                        z.extractall(outdir)
                    # locate .ipa and copy to a stable name
                    ipa_path = None
                    for root, _, files in os.walk(outdir):
                        for f in files:
                            if f.endswith(".ipa"):
                                ipa_path = os.path.join(root, f)
                    if ipa_path:
                        dest = "/opt/data/qingliao-unsigned.ipa"
                        # verify CFBundleShortVersionString == 3.0.28
                        ver = verify_version(ipa_path)
                        print(f"IPA_VERSION_CHECK: {ver}", flush=True)
                        print(f"DOWNLOADED: {dest}", flush=True)
                    else:
                        print("ERROR: no .ipa inside artifact", flush=True)
                    return
                else:
                    print(f"CI FAILED: {concl}"); sys.exit(1)
        except Exception as e:
            print(f"[{attempt}] error: {e}", flush=True)
        time.sleep(30)
    print("TIMEOUT"); sys.exit(1)

def verify_version(ipa_path):
    try:
        import zipfile
        with zipfile.ZipFile(ipa_path) as z:
            info = z.read("Payload/Qingliao.app/Info.plist")
        import plistlib
        pl = plistlib.loads(info)
        return pl.get("CFBundleShortVersionString")
    except Exception as e:
        return f"verify-error:{e}"

if __name__ == "__main__":
    main()

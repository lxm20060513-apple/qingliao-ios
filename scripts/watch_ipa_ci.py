#!/usr/bin/env python3
"""Watch CI run and download IPA from GitHub Release when done."""
import sys, time, urllib.request, json, os

def get_token():
    # Get token from git remote URL
    import subprocess
    result = subprocess.run(["git", "remote", "get-url", "origin"], capture_output=True, text=True, cwd="/opt/data/ql_ipa2")
    url = result.stdout.strip()
    # Extract token from URL like https://user:TOKEN@github.com/...
    import re
    m = re.search(r'://[^:]*:([^@]*)@', url)
    return m.group(1) if m else None

def api(path, token):
    url = f"https://api.github.com{path}"
    req = urllib.request.Request(url, headers={
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "hermes-watch"
    })
    resp = urllib.request.urlopen(req)
    return json.loads(resp.read())

def main():
    sha_prefix = sys.argv[1] if len(sys.argv) > 1 else None
    output_path = sys.argv[2] if len(sys.argv) > 2 else "/opt/data/qingliao-unsigned.ipa"
    repo = "lxm20060513-svg/qingliao-ios"
    token = get_token()
    if not token:
        print("ERROR: Cannot extract GitHub token")
        sys.exit(1)

    print(f"Watching CI for SHA prefix: {sha_prefix}")
    print(f"Output: {output_path}")

    # Find the run
    run_id = None
    for attempt in range(120):  # 120 * 30s = 60 min max
        data = api(f"/repos/{repo}/actions/runs?per_page=5", token)
        for run in data.get("workflow_runs", []):
            if sha_prefix and run["head_sha"].startswith(sha_prefix):
                run_id = run["id"]
                status = run["status"]
                conclusion = run.get("conclusion", "")
                print(f"[{attempt}] Run {run_id}: {status} {conclusion}")
                if status == "completed":
                    if conclusion == "success":
                        print("CI SUCCESS! Downloading IPA...")
                        download_ipa(repo, token, output_path)
                        return
                    else:
                        print(f"CI FAILED: {conclusion}")
                        sys.exit(1)
                break
        else:
            print(f"[{attempt}] Run not found yet for SHA {sha_prefix}")
        time.sleep(30)

    print("TIMEOUT: CI did not complete in 60 minutes")
    sys.exit(1)

def download_ipa(repo, token, output_path):
    # Get latest release
    data = api(f"/repos/{repo}/releases?per_page=5", token)
    for rel in data:
        for asset in rel.get("assets", []):
            if asset["name"].endswith(".ipa"):
                print(f"Downloading {asset['name']} ({asset['size']} bytes)...")
                url = asset["browser_download_url"]
                req = urllib.request.Request(url, headers={
                    "Authorization": f"token {token}",
                    "User-Agent": "hermes-watch"
                })
                resp = urllib.request.urlopen(req)
                with open(output_path, "wb") as f:
                    f.write(resp.read())
                size = os.path.getsize(output_path)
                print(f"Downloaded: {output_path} ({size} bytes)")
                return
    print("No IPA found in releases")

if __name__ == "__main__":
    main()

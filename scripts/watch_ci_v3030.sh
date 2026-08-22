#!/bin/bash
# watch_ci_ship_ipa v3.0.30：盯 GitHub Actions → 成功下载 IPA → plistlib 校验 → 转存 NAS 微信文件夹
set -u
REPO="lxm20060513-svg/qingliao-ios"
TAG_VER="v3.0.30"
WANT_SHA="af5788a"
OUT_NAME="qingliao-v3.0.30.ipa"
TOKEN=$(python3 -c "
import subprocess, re
url = subprocess.check_output(['git','-C','/opt/data/ql_ipa2','remote','get-url','origin']).decode().strip()
print(re.sub(r'https://[^:]+:([^@]+)@.*', r'\1', url))
")
if [ -z "$TOKEN" ]; then echo "❌ 提取 token 失败"; exit 1; fi

# 轮询等 CI 完成（最多 45 分钟）
for ATTEMPT in $(seq 1 90); do
  RUNS=$(curl -s -m 30 -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/actions/runs?per_page=5")
  RUN_ID=$(echo "$RUNS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for r in d.get('workflow_runs', []):
    if r['head_sha'].startswith('$WANT_SHA'):
        print(r['id']); break
")
  if [ -z "$RUN_ID" ]; then echo "⚠️ [$ATTEMPT] 未找到 $TAG_VER 对应 run（sha $WANT_SHA）"; sleep 30; continue; fi
  STATUS=$(echo "$RUNS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for r in d.get('workflow_runs', []):
    if r['id'] == $RUN_ID: print(r['status']); break
")
  CONCL=$(echo "$RUNS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for r in d.get('workflow_runs', []):
    if r['id'] == $RUN_ID: print(r['conclusion'] or ''); break
")
  echo "[$ATTEMPT] run=$RUN_ID status=$STATUS conclusion=$CONCL"
  if [ "$STATUS" = "completed" ]; then break; fi
  sleep 30
done

if [ "$STATUS" != "completed" ]; then echo "❌ CI 45 分钟未完成"; exit 1; fi
if [ "$CONCL" != "success" ]; then echo "❌ CI $TAG_VER 构建失败（$CONCL），run=$RUN_ID"; exit 1; fi

ART=$(curl -s -m 30 -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/actions/runs/$RUN_ID/artifacts" | python3 -c "
import sys, json
d = json.load(sys.stdin)
arts = d.get('artifacts', [])
if arts: print(arts[0]['archive_download_url'])
")
if [ -z "$ART" ]; then echo "❌ 无 artifact"; exit 1; fi
rm -rf /tmp/watch_release && mkdir -p /tmp/watch_release
curl -sL -m 120 -H "Authorization: Bearer $TOKEN" -o /tmp/watch_release/art.zip "$ART"
cd /tmp/watch_release && python3 -c "
import zipfile, sys
with zipfile.ZipFile('art.zip') as z: z.extractall('.')
" && rm -f art.zip
IPA=$(find /tmp/watch_release -name "*.ipa" | head -1)
if [ -z "$IPA" ]; then echo "❌ artifact 内无 IPA"; exit 1; fi

VER=$(python3 -c "
import zipfile, plistlib
z = zipfile.ZipFile('$IPA')
name = [n for n in z.namelist() if n.endswith('.app/Info.plist')][0]
data = z.read(name)
p = plistlib.loads(data)
print(p.get('CFBundleShortVersionString', ''))
")
echo "IPA 版本校验: $VER (期望 3.0.30)"
if [ "$VER" != "3.0.30" ]; then echo "❌ 版本不匹配"; exit 1; fi

# 转存 NAS 微信文件夹（paramiko 分块 + sudo PTY root 属主目录）
/opt/data/paramiko_old/bin/python3 - "$IPA" "$OUT_NAME" <<PYEOF
import sys, base64, hashlib, time
sys.path.insert(0, "/opt/data/paramiko_old/lib/python3.13/site-packages")
import paramiko
ipa = open(sys.argv[1], "rb").read()
b64 = base64.b64encode(ipa).decode()
pwd = open("/opt/data/.nas_cred").read().strip()
out = sys.argv[2]
c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.31.40", username="lxm20060513", password=pwd, timeout=15)
stdin, stdout, stderr = c.exec_command("cat > /tmp/ql_ipa.b64", timeout=120)
for i in range(0, len(b64), 60000):
    stdin.write(b64[i:i+60000])
stdin.channel.shutdown_write(); stdout.read(); c.close()
c = paramiko.SSHClient(); c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect("192.168.31.40", username="lxm20060513", password=pwd, timeout=15)
stdin, stdout, stderr = c.exec_command("sudo -s", get_pty=True)
stdin.write(pwd + "\n"); stdin.flush(); time.sleep(1.5)
chan = stdout.channel
cmd = f'base64 -d /tmp/ql_ipa.b64 > "/volume1/docker/hermes/微信文件/轻聊app/{out}" && chmod 644 "/volume1/docker/hermes/微信文件/轻聊app/{out}" && md5sum "/volume1/docker/hermes/微信文件/轻聊app/{out}" && rm -f /tmp/ql_ipa.b64\n'
stdin.write(cmd + "\n"); stdin.flush(); time.sleep(3)
res = b""
while chan.recv_ready(): res += chan.recv(65536)
time.sleep(1)
while chan.recv_ready(): res += chan.recv(65536)
print("LOCAL MD5:", hashlib.md5(ipa).hexdigest())
print(res.decode("utf-8", errors="replace")[-600:])
c.close()
PYEOF
echo "✅ $TAG_VER IPA 已转存微信文件夹（版本校验: $VER）"
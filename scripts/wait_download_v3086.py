#!/usr/bin/env python3
"""等 v3.0.86 CI 构建成功后自动下载 IPA。"""
import urllib.request, json, time, hashlib

token = open('/opt/data/.gh_cred').read().strip()
repo = 'lxm20060513-svg/qingliao-ios'
target_head = '6d04526'  # v3.0.86 的 HEAD 前缀
OUT = '/opt/data/ipa_dl/qingliao_v3.0.86.ipa'
UA = 'hermes-wait'

def api(u):
    r = urllib.request.Request(u, headers={'Authorization': 'Bearer ' + token, 'User-Agent': UA, 'Accept': 'application/vnd.github+json'})
    return json.load(urllib.request.urlopen(r, timeout=45))

for attempt in range(80):  # 最多 ~40 分钟
    try:
        d = api('https://api.github.com/repos/%s/actions/runs?per_page=8' % repo)
    except Exception as e:
        print('api err', e, flush=True); time.sleep(30); continue
    for run in d['workflow_runs']:
        if run['head_sha'].startswith(target_head):
            st, conc = run['status'], run['conclusion']
            print('CI status=%s conclusion=%s at %s' % (st, conc, time.strftime('%H:%M:%S')), flush=True)
            if st == 'completed':
                if conc != 'success':
                    print('CI_FAILED', flush=True); raise SystemExit(1)
                # 下载 asset（固定 release 名 qingliao-ipa-2）
                aid = None
                for rel in api('https://api.github.com/repos/%s/releases' % repo):
                    if rel['tag_name'] == 'qingliao-ipa-2':
                        for a in rel['assets']:
                            if a['name'] == 'qingliao-2.0-unsigned.ipa':
                                aid = a['id']
                if not aid:
                    print('ASSET_NOT_FOUND', flush=True); raise SystemExit(1)
                req = urllib.request.Request('https://api.github.com/repos/%s/releases/assets/%d' % (repo, aid),
                                             headers={'Authorization': 'Bearer ' + token, 'User-Agent': UA, 'Accept': 'application/octet-stream'})
                data = urllib.request.urlopen(req, timeout=180).read()
                open(OUT, 'wb').write(data)
                md5 = hashlib.md5(data).hexdigest()
                print('IPA_READY %s %s %dB' % (OUT, md5, len(data)), flush=True)
                raise SystemExit(0)
    time.sleep(30)
print('TIMEOUT', flush=True)

#!/usr/bin/env python3
"""上传 qingliao-3.0.55-unsigned.ipa 到 NAS 微信文件/轻聊app/ + chmod 644 + md5。"""
import sys, time, hashlib
try:
    import paramiko
except ImportError:
    sys.path.insert(0, '/opt/data/paramiko_old')
    import paramiko
PWD = open('/opt/data/.nas_cred').read().strip()
LOCAL = '/opt/data/qingliao-3.0.55-unsigned.ipa'
TARGET = '/volume1/docker/hermes/微信文件/轻聊app/qingliao-3.0.55-unsigned.ipa'
local_md5 = hashlib.md5(open(LOCAL,'rb').read()).hexdigest()
print('local md5:', local_md5)
c = paramiko.SSHClient()
c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
c.connect('192.168.31.40', port=22, username='lxm20060513', password=PWD, timeout=20)
data = open(LOCAL,'rb').read()
stdin, stdout, stderr = c.exec_command('cat > /tmp/ql55.ipa && wc -c /tmp/ql55.ipa')
stdin.write(data); stdin.channel.shutdown_write()
print('tmp wc:', stdout.read().decode(errors='replace').strip())
stdin, stdout, stderr = c.exec_command('sudo -s', get_pty=True)
stdin.write(PWD + '\n'); stdin.flush(); time.sleep(1.5)
chan = stdout.channel
def send(cmd, wait=1.5):
    stdin.write(cmd + '\n'); stdin.flush(); time.sleep(wait)
    out = b''
    while chan.recv_ready():
        out += chan.recv(65536)
    return out.decode(errors='replace')
print(send('whoami'))
print(send('\\cp -f /tmp/ql55.ipa "' + TARGET + '" && chmod 644 "' + TARGET + '" && md5sum "' + TARGET + '" && rm -f /tmp/ql55.ipa'))
stdin.close(); c.close()
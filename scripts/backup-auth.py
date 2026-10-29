#!/usr/bin/env python3
"""Assinatura de backup sem senha em argumentos, arquivo ou saída."""
import hashlib,hmac,os,pathlib,sys
mode,filename=sys.argv[1:3]
path=pathlib.Path(filename)
with path.open('rb') as stream:
    salt=stream.read(32)
key=hashlib.pbkdf2_hmac('sha256',os.environ['BACKUP_PASSPHRASE'].encode(),b'portaria-backup-auth-v1:'+salt,600000)
mac=hmac.new(key,digestmod='sha256')
with path.open('rb') as stream:
    for chunk in iter(lambda:stream.read(1024*1024),b''): mac.update(chunk)
signature=pathlib.Path(filename+'.hmac')
if mode=='create': signature.write_text(mac.hexdigest()+'\n')
elif mode=='check':
    if not hmac.compare_digest(mac.hexdigest(),signature.read_text().strip()): raise SystemExit('Assinatura inválida: backup alterado ou senha incorreta.')
else: raise SystemExit('Modo inválido.')

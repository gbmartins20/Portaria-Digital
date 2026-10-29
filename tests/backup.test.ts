import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
test('backup rejeita alteração do arquivo e senha incorreta antes de restaurar',()=>{
 const dir=mkdtempSync(join(tmpdir(),'portaria-backup-test-'));const file=join(dir,'test.enc');
 const env={...process.env,BACKUP_PASSPHRASE:'SOMENTE-TESTE-TEMPORARIO-NUNCA-USAR-EM-PRODUCAO'};
 const run=(mode:string,custom=env)=>spawnSync('python3',['scripts/backup-auth.py',mode,file],{env:custom,encoding:'utf8'});
 try{writeFileSync(file,crypto.getRandomValues(new Uint8Array(256)));assert.equal(run('create').status,0);assert.equal(run('check').status,0);assert.notEqual(run('check',{...env,BACKUP_PASSPHRASE:'senha-incorreta'}).status,0);const data=readFileSync(file);data[100]^=1;writeFileSync(file,data);assert.notEqual(run('check').status,0);}finally{rmSync(dir,{recursive:true,force:true});}
});

// Formato canônico descrito em docs/MIGRACAO.md. Simula por padrão.
// A senha do administrador entra por stdin e não é escrita em disco.
import {readFile} from 'node:fs/promises';
import {createClient} from '@supabase/supabase-js';
const input=process.argv[2];if(!input)throw new Error('Uso: node scripts/import-legacy.mjs caminho.json [--apply]');
const apply=process.argv.includes('--apply');const rows=JSON.parse(await readFile(input,'utf8'));
if(!Array.isArray(rows)||rows.length===0)throw new Error('O arquivo deve conter uma lista não vazia.');
const keys=new Set();
for(const [index,row] of rows.entries()){
 if(!row.source||!row.source_id||!row.record)throw new Error(`Linha ${index+1}: origem, identificador e record obrigatórios.`);
 const k=row.source+':'+row.source_id;if(keys.has(k))throw new Error(`Linha ${index+1}: ID da origem repetido.`);keys.add(k);
 for(const field of ['entry_at','exit_at']){const val=row.record[field];if(field==='entry_at'&&!val)throw new Error(`Linha ${index+1}: entrada ausente.`);if(val&&(!/T.*(?:Z|[+-]\d\d:\d\d)$/.test(val)||!Number.isFinite(Date.parse(val))))throw new Error(`Linha ${index+1}: ${field} precisa conter data, hora e fuso explícitos.`);}
}
if(process.stdin.isTTY)process.stdin.setRawMode(true);
console.log('Informe por stdin uma linha JSON com email e password do administrador (entrada oculta).');
const credentials=await new Promise(resolve=>{let text='';process.stdin.on('data',part=>{text+=part.toString();if(text.includes('\n')){if(process.stdin.isTTY)process.stdin.setRawMode(false);process.stdin.pause();resolve(JSON.parse(text.trim()));}});});
const client=createClient(process.env.SUPABASE_URL||'https://nnwuxnwjbprybyjslaob.supabase.co',process.env.SUPABASE_PUBLISHABLE_KEY||'sb_publishable_p5Z7cDWnfUgokT1lav4-SQ_DuHfs1d9',{auth:{persistSession:false}});
try{
 const login=await client.auth.signInWithPassword(credentials);if(login.error)throw new Error('Não foi possível autenticar o administrador.');
 const batch=crypto.randomUUID();let validated=0,skipped=0;
 for(let i=0;i<rows.length;i+=200){const {data,error}=await client.rpc('pd_import',{batch,rows:rows.slice(i,i+200),dry_run:!apply});if(error)throw new Error(`Lote iniciado na linha ${i+1}: ${error.message}`);validated+=data.validated;skipped+=data.skipped;}
 console.log(JSON.stringify({batch,dry_run:!apply,validated,skipped,records:rows.length}));
}finally{await client.auth.signOut();}

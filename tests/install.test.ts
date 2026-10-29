import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
test('manifesto instalável usa a mesma origem, modo aplicativo e ícones PNG válidos',async()=>{
 const root=new URL('../public/',import.meta.url);const manifest=JSON.parse(await readFile(new URL('manifest.webmanifest',root),'utf8'));
 assert.equal(manifest.display,'standalone');assert.equal(manifest.scope,'/');assert.equal(manifest.id,'/');assert.ok(manifest.start_url.startsWith('/'));assert.equal(manifest.prefer_related_applications,false);
 for(const icon of manifest.icons){const data=await readFile(new URL(icon.src.slice(1),root));assert.deepEqual([...data.subarray(0,8)],[137,80,78,71,13,10,26,10]);assert.equal(`${data.readUInt32BE(16)}x${data.readUInt32BE(20)}`,icon.sizes);}
 const html=await readFile(new URL('../index.html',import.meta.url),'utf8');assert.match(html,/rel="manifest"/);assert.match(html,/crossorigin="use-credentials"/);assert.match(html,/apple-touch-icon/);
 const apple=await readFile(new URL('app-180.png',root));assert.equal(apple.readUInt32BE(16),180);
});

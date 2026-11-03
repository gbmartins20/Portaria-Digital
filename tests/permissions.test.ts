import test from 'node:test';
import assert from 'node:assert/strict';
import {canAccess,type Profile} from '../src/domain.ts';
const operator:Profile={id:'qa',name:'QA',email:'qa@example.invalid',role:'operator',active:true};
test('operador só acessa cada seção explicitamente liberada',()=>{
 assert.equal(canAccess(operator,'greenhouse'),false);
 assert.equal(canAccess(operator,'dashboard'),false);assert.equal(canAccess(operator,'catalogs'),false);
 for(const dashboard of [false,true])for(const catalogs of [false,true])for(const greenhouse of [false,true]){
  const p={...operator,permissions:{dashboard,catalogs,greenhouse}};
  assert.equal(canAccess(p,'dashboard'),dashboard);assert.equal(canAccess(p,'catalogs'),catalogs);assert.equal(canAccess(p,'greenhouse'),greenhouse);
  assert.equal(canAccess({...p,active:false},'dashboard'),false);
  assert.equal(canAccess({...p,active:false},'catalogs'),false);assert.equal(canAccess({...p,active:false},'greenhouse'),false);
 }
});
test('administrador ativo mantém acesso completo; perfil ausente não recebe acesso',()=>{
 const p:Profile={...operator,role:'admin',permissions:{dashboard:false,catalogs:false}};
 assert.equal(canAccess(p,'greenhouse'),true);assert.equal(canAccess(p,'dashboard'),true);assert.equal(canAccess(p,'catalogs'),true);
 assert.equal(canAccess({...p,active:false},'catalogs'),false);assert.equal(canAccess({...p,active:false},'greenhouse'),false);
 assert.equal(canAccess(null,'dashboard'),false);assert.equal(canAccess(undefined,'catalogs'),false);
});

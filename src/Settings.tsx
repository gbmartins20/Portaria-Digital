import React,{useEffect,useRef,useState,type FormEvent} from 'react';
import {Camera,Trash2,LockKeyhole,Bell,Save} from 'lucide-react';
import {supabase,rpc,errorMessage,DEV_PREVIEW} from './api';
import {defaultNotifications,type Profile,type NotificationPreferences,uuid} from './domain';
import {Field,ErrorNotice} from './ui';
import {ProfileAvatar,preparePhoto} from './ProfileAvatar';
import {deviceSubscribed,enableDeviceNotifications,disableDeviceNotifications,pushSupported} from './notifications';
const categories=[['visitor','Visitantes'],['disposal','Descarte'],['material','Saída de materiais'],['service','Pessoas a serviço']] as const;
export function Settings({profile,onProfile,onToast}:{profile:Profile;onProfile:(p:Profile)=>void;onToast:(msg:string)=>void}){
 const [busy,setBusy]=useState(''),[error,setError]=useState('');const fileInput=useRef<HTMLInputElement>(null);
 const [password,setPassword]=useState(''),[confirm,setConfirm]=useState('');
 const [preferences,setPreferences]=useState<NotificationPreferences>(()=>({...defaultNotifications,...profile.notification_preferences}));
 const [subscribed,setSubscribed]=useState(false);
 useEffect(()=>{void deviceSubscribed().then(setSubscribed).catch(()=>{});},[]);
 const online=navigator.onLine;
 async function savePhoto(file:File|null){
  if(busy)return;setBusy('photo');setError('');let newPath:string|null=null;
  try{
   if(!navigator.onLine)throw new Error('Conecte-se à internet para alterar sua foto.');
   if(DEV_PREVIEW)throw new Error('O envio de fotos está disponível no aplicativo publicado.');
   if(file){const blob=await preparePhoto(file);newPath=`${profile.id}/${uuid()}.jpg`;const {error}=await supabase.storage.from('profile-photos').upload(newPath,blob,{contentType:'image/jpeg',upsert:false});if(error)throw error;}
   let saved:Profile;try{saved=await rpc<Profile>('pd_settings',{p:{avatar_path:newPath}});}catch(e){if(newPath)await supabase.storage.from('profile-photos').remove([newPath]);throw e;}
   const previous=profile.avatar_path;onProfile(saved);
   if(previous)void supabase.storage.from('profile-photos').remove([previous]);
   onToast(file?'Foto atualizada.':'Foto removida.');
  }catch(e){setError(errorMessage(e));}finally{setBusy('');if(fileInput.current)fileInput.current.value='';}
 }
 async function savePassword(e:FormEvent){
  e.preventDefault();if(busy)return;setError('');
  if(password!==confirm){setError('As senhas não coincidem.');return;}
  if(password.length<12||password.length>128){setError('Use uma senha de 12 a 128 caracteres.');return;}
  setBusy('password');try{
   if(!navigator.onLine)throw new Error('Conecte-se à internet para alterar sua senha.');
   if(!DEV_PREVIEW){const {error}=await supabase.auth.updateUser({password});if(error)throw error;}
   setPassword('');setConfirm('');onToast('Senha atualizada.');
  }catch(e){setError(errorMessage(e));}finally{setBusy('');}
 }
 async function saveNotifications(e:FormEvent){
  e.preventDefault();if(busy)return;setError('');
  if(preferences.enabled&&!categories.some(([key])=>preferences[key])){setError('Selecione pelo menos um tipo de registro.');return;}
  setBusy('notifications');try{
   if(!navigator.onLine)throw new Error('Conecte-se à internet para salvar as notificações.');
   if(preferences.enabled&&!DEV_PREVIEW){await enableDeviceNotifications();setSubscribed(true);}
   const saved=await rpc<Profile>('pd_settings',{p:{notification_preferences:preferences}});onProfile(saved);
   onToast(preferences.enabled?'Notificações ativadas e preferências salvas.':'Notificações desativadas em todos os seus aparelhos.');
  }catch(e){setError(errorMessage(e));}finally{setBusy('');}
 }
 return <div className="settings-page"><div className="page-heading"><div><div className="eyebrow">MINHA CONTA</div><h1>Configurações</h1><p>Personalize seu perfil e escolha como acompanhar a portaria.</p></div></div>
 <ErrorNotice message={error}/>{!online&&<div className="info-notice">Conecte-se à internet para alterar suas configurações.</div>}
 <div className="settings-grid"><section className="settings-card"><div className="settings-title"><Camera size={21}/><h2>Foto do perfil</h2></div><div className="settings-profile"><ProfileAvatar path={profile.avatar_path} large/><div><strong>{profile.name}</strong><span>{profile.role==='admin'?'Administrador':'Operador da portaria'}</span></div></div><p>A foto aparece ao lado da sua saudação no menu.</p>
 <input ref={fileInput} id="profile-photo" type="file" accept="image/jpeg,image/png,image/webp" className="visually-hidden" disabled={!!busy||!online} onChange={e=>{const file=e.target.files?.[0];if(file)void savePhoto(file);}}/>
 <div className="settings-actions"><button className="button secondary" disabled={!!busy||!online} onClick={()=>fileInput.current?.click()}><Camera size={17}/>{busy==='photo'?'Salvando…':'Escolher foto'}</button>{profile.avatar_path&&<button className="text-button" disabled={!!busy||!online} onClick={()=>void savePhoto(null)}><Trash2 size={16}/>Remover foto</button>}</div><small>JPG, PNG ou WebP · até 5 MB. A imagem será ajustada ao centro.</small></section>
 <section className="settings-card"><div className="settings-title"><LockKeyhole size={21}/><h2>Alterar senha</h2></div><form onSubmit={savePassword}><Field label="Nova senha" required hint="Use de 12 a 128 caracteres."><input type="password" autoComplete="new-password" minLength={12} maxLength={128} value={password} onChange={e=>setPassword(e.target.value)} required/></Field><Field label="Confirmar nova senha" required><input type="password" autoComplete="new-password" minLength={12} maxLength={128} value={confirm} onChange={e=>setConfirm(e.target.value)} required/></Field><button className="button" disabled={!!busy||!online}><Save size={17}/>{busy==='password'?'Atualizando…':'Atualizar senha'}</button></form></section>
 {profile.role==='admin'&&<section className="settings-card settings-notifications"><div className="settings-title"><Bell size={21}/><h2>Notificações de novas entradas</h2></div><p>Escolha quais registros você quer acompanhar. Esta preferência é só sua.</p><form onSubmit={saveNotifications}>
 <label className="settings-switch"><input type="checkbox" checked={preferences.enabled} onChange={e=>setPreferences(p=>({...p,enabled:e.target.checked}))}/><span><strong>Receber notificações</strong><small>Alertas no celular ou computador, mesmo com o aplicativo fechado.</small></span></label>
 <fieldset className="notification-categories" disabled={!preferences.enabled||!!busy}><legend>Quais registros deseja receber?</legend>{categories.map(([key,label])=><label key={key}><input type="checkbox" checked={preferences[key]} onChange={e=>setPreferences(p=>({...p,[key]:e.target.checked}))}/>{label}</label>)}</fieldset>
 <div className="notification-rule"><strong>Somente entradas registradas online</strong><p>Saídas, edições e registros guardados offline não geram alertas. Ao reconectar, a sincronização acontece sem notificações atrasadas.</p></div>
 <p className="device-status">{subscribed?'Este aparelho está habilitado para receber alertas.':DEV_PREVIEW?'Demonstração: nenhum alerta será enviado.':pushSupported()?'Ao salvar com as notificações ativadas, permita os alertas neste navegador.':'Seu navegador não oferece notificações. No iPhone, adicione o aplicativo à Tela de Início e abra por esse ícone.'}</p>
 <div className="settings-actions"><button className="button" disabled={!!busy||!online}><Bell size={17}/>{busy==='notifications'?'Salvando…':'Salvar notificações'}</button>{subscribed&&<button type="button" className="text-button" disabled={!!busy||!online} onClick={async()=>{setBusy('device');setError('');try{await disableDeviceNotifications();setSubscribed(false);onToast('Alertas desativados neste aparelho.');}catch(e){setError(errorMessage(e));}finally{setBusy('');}}}>Desativar neste aparelho</button>}</div></form></section>}
 </div></div>;
}

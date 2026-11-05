import React,{useEffect,useState} from 'react';
import {UserRound} from 'lucide-react';
import {supabase} from './api';
const urls=new Map<string,{until:number;promise:Promise<string>}>();
function photoURL(path:string){
 const cached=urls.get(path);if(cached&&cached.until>Date.now())return cached.promise;
 const promise=supabase.storage.from('profile-photos').createSignedUrl(path,3600).then(({data,error})=>{if(error)throw error;return data.signedUrl;});
 urls.set(path,{until:Date.now()+3000000,promise});promise.catch(()=>urls.delete(path));return promise;
}
export function ProfileAvatar({path,large=false}:{path?:string|null;large?:boolean}){
 const [image,setImage]=useState<{path:string;url:string}|null>(null);
 useEffect(()=>{let live=true;if(path)void photoURL(path).then(url=>{if(live)setImage({path,url});}).catch(()=>{if(live)setImage(null);});return()=>{live=false;};},[path]);
 return <span className={`profile-avatar${large?' large':''}`} aria-label="Foto do perfil">{path&&image?.path===path?<img src={image.url} alt="" onError={()=>setImage(null)}/>:<UserRound size={large?36:23} aria-hidden="true"/>}</span>;
}
export async function preparePhoto(file:File){
 if(!['image/jpeg','image/png','image/webp'].includes(file.type))throw new Error('Escolha uma imagem JPG, PNG ou WebP.');
 if(file.size>5*1024*1024)throw new Error('Escolha uma foto de até 5 MB.');
 const bitmap=await createImageBitmap(file);
 try{
  const canvas=document.createElement('canvas');canvas.width=512;canvas.height=512;
  const context=canvas.getContext('2d');if(!context)throw new Error('Não foi possível preparar a foto.');
  const side=Math.min(bitmap.width,bitmap.height);
  context.fillStyle='#fff';context.fillRect(0,0,512,512);
  context.drawImage(bitmap,(bitmap.width-side)/2,(bitmap.height-side)/2,side,side,0,0,512,512);
  return await new Promise<Blob>((resolve,reject)=>canvas.toBlob(b=>b?resolve(b):reject(new Error('Não foi possível preparar a foto.')),'image/jpeg',.86));
 }finally{bitmap.close();}
}

// Only browser push providers can be contacted; redirects are disabled as well.
export function allowedPushEndpoint(endpoint:string){
 try{
  const u=new URL(endpoint);
  return u.protocol==='https:'&&!u.username&&!u.password&&!u.port&&(
   u.hostname==='fcm.googleapis.com'||u.hostname==='updates.push.services.mozilla.com'||
   /^[a-z0-9-]+\.push\.services\.mozilla\.com$/.test(u.hostname)||
   /^[a-z0-9.-]+\.notify\.windows\.com$/.test(u.hostname)||
   /^[a-z0-9.-]+\.push\.apple\.com$/.test(u.hostname));
 }catch{return false;}
}

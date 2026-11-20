// Tirsdagsklubben service worker: viser birdie-beskeder (push). Gemmer intet, så appen altid er den nyeste.
self.addEventListener("install",()=>self.skipWaiting());
self.addEventListener("activate",e=>e.waitUntil(self.clients.claim()));
self.addEventListener("push",e=>{
  let d={};try{d=e.data?e.data.json():{}}catch(_){d={body:e.data&&e.data.text()}}
  e.waitUntil(self.registration.showNotification(d.title||"Tirsdagsklubben",{
    body:d.body||"",tag:d.tag,icon:"icon-180.png?v=4",badge:"icon-180.png?v=4",data:{url:"./#live"}}));
});
self.addEventListener("notificationclick",e=>{
  e.notification.close();const url=(e.notification.data&&e.notification.data.url)||"./";
  e.waitUntil(self.clients.matchAll({type:"window",includeUncontrolled:true}).then(cs=>{
    for(const c of cs){if("focus" in c)return c.focus()}
    return self.clients.openWindow(url);
  }));
});

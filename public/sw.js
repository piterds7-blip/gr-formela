const CACHE_NAME='grformela-v7';
const ASSETS=['./index.html','./manifest.json','./icon-192.png','./icon-512.png','./icon-512-maskable.png','./apple-touch-icon.png','./favicon-32.png'];
const CDN=[
  'https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/Chart.js/4.4.1/chart.umd.min.js',
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js',
  'https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore-compat.js'
];
self.addEventListener('install',e=>{
  e.waitUntil(caches.open(CACHE_NAME).then(c=>c.addAll(ASSETS).then(()=>Promise.all(CDN.map(u=>
    fetch(u,{mode:'cors'}).then(r=>r.ok?c.put(u,r):null).catch(()=>null))))));
  self.skipWaiting();
});
self.addEventListener('activate',e=>{
  e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x.startsWith('grformela-')&&x!==CACHE_NAME).map(x=>caches.delete(x)))));
  self.clients.claim();
});
self.addEventListener('fetch',e=>{
  if(e.request.method!=='GET')return;
  const url=new URL(e.request.url);
  if(CDN.includes(e.request.url)){
    e.respondWith(caches.match(e.request).then(c=>c||fetch(e.request).then(r=>{const cl=r.clone();caches.open(CACHE_NAME).then(ca=>ca.put(e.request,cl));return r})));
    return;
  }
  if(url.origin!==location.origin)return; // Firebase/Firestore idą bezpośrednio do sieci
  e.respondWith(fetch(e.request).then(r=>{const cl=r.clone();caches.open(CACHE_NAME).then(ca=>ca.put(e.request,cl));return r}).catch(()=>caches.match(e.request)));
});

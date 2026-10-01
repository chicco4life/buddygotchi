// Loopback-only static review server; no external binding or host integration.
const http=require('node:http'),fs=require('node:fs'),path=require('node:path');
if(process.argv.includes('--help')){console.log('node tools/serve.cjs [--port 4190]\nServes this package on 127.0.0.1; / opens preview/index.html.');process.exit(0);}
const args=process.argv.slice(2);
if(args.some((v,i)=>v!=='--port'&&args[i-1]!=='--port')||args.filter(v=>v==='--port').length>1)throw Error('Use --help for arguments.');
const port=args.includes('--port')?Number(args[args.indexOf('--port')+1]):4190;
if(!Number.isInteger(port)||port<1024||port>65535)throw Error('Port must be an integer between 1024 and 65535.');
const root=path.resolve(__dirname,'..');
const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.md':'text/plain; charset=utf-8'};
http.createServer((req,res)=>{
  if(!['GET','HEAD'].includes(req.method)){res.writeHead(405);res.end();return;}
  let name;
  try{name=decodeURIComponent(new URL(req.url,'http://localhost').pathname);}catch{res.writeHead(400);res.end();return;}
  if(name.endsWith('/favicon.ico')){res.writeHead(204);res.end();return;}
  if(name==='/'){res.writeHead(302,{'Location':'/preview/index.html'});res.end();return;}
  const file=path.resolve(root,'.'+name);
  if(!file.startsWith(root+path.sep)){res.writeHead(403);res.end();return;}
  fs.readFile(file,(error,data)=>{
    if(error){res.writeHead(404);res.end('Not found');return;}
    res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
    res.end(req.method==='HEAD'?undefined:data);
  });
}).listen(port,'127.0.0.1',()=>console.log('VideoG Slime Blob: http://127.0.0.1:'+port+'/'));

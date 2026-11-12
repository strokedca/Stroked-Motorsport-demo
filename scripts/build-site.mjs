import {readFile,writeFile,mkdir,rm} from 'node:fs/promises';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';

const root=fileURLToPath(new URL('../',import.meta.url));
export const siteFiles=Object.freeze(['index.html','events-logo-1.png','clothing-apparel-logo.png','assets/stroked-config.js','assets/stroked-core.js','assets/stroked-live.js','assets/stroked-live.css','assets/stroked-payments-config.js','assets/stroked-support.js','assets/stroked-support.css','assets/stroked-promotions.js','assets/stroked-promotions.css','assets/stroked-information.js','assets/stroked-information.css','assets/stroked-sales-pitch.js','assets/stroked-pricing.js','assets/stroked-pricing.css','assets/stroked-pages.css','assets/stroked-pages-nav.js','assets/stroked-tour.js','about.html','how-it-works.html','motorsports.html','clothing-apparel.html','contact.html']);

export function resolveBuildMode(branch=process.env.CF_PAGES_BRANCH,requested=process.env.STROKED_BUILD_MODE){
  const mode=requested||(branch==='main'?'production':'testing');
  if(!['production','testing'].includes(mode))throw new Error('Build mode must be production or testing');
  if(branch&&mode!==(branch==='main'?'production':'testing'))throw new Error('Build mode does not match the Cloudflare branch');
  return mode;
}

function replaceOnce(source,pattern,after){
  if((source.match(new RegExp(pattern.source,'g'))||[]).length!==1)throw new Error('Release source changed; review the build replacement: '+pattern);
  return source.replace(pattern,after);
}

export async function buildSite({mode='testing',outDir=join(root,'dist')}={}){
  if(!['production','testing'].includes(mode))throw new Error('Unknown build mode');
  const output=resolve(outDir);
  if(output===resolve(root)||output===dirname(output))throw new Error('Refusing to replace the source directory');
  const contents=new Map();
  for(const path of siteFiles)contents.set(path,await readFile(join(root,path)));
  {
    let html=contents.get('index.html').toString('utf8');
    html=replaceOnce(html,/<title>Stroked Motorsports Events<\/title>/,'<title>Stroked Motorsports Events'+(mode==='testing'?' — Testing Release':'')+'</title>');
    html=replaceOnce(html,/<header>/,'<header>'+(mode==='testing'?'<span class="tag">TESTING RELEASE</span>':''));
    html=replaceOnce(html,/<meta name="robots" content="index, follow">/,'<meta name="robots" content="'+(mode==='testing'?'noindex, nofollow':'index, follow')+'">');
    contents.set('index.html',Buffer.from(html));
    let config=contents.get('assets/stroked-config.js').toString('utf8');
    config=replaceOnce(config,/rpcPrefix: '(?:stroked_v55_|stroked_live_v55_)'/,"rpcPrefix: '"+(mode==='production'?'stroked_live_v55_':'stroked_v55_')+"'");
    config=replaceOnce(config,/testing: (?:true|false)/,'testing: '+(mode==='testing'));
    contents.set('assets/stroked-config.js',Buffer.from(config));
  }
  contents.set('robots.txt',mode==='production'?await readFile(join(root,'robots.txt')):Buffer.from('User-agent: *\nDisallow: /\n'));
  if(mode==='production')contents.set('sitemap.xml',await readFile(join(root,'sitemap.xml')));
  const csp="default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://*.stripe.com https://*.link.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://*.supabase.co https://*.stripe.com https://*.link.com; connect-src 'self' https://*.supabase.co wss://*.supabase.co https://*.stripe.com https://*.link.com; frame-src https://*.stripe.com https://*.link.com; font-src 'self' data:; object-src 'none'; base-uri 'self'; form-action 'self' https://*.stripe.com https://*.link.com";
  contents.set('_headers',Buffer.from('/*\n  Cache-Control: no-cache\n  X-Content-Type-Options: nosniff\n  Referrer-Policy: same-origin\n  Content-Security-Policy: '+csp+'\n'+(mode==='testing'?'  X-Robots-Tag: noindex, nofollow\n':'')));
  const manifest={version:'5.5.5',mode,rpcPrefix:mode==='production'?'stroked_live_v55_':'stroked_v55_',files:Object.fromEntries([...contents].map(([path,bytes])=>[path,createHash('sha256').update(bytes).digest('hex')]))};
  contents.set('release-manifest.json',Buffer.from(JSON.stringify(manifest,null,2)+'\n'));
  // dist is generated output; historical clients, SQL, tests and credentials are never copied.
  await rm(output,{recursive:true,force:true});await mkdir(output,{recursive:true});
  for(const [path,bytes] of contents){await mkdir(dirname(join(output,path)),{recursive:true});await writeFile(join(output,path),bytes);}
  return manifest;
}

if(process.argv[1]&&pathToFileURL(resolve(process.argv[1])).href===import.meta.url){
  const mode=resolveBuildMode(process.env.CF_PAGES_BRANCH,process.argv[2]||process.env.STROKED_BUILD_MODE);
  await buildSite({mode});process.stdout.write('Built '+mode+' website in dist/\n');
}

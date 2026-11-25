import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {buildSite,siteFiles} from '../scripts/build-site.mjs';

test('entry pages use content-specific asset URLs, including different preview configuration',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'stroked-cache-'));
  const configurations=[];
  try{
    for(const mode of ['production','testing']){
      await buildSite({mode,outDir:dir});
      for(const file of siteFiles.filter(file=>file.endsWith('.html'))){
        const html=await readFile(join(dir,file),'utf8');
        for(const match of html.matchAll(/\b(?:src|href)="(\/?assets\/[^\"]+\.(?:js|css)\?[^\"]+)"/g)){
          const url=new URL(match[1],'https://stroked.ca/'),path=url.pathname.slice(1);
          const expected=createHash('sha256').update(await readFile(join(dir,path))).digest('hex').slice(0,12);
          assert.equal(url.searchParams.get('v'),expected,file+': '+path);
          if(file==='index.html'&&path==='assets/stroked-config.js')configurations.push(expected);
        }
        assert.doesNotMatch(html,/\b(?:src|href)="\/?assets\/[^"?]+\.(?:js|css)"/,'no unversioned first-party code remains');
      }
    }
    assert.equal(configurations.length,2);assert.notEqual(configurations[0],configurations[1]);
  }finally{await rm(dir,{recursive:true,force:true});}
});

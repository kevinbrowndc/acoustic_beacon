import {readdir} from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
for (const name of await readdir(new URL('../src/', import.meta.url))) {
  if (!name.endsWith('.js')) continue;
  const result=spawnSync(process.execPath,['--check',fileURLToPath(new URL(`../src/${name}`,import.meta.url))],{stdio:'inherit'});
  if(result.status)process.exit(result.status);
}
console.log('JavaScript syntax checks passed.');

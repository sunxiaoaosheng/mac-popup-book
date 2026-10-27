#!/usr/bin/env python3
"""Editor-neutral page development commands. A page never modifies host package registration."""
import argparse,json,pathlib,re,shutil,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
def run(args):subprocess.run(args,cwd=ROOT,check=True)
def pages():
 result=[]
 for path in sorted((ROOT/'Scenes').glob('*/page.json')):
  try:
   data=json.loads(path.read_text());assert data['id']==path.parent.name and data['contractVersion']==1
   result.append(data)
  except Exception as e:print('已隔离无效开发描述：',path,e,file=sys.stderr)
 return result
parser=argparse.ArgumentParser(description='场景开发与集成命令')
parser.add_argument('action',choices=['list','check','build','preview','new'])
parser.add_argument('page',nargs='?');args=parser.parse_args()
if args.action=='list':print(json.dumps([p['id']for p in pages()]))
else:
 id=args.page
 if not id or not re.fullmatch('[a-z][a-z0-9-]{0,63}',id):parser.error('请提供合法场景标识')
 package=ROOT/'Scenes'/id
 if args.action=='new':
  if package.exists():raise SystemExit('场景目录已存在，不覆盖')
  shutil.copytree(ROOT/'Templates/Page',package)
  for file in package.rglob('*'):
   if file.is_file():file.write_text(file.read_text().replace('__PAGE_ID__',id).replace('__SERVICE_ID__','local.ssr.forestbook.page.'+id))
  print('已创建独立场景：',package)
 else:
  if id not in [p['id']for p in pages()]:raise SystemExit('场景描述不可用')
  if args.action=='check':
   run(['swift','test','--package-path',str(package)])
   run(['python3','scripts/check-boundaries.py'])
   if (package/'Tests/AudioPipelineTests').is_dir():run(['python3','-m','unittest','discover','-s',str(package/'Tests/AudioPipelineTests')])
  else:
   run(['python3','scripts/book-build.py','--preview','--pages',id])
   if args.action=='preview':run(['open',str(ROOT/'build/场景预览.app')])

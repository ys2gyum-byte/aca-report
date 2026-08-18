#!/usr/bin/env bash
# 성적표 생성기 배포 — 한 줄이면 끝납니다.
#
#   ./deploy.sh "무엇을 바꿨는지 한 줄"
#
# 하는 일: (1) 변경사항을 로컬 git에 기록하고  (2) public 폴더를 Netlify에 바로 올립니다.
# GitHub 은 쓰지 않습니다. 되돌리고 싶으면 git 기록으로 언제든 복구할 수 있습니다.
#
# 준비 (처음 한 번만): Netlify 개인 토큰을 맥 키체인에 넣어 둡니다.
#   security add-generic-password -a "$USER" -s report-netlify -w
#   (토큰은 app.netlify.com → User settings → Applications → Personal access tokens 에서 발급)

set -euo pipefail
cd "$(dirname "$0")"

MSG="${1:-성적표 생성기 업데이트}"
SITE_FILE=".netlify-site"
SITE_NAME="${SITE_NAME:-}"          # 첫 배포 때 쓸 주소. 예: SITE_NAME=aca-report ./deploy.sh "첫 배포"

kc() { security find-generic-password -a "$USER" -s "$1" -w 2>/dev/null || true; }
TOKEN="${NETLIFY_AUTH_TOKEN:-$(kc report-netlify)}"
[ -n "$TOKEN" ] || { echo "✗ Netlify 토큰이 없습니다."; echo "  security add-generic-password -a \"\$USER\" -s report-netlify -w  로 먼저 등록해 주세요."; exit 1; }

# ---------- 1. 로컬 git 기록 ----------
if [ -d .git ] && [ -n "$(git status --porcelain)" ]; then
  git add -A && git commit -q -m "$MSG" && echo "✓ 기록: $MSG"
fi

# ---------- 2. 업로드 ----------
SITE_ID="$([ -f "$SITE_FILE" ] && cat "$SITE_FILE" || echo '')"

NEW_ID=$(NF_TOKEN="$TOKEN" NF_SITE="$SITE_ID" NF_NAME="$SITE_NAME" node - <<'NODE'
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const TOKEN=process.env.NF_TOKEN, API='https://api.netlify.com/api/v1';
const H={Authorization:'Bearer '+TOKEN};
const log=m=>process.stderr.write(m+'\n');

async function api(p,opt={}){
  const r=await fetch(API+p,{...opt,headers:{...H,...(opt.headers||{})}});
  if(!r.ok)throw new Error(`${opt.method||'GET'} ${p} → ${r.status} ${(await r.text()).slice(0,200)}`);
  return r.headers.get('content-type')?.includes('json')?r.json():r.text();
}
function walk(dir,base=dir,out=[]){
  for(const e of fs.readdirSync(dir,{withFileTypes:true})){
    if(e.name==='.DS_Store')continue;
    const f=path.join(dir,e.name);
    e.isDirectory()?walk(f,base,out):out.push('/'+path.relative(base,f).split(path.sep).join('/'));
  }
  return out;
}
(async()=>{
  let siteId=process.env.NF_SITE;
  if(!siteId){
    const name=process.env.NF_NAME;
    if(!name){log('✗ 첫 배포입니다. 원하는 주소를 정해 주세요:\n  SITE_NAME=원하는이름 ./deploy.sh "첫 배포"   → 원하는이름.netlify.app');process.exit(1)}
    log(`· 새 사이트를 만듭니다: ${name}.netlify.app`);
    const s=await api('/sites',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({name})});
    siteId=s.id; log('✓ 사이트 생성 완료');
  }
  // 파일 목록 + 해시
  const paths=walk('public');
  const digests={},bodies={};
  for(const p of paths){
    const buf=fs.readFileSync('public'+p);
    const sha=crypto.createHash('sha1').update(buf).digest('hex');
    digests[p]=sha; (bodies[sha]=bodies[sha]||[]).push({p,buf});
  }
  log(`· 파일 ${paths.length}개 (${paths.join(', ')})`);
  const dep=await api(`/sites/${siteId}/deploys`,{method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({files:digests,async:false})});
  const need=dep.required||[];
  log(`· 업로드 대상 ${need.length}개`);
  for(const sha of need){
    for(const {p,buf} of (bodies[sha]||[])){
      const r=await fetch(`${API}/deploys/${dep.id}/files${p}`,{method:'PUT',
        headers:{...H,'Content-Type':'application/octet-stream'},body:buf});
      if(!r.ok)throw new Error(`업로드 실패 ${p} → ${r.status} ${(await r.text()).slice(0,200)}`);
      log(`  ↑ ${p}`);
    }
  }
  // 완료 대기
  for(let i=0;i<40;i++){
    const d=await api(`/deploys/${dep.id}`);
    if(d.state==='ready'){log('✓ 배포 완료 → '+(d.ssl_url||d.url||''));break}
    if(d.state==='error'){log('✗ 배포 실패: '+(d.error_message||''));process.exit(1)}
    await new Promise(r=>setTimeout(r,2000));
  }
  // 첫 배포였다면 사이트 id 를 표준출력으로 넘겨 저장
  if(!process.env.NF_SITE)process.stdout.write(siteId);
  // 접근 제한 상태 안내
  try{
    const s=await api('/sites/'+siteId);
    if(s.account_sso_login)log('⚠ 이 사이트는 Netlify 로그인(SSO)이 걸려 있어 공동작업자가 못 들어옵니다.\n  app.netlify.com → 사이트 → Site configuration → Access & security → Visitor access 에서 해제하세요.');
  }catch(e){}
})().catch(e=>{log('✗ '+e.message);process.exit(1)});
NODE
)

if [ -n "$NEW_ID" ] && [ ! -f "$SITE_FILE" ]; then
  echo "$NEW_ID" > "$SITE_FILE"
fi

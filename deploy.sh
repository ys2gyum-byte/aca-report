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
[ -n "$TOKEN" ] || TOKEN="$(kc gyumhub-netlify)"
[ -n "$TOKEN" ] || { echo "✗ Netlify 토큰이 없습니다."; echo "  security add-generic-password -a \"\$USER\" -s report-netlify -w  로 먼저 등록해 주세요."; exit 1; }

api() { curl -sf -H "Authorization: Bearer $TOKEN" "$@"; }

# ---------- 1. 로컬 git 기록 ----------
if [ -d .git ] && [ -n "$(git status --porcelain)" ]; then
  git add -A && git commit -q -m "$MSG" && echo "✓ 기록: $MSG"
fi

# ---------- 2. 사이트 확인 (없으면 새로 만듦) ----------
if [ -f "$SITE_FILE" ]; then
  SITE_ID="$(cat "$SITE_FILE")"
else
  [ -n "$SITE_NAME" ] || { echo "✗ 첫 배포입니다. 원하는 주소를 정해 주세요:"; echo "  SITE_NAME=원하는이름 ./deploy.sh \"첫 배포\"   → 원하는이름.netlify.app"; exit 1; }
  echo "· 새 사이트를 만듭니다: ${SITE_NAME}.netlify.app"
  SITE_ID=$(api -X POST -H "Content-Type: application/json" \
    -d "{\"name\":\"${SITE_NAME}\"}" https://api.netlify.com/api/v1/sites \
    | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>console.log(JSON.parse(d).id))')
  [ -n "$SITE_ID" ] || { echo "✗ 사이트 생성 실패 (이름이 이미 쓰이고 있을 수 있습니다)"; exit 1; }
  echo "$SITE_ID" > "$SITE_FILE"
  echo "✓ 사이트 생성 완료"
fi

# ---------- 3. public 폴더를 압축해서 올리기 ----------
ZIP="$(mktemp -t rcard).zip"
( cd public && zip -qr "$ZIP" . )
echo -n "· 업로드 중"
RES=$(curl -sf -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/zip" \
      --data-binary "@$ZIP" "https://api.netlify.com/api/v1/sites/${SITE_ID}/deploys")
rm -f "$ZIP"
DEPLOY_ID=$(echo "$RES" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>console.log(JSON.parse(d).id))')

# ---------- 4. 배포 완료 대기 ----------
for _ in $(seq 1 40); do
  STATE=$(api "https://api.netlify.com/api/v1/deploys/${DEPLOY_ID}" \
    | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{const j=JSON.parse(d);console.log(j.state+" "+(j.ssl_url||j.url||""))})')
  set -- $STATE
  case "$1" in
    ready) echo; echo "✓ 배포 완료 → ${2:-https://app.netlify.com}"; exit 0 ;;
    error) echo; echo "✗ 배포 실패 — https://app.netlify.com/sites 에서 확인해 주세요"; exit 1 ;;
  esac
  echo -n "."
  sleep 2
done
echo; echo "⚠ 시간이 걸리고 있습니다 — https://app.netlify.com/sites 에서 확인해 주세요"

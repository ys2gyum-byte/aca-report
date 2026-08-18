#!/usr/bin/env bash
# 성적표 생성기 배포 (GitHub Pages) — 한 줄이면 끝납니다.
#
#   ./deploy.sh "무엇을 바꿨는지 한 줄"
#
# 하는 일: (1) 로컬 git 에 기록 → (2) GitHub 저장소에 소스 백업 → (3) 사이트 파일을 gh-pages 로 올림
# GitHub Pages 는 배포 횟수 제한이 없습니다.
#
# 준비 (처음 한 번만): GitHub 토큰을 맥 키체인에 넣어 둡니다.
#   security add-generic-password -a "$USER" -s report-github -w
#   (토큰은 github.com → Settings → Developer settings → Personal access tokens (classic) → repo 권한)

set -euo pipefail
cd "$(dirname "$0")"

MSG="${1:-성적표 생성기 업데이트}"
REPO_NAME="${REPO_NAME:-aca-report}"

kc() { security find-generic-password -a "$USER" -s "$1" -w 2>/dev/null || true; }
TOKEN="${GITHUB_TOKEN:-$(kc report-github)}"
[ -n "$TOKEN" ] || { echo "✗ GitHub 토큰이 없습니다."; echo "  security add-generic-password -a \"\$USER\" -s report-github -w  로 먼저 등록해 주세요."; exit 1; }

gh() { curl -sf -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json" "$@"; }

OWNER=$(gh https://api.github.com/user | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).login')
[ -n "$OWNER" ] || { echo "✗ 토큰이 유효하지 않습니다 (GitHub 로그인 확인 실패)"; exit 1; }

# ---------- 1. 로컬 기록 ----------
if [ -d .git ] && [ -n "$(git status --porcelain)" ]; then
  git add -A && git commit -q -m "$MSG" && echo "✓ 기록: $MSG"
fi

# ---------- 2. 저장소 확인 (없으면 생성) ----------
if ! gh "https://api.github.com/repos/${OWNER}/${REPO_NAME}" >/dev/null 2>&1; then
  echo "· 저장소를 만듭니다: ${OWNER}/${REPO_NAME}"
  gh -X POST -d "{\"name\":\"${REPO_NAME}\",\"private\":false,\"description\":\"입반테스트 성적표·코멘트 생성기\",\"has_issues\":false,\"has_wiki\":false}" \
     https://api.github.com/user/repos >/dev/null
  echo "✓ 저장소 생성 완료"
fi
REMOTE="https://x-access-token:${TOKEN}@github.com/${OWNER}/${REPO_NAME}.git"

# ---------- 3. 소스 백업 (main) ----------
git push -q --force "$REMOTE" HEAD:main 2>&1 | sed 's/gh[a-z]_[A-Za-z0-9_]*/***/g' || true
echo "✓ 소스 백업 → github.com/${OWNER}/${REPO_NAME}"

# ---------- 4. 사이트 파일 업로드 (gh-pages) ----------
TMP=$(mktemp -d)
cp -R public/. "$TMP"/
STAMP=$(date "+%Y-%m-%d %H:%M")
/usr/bin/sed -i '' "s/__BUILD__/${STAMP}/" "$TMP/index.html"
touch "$TMP/.nojekyll"                       # _로 시작하는 파일도 그대로 서빙
(
  cd "$TMP"
  git init -q
  git add -A
  git -c user.name="deploy" -c user.email="deploy@local" commit -q -m "$MSG"
  git push -q --force "$REMOTE" HEAD:gh-pages 2>&1 | sed 's/gh[a-z]_[A-Za-z0-9_]*/***/g'
)
rm -rf "$TMP"
echo "✓ 사이트 업로드 완료 (gh-pages)"

# ---------- 5. Pages 설정 ----------
if ! gh "https://api.github.com/repos/${OWNER}/${REPO_NAME}/pages" >/dev/null 2>&1; then
  gh -X POST -d '{"source":{"branch":"gh-pages","path":"/"}}' \
     "https://api.github.com/repos/${OWNER}/${REPO_NAME}/pages" >/dev/null && echo "✓ GitHub Pages 켬"
fi

URL="https://${OWNER}.github.io/${REPO_NAME}/"
# 주소가 응답하는지가 아니라, 방금 올린 내용이 실제로 나오는지 확인합니다 (보통 1~2분)
echo -n "· 실제 반영 확인 중"
for _ in $(seq 1 60); do
  if curl -s -H 'Cache-Control: no-cache' "$URL" | grep -q "$STAMP"; then
    echo; echo "✓ 배포 완료 (버전 ${STAMP}) → $URL"
    echo "  화면이 그대로면 브라우저에서 ⌘+Shift+R 로 새로고침하세요."
    exit 0
  fi
  echo -n "."
  sleep 5
done
echo; echo "⚠ 3분이 지나도 반영되지 않았습니다 — 잠시 후 $URL 을 다시 열어보세요."
echo "  확인 방법: 앱 → ☁︎ 공유 설정 → '이 화면의 버전'이 ${STAMP} 인지 보세요."
exit 1

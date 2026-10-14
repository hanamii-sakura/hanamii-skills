#!/usr/bin/env bash
# hanamii に ZIP で公開する（新規作成 or 再デプロイ）。curl / python3 / zip だけで動く。
# 通常は公式 CLI `npx -y hanamii deploy` を使う。このスクリプトは Node.js が無い環境向けの代替。
# 使い方:
#   hanamii-deploy.sh --name my-app [--workspace <workspace-id>] [--env "K=V,K2=V2"] [--dir .]
#   hanamii-deploy.sh --project <project-id> [--env "K=V"] [--dir .]   # ID は UUID
# 必要: 環境変数 HANAMII_TOKEN（hnm_ で始まる）。正本の仕様: https://hanamii.jp/docs/public-api.md
set -euo pipefail

BASE_URL="${HANAMII_BASE_URL:-https://hanamii.jp}"
NAME=""; PROJECT=""; WORKSPACE=""; ENVS=""; DIR="."; TIMEOUT="${HANAMII_DEPLOY_TIMEOUT:-900}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2;;
    --project) PROJECT="$2"; shift 2;;
    --workspace) WORKSPACE="$2"; shift 2;;
    --env) ENVS="$2"; shift 2;;
    --dir) DIR="$2"; shift 2;;
    -h|--help) sed -n 2,7p "$0"; exit 0;;
    *) echo "不明な引数: $1" >&2; exit 2;;
  esac
done

if [[ -z "${HANAMII_TOKEN:-}" ]]; then
  echo "HANAMII_TOKEN が未設定です。https://hanamii.jp/account/settings/tokens でトークンを発行し、export HANAMII_TOKEN=hnm_... を設定してください" >&2
  exit 3
fi
if [[ -z "$NAME" && -z "$PROJECT" ]]; then echo "--name か --project のどちらかが必要です" >&2; exit 2; fi
for cmd in curl python3 zip; do command -v "$cmd" >/dev/null || { echo "$cmd が見つかりません" >&2; exit 4; }; done

AUTH=(-H "Authorization: Bearer $HANAMII_TOKEN")
JSON=(-H "Content-Type: application/json")
jget() { python3 -c 'import json,sys; d=json.load(sys.stdin)
for k in sys.argv[1].split("."):
    d = d[int(k)] if isinstance(d, list) else d.get(k)
    if d is None: break
print("" if d is None else (json.dumps(d, ensure_ascii=False) if isinstance(d,(dict,list)) else d))' "$1"; }

# 0. 言語判定ファイルの確認
cd "$DIR"
if [[ -f package.json ]]; then
  python3 - <<'PY' || exit 5
import json,sys
p=json.load(open("package.json")); s=p.get("scripts",{})
if "start" not in s: print("package.json に scripts.start がありません（例: \"start\": \"next start\"）", file=sys.stderr); sys.exit(1)
if "dev" in s.get("start",""): print("scripts.start が開発用コマンドです。本番用（next start / node server.js など）にしてください", file=sys.stderr); sys.exit(1)
PY
elif [[ ! -f requirements.txt && ! -f pyproject.toml && ! -f composer.json ]]; then
  echo "言語を判定するファイルがありません（package.json / requirements.txt / pyproject.toml / composer.json）" >&2; exit 5
fi

# 1. ZIP を作る（不要物を除外）
ZIP="$(mktemp -t hanamii-XXXXXX).zip"
zip -q -r "$ZIP" . -x "node_modules/*" "*/node_modules/*" ".next/*" "dist/*" "build/*" ".git/*" ".env" ".env.*" "vendor/*" "__pycache__/*" "*/__pycache__/*" ".venv/*" "venv/*" "__MACOSX/*" ".DS_Store" "*.zip"
echo "ZIP: $ZIP ($(du -h "$ZIP" | cut -f1))"

# 2. ワークスペースを決める
if [[ -z "$WORKSPACE" && -z "$PROJECT" ]]; then
  WS_JSON=$(curl -sS "${AUTH[@]}" "$BASE_URL/api/v1/workspaces")
  COUNT=$(printf '%s' "$WS_JSON" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("workspaces",[])))')
  if [[ "$COUNT" == "1" ]]; then
    WORKSPACE=$(printf '%s' "$WS_JSON" | jget workspaces.0.id)
  elif [[ "$COUNT" == "0" ]]; then
    WORKSPACE=""  # workspace スコープのトークンは指定不要
  else
    echo "ワークスペースが複数あります。--workspace で指定してください:" >&2
    printf '%s' "$WS_JSON" | python3 -c 'import json,sys
for w in json.load(sys.stdin)["workspaces"]: print(" ", w.get("id"), w.get("name",""))' >&2
    exit 6
  fi
fi
if [[ -n "$PROJECT" && -z "$WORKSPACE" ]]; then
  WORKSPACE=$(curl -sS "${AUTH[@]}" "$BASE_URL/api/v1/projects/$PROJECT" | jget project.workspaceId)
fi
WS_FIELD=""; [[ -n "$WORKSPACE" ]] && WS_FIELD="\"workspaceId\": \"$WORKSPACE\","

# 3. アップロード URL を発行して PUT
UP=$(curl -sS -X POST "${AUTH[@]}" "${JSON[@]}" "$BASE_URL/api/v1/uploads" \
  --data "{ $WS_FIELD \"fileName\": \"app.zip\", \"contentType\": \"application/zip\" }")
UPLOAD_ID=$(printf '%s' "$UP" | jget upload.id); UPLOAD_URL=$(printf '%s' "$UP" | jget upload.uploadUrl)
if [[ -z "$UPLOAD_ID" ]]; then echo "アップロード URL の発行に失敗: $UP" >&2; exit 7; fi
curl -sS -f -X PUT "$UPLOAD_URL" -H "Content-Type: application/zip" --data-binary "@$ZIP" >/dev/null
echo "アップロード完了: $UPLOAD_ID"

# 4. 検証して checkId を得る
CHECK=$(curl -sS -N -X POST "${AUTH[@]}" "${JSON[@]}" "$BASE_URL/api/v1/uploads/$UPLOAD_ID/check" --data '{}' | tr -d '[:space:]' | python3 -c 'import sys,json; s=sys.stdin.read(); i=s.find("{"); print(s[i:])')
CAN=$(printf '%s' "$CHECK" | jget result.canDeploy); CHECK_ID=$(printf '%s' "$CHECK" | jget result.checkId)
if [[ "$CAN" != "True" && "$CAN" != "true" ]]; then
  echo "検証で問題が見つかりました:" >&2; printf '%s' "$CHECK" | jget result.errors >&2; exit 8
fi
echo "検証 OK: $CHECK_ID"

# 5. 環境変数の JSON
ENV_FIELD=""
if [[ -n "$ENVS" ]]; then
  ENV_JSON=$(python3 -c 'import json,sys
items=[]
for kv in sys.argv[1].split(","):
    if "=" in kv:
        k,v=kv.split("=",1); items.append({"key":k.strip(),"value":v,"type":"secret"})
print(json.dumps(items, ensure_ascii=False))' "$ENVS")
  ENV_FIELD=", \"envs\": $ENV_JSON"
fi

# 6. 作成 or 再デプロイ
if [[ -n "$PROJECT" ]]; then
  if [[ -n "$ENVS" ]]; then  # 先に保存してからデプロイすると、新しいデプロイに反映される
    curl -sS -X PATCH "${AUTH[@]}" "${JSON[@]}" "$BASE_URL/api/v1/projects/$PROJECT/env" --data "{ \"envs\": $ENV_JSON }" >/dev/null
    echo "環境変数を保存: $(printf '%s' "$ENV_JSON" | python3 -c 'import json,sys; print(",".join(e["key"] for e in json.load(sys.stdin)))')"
  fi
  RES=$(curl -sS -N -X POST "${AUTH[@]}" "${JSON[@]}" "$BASE_URL/api/v1/projects/$PROJECT/deploy" \
    --data "{ \"source\": { \"type\": \"zip\", \"checkId\": \"$CHECK_ID\" } }" | tr -d '\r' | python3 -c 'import sys; s=sys.stdin.read(); i=s.find("{"); print(s[i:] if i>=0 else s)')
else
  RES=$(curl -sS -N -X POST "${AUTH[@]}" "${JSON[@]}" "$BASE_URL/api/v1/projects" \
    --data "{ $WS_FIELD \"name\": \"$NAME\", \"source\": { \"type\": \"zip\", \"checkId\": \"$CHECK_ID\" } $ENV_FIELD }" | tr -d '\r' | python3 -c 'import sys; s=sys.stdin.read(); i=s.find("{"); print(s[i:] if i>=0 else s)')
  PROJECT=$(printf '%s' "$RES" | jget project.id)
  if [[ -z "$PROJECT" ]]; then echo "プロジェクト作成に失敗: $RES" >&2; exit 9; fi
fi
echo "デプロイ開始: project=$PROJECT"

# 7. 完了を待つ
START=$(date +%s)
while true; do
  P=$(curl -sS "${AUTH[@]}" "$BASE_URL/api/v1/projects/$PROJECT")
  STATE=$(printf '%s' "$P" | jget project.latestDeployment.readyState)
  case "$STATE" in
    READY) echo "公開完了: $(printf '%s' "$P" | jget project.url)"; echo "project id: $PROJECT"; rm -f "$ZIP"; exit 0;;
    ERROR) echo "デプロイ失敗: errorCode=$(printf '%s' "$P" | jget project.latestDeployment.errorCode)" >&2
           echo "ログ: curl -s \"$BASE_URL/api/v1/projects/$PROJECT/logs?since=-30m&format=text\" -H 'Authorization: Bearer \$HANAMII_TOKEN'" >&2; rm -f "$ZIP"; exit 10;;
  esac
  if (( $(date +%s) - START > TIMEOUT )); then echo "タイムアウト（${TIMEOUT}秒）。状態: $STATE。あとで GET /api/v1/projects/$PROJECT を確認してください" >&2; rm -f "$ZIP"; exit 11; fi
  sleep 10
done

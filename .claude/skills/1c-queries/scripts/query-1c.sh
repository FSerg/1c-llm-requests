#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
env_file="$script_dir/../.env"

if [[ ! -f "$env_file" ]]; then
  echo "Env file not found: $env_file" >&2
  exit 1
fi

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%$'\r'}"
  line="$(trim "$line")"
  [[ -z "$line" ]] && continue
  [[ "${line:0:1}" == "#" ]] && continue

  key="${line%%=*}"
  value="${line#*=}"
  key="$(trim "$key")"
  value="$(trim "$value")"

  if [[ "$value" == "\""*"\"" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == "'"*"'" ]]; then
    value="${value:1:${#value}-2}"
  fi

  export "$key=$value"
done < "$env_file"

: "${ONEC_QUERY_URL:?Missing ONEC_QUERY_URL in $env_file}"
: "${ONEC_QUERY_LOGIN:?Missing ONEC_QUERY_LOGIN in $env_file}"
: "${ONEC_QUERY_PASSWORD:?Missing ONEC_QUERY_PASSWORD in $env_file}"

query=""

if [[ $# -gt 0 ]]; then
  case "$1" in
    -f|--file)
      if [[ $# -lt 2 ]]; then
        echo "Missing file path after $1" >&2
        exit 1
      fi
      query="$(cat "$2")"
      shift 2
      ;;
    *)
      query="$*"
      ;;
  esac
else
  query="$(cat)"
fi

if [[ -z "$query" ]]; then
  echo "Query is empty. Pass query text, use -f/--file, or pipe input." >&2
  exit 1
fi

python_bin="$(command -v python3 || true)"
if [[ -z "$python_bin" ]]; then
  python_bin="$(command -v python || true)"
fi

if [[ -z "$python_bin" ]]; then
  echo "Python is required to build JSON payload (python3 or python)." >&2
  exit 1
fi

json="$($python_bin -c 'import json,sys; query=sys.stdin.read(); print(json.dumps({"query": query}))' <<<"$query")"

if ! command -v base64 >/dev/null 2>&1; then
  echo "base64 command is required for Basic Auth." >&2
  exit 1
fi

auth="$(printf '%s' "${ONEC_QUERY_LOGIN}:${ONEC_QUERY_PASSWORD}" | base64 | tr -d '\n')"

curl -sS --connect-timeout 5 --max-time 60 -X POST "$ONEC_QUERY_URL" \
  -H "Authorization: Basic $auth" \
  -H "Content-Type: application/json; charset=utf-8" \
  --data-binary "$json"

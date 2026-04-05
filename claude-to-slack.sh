#!/bin/bash

# Hook 데이터를 먼저 읽기 (UserPromptSubmit은 설정 로딩 없이 바로 처리)
input=$(cat)
hook_event_name=$(echo "$input" | jq -r '.hook_event_name')
session_id=$(echo "$input" | jq -r '.session_id // empty')

# UserPromptSubmit: 사용자 입력을 임시 파일에 저장 후 종료
if [ "$hook_event_name" = "UserPromptSubmit" ]; then
    prompt=$(echo "$input" | jq -r '.prompt // empty')
    if [ -n "$prompt" ] && [ "$prompt" != "null" ]; then
        echo "$prompt" > "/tmp/claude-slack-prompt-${session_id}.tmp"
    fi
    exit 0
fi

# Slack 설정 파일 경로 (프로젝트별 > 전역)
PROJECT_SLACK_CONFIG="$(pwd)/.claude/plugins/slack-integration/slack-config.json"
GLOBAL_SLACK_CONFIG="$HOME/.claude/slack-config.json"

# 기본값 설정
SLACK_BOT_TOKEN=""
SLACK_CHANNEL="#claude-code"
DISPLAY_NAME=""
USED_CONFIG_FILE=""

# 설정 파일 우선순위: 프로젝트별 > 전역
if [ -f "$PROJECT_SLACK_CONFIG" ]; then
    SLACK_BOT_TOKEN=$(jq -r '.bot_token // empty' "$PROJECT_SLACK_CONFIG")
    SLACK_CHANNEL=$(jq -r '.channel // "#claude-code"' "$PROJECT_SLACK_CONFIG")
    DISPLAY_NAME=$(jq -r '.display_name // empty' "$PROJECT_SLACK_CONFIG")
    USED_CONFIG_FILE="$PROJECT_SLACK_CONFIG"
elif [ -f "$GLOBAL_SLACK_CONFIG" ]; then
    SLACK_BOT_TOKEN=$(jq -r '.bot_token // empty' "$GLOBAL_SLACK_CONFIG")
    SLACK_CHANNEL=$(jq -r '.channel // "#claude-code"' "$GLOBAL_SLACK_CONFIG")
    DISPLAY_NAME=$(jq -r '.display_name // empty' "$GLOBAL_SLACK_CONFIG")
    USED_CONFIG_FILE="$GLOBAL_SLACK_CONFIG"
else
    echo "오류: Slack 설정 파일이 없습니다." >&2
    echo "" >&2
    echo "다음 중 하나의 설정 파일을 생성해주세요:" >&2
    echo "" >&2
    echo "1. 프로젝트별 설정 (이 프로젝트에서만 사용):" >&2
    echo "   mkdir -p .claude/plugins/slack-integration" >&2
    echo "   cat > .claude/plugins/slack-integration/slack-config.json << EOF" >&2
    echo '   {' >&2
    echo '     "bot_token": "xoxb-your-bot-token-here",' >&2
    echo '     "channel": "#claude-code"' >&2
    echo '   }' >&2
    echo '   EOF' >&2
    echo "" >&2
    echo "2. 전역 설정 (모든 프로젝트에서 사용):" >&2
    echo "   mkdir -p ~/.claude" >&2
    echo "   cat > ~/.claude/slack-config.json << EOF" >&2
    echo '   {' >&2
    echo '     "bot_token": "xoxb-your-bot-token-here",' >&2
    echo '     "channel": "#claude-code"' >&2
    echo '   }' >&2
    echo '   EOF' >&2
    exit 1
fi

# 필수 설정 체크
if [ -z "$SLACK_BOT_TOKEN" ] || [ "$SLACK_BOT_TOKEN" = "null" ]; then
    echo "오류: bot_token이 설정되지 않았습니다." >&2
    echo "$USED_CONFIG_FILE 파일의 bot_token을 확인해주세요." >&2
    exit 1
fi

# 프로젝트 이름 추출
project_name=$(basename "$(pwd)")

# 사용자 이름 및 날짜 추출
user_name=$(whoami)
current_date=$(date '+%Y-%m-%d')
thread_key="${user_name}_${current_date}"

# 표시 이름 설정
if [ -n "$DISPLAY_NAME" ] && [ "$DISPLAY_NAME" != "null" ] && [ "$DISPLAY_NAME" != "" ]; then
    display_user_name="$DISPLAY_NAME"
else
    display_user_name="$user_name"
fi

# 프로젝트별 쓰레드 캐시 파일
project_claude_dir="$(pwd)/.claude/plugins/slack-integration"
THREAD_CACHE_FILE="$project_claude_dir/slack-threads.json"

if [ ! -f "$THREAD_CACHE_FILE" ]; then
    mkdir -p "$(dirname "$THREAD_CACHE_FILE")"
    echo '{}' > "$THREAD_CACHE_FILE"
fi

# 쓰레드 TS 관리 함수
get_thread_ts() {
    local key="$1"
    if [ ! -f "$THREAD_CACHE_FILE" ]; then
        mkdir -p "$(dirname "$THREAD_CACHE_FILE")"
        echo '{}' > "$THREAD_CACHE_FILE"
    fi
    jq -r ".\"$key\" // \"\"" "$THREAD_CACHE_FILE" 2>/dev/null || echo ""
}

save_thread_ts() {
    local key="$1"
    local ts="$2"
    if [ ! -f "$THREAD_CACHE_FILE" ]; then
        mkdir -p "$(dirname "$THREAD_CACHE_FILE")"
        echo '{}' > "$THREAD_CACHE_FILE"
    fi
    local temp_file=$(mktemp)
    jq ". + {\"$key\": \"$ts\"}" "$THREAD_CACHE_FILE" > "$temp_file" && mv "$temp_file" "$THREAD_CACHE_FILE"
}

# Slack 메시지 전송 함수
send_slack_message() {
    local text="$1"
    local thread_ts="$2"

    local payload
    if [ -n "$thread_ts" ]; then
        payload=$(jq -n \
            --arg channel "$SLACK_CHANNEL" \
            --arg text "$text" \
            --arg thread_ts "$thread_ts" \
            '{channel: $channel, text: $text, thread_ts: $thread_ts,
              username: "Claude Code Monitor", icon_emoji: ":claude:"}')
    else
        payload=$(jq -n \
            --arg channel "$SLACK_CHANNEL" \
            --arg text "$text" \
            '{channel: $channel, text: $text,
              username: "Claude Code Monitor", icon_emoji: ":claude:"}')
    fi

    local response=$(curl -X POST \
        -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
        -H "Content-Type: application/json" \
        --data "$payload" \
        --max-time 10 \
        --silent \
        "https://slack.com/api/chat.postMessage" 2>/dev/null)

    if [ -z "$thread_ts" ]; then
        local new_ts=$(echo "$response" | jq -r '.ts // empty')
        if [ -n "$new_ts" ] && [ "$new_ts" != "null" ]; then
            save_thread_ts "$thread_key" "$new_ts"
            echo "새 쓰레드 생성: $new_ts" >&2
        else
            echo "쓰레드 생성 실패: $response" >&2
        fi
    else
        echo "쓰레드에 메시지 추가 완료" >&2
    fi
}

# Stop hook 처리
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

if [ "$hook_event_name" = "Stop" ]; then
    # 1. UserPromptSubmit이 저장한 temp 파일에서 user_text 읽기
    PROMPT_FILE="/tmp/claude-slack-prompt-${session_id}.tmp"
    if [ -f "$PROMPT_FILE" ]; then
        user_text=$(cat "$PROMPT_FILE")
        rm -f "$PROMPT_FILE"
    fi

    # 2. transcript에서 assistant 응답 추출 + user_text 폴백 + 최종 Stop 여부 판별
    if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
        _tmp_asst=$(mktemp)
        _tmp_user_fallback=$(mktemp)
        _tmp_is_final=$(mktemp)
        python3 - "$transcript_path" "$_tmp_asst" "$_tmp_user_fallback" "$_tmp_is_final" << 'PYEOF'
import json, sys

transcript_path, asst_file, user_fallback_file, is_final_file = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

entries = []
with open(transcript_path, 'r', encoding='utf-8', errors='replace') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except Exception:
            pass

SKIP_TAGS = ('<user-prompt-submit-hook>', '<system-reminder>')

# 마지막 user 메시지 인덱스 찾기
last_user_idx = None
last_user_text = None
for i, entry in enumerate(entries):
    if entry.get('type') == 'user':
        content = entry.get('message', {}).get('content', '')
        if isinstance(content, list):
            if any(c.get('type') == 'tool_result' for c in content):
                continue
            text = '\n'.join(c.get('text', '') for c in content if c.get('type') == 'text')
        elif isinstance(content, str):
            text = content
        else:
            continue
        if not text or any(tag in text for tag in SKIP_TAGS):
            continue
        last_user_text = text
        last_user_idx = i

# 마지막 user 이후 assistant 메시지 수집
# - asst_text: 마지막 assistant의 text (최종 응답)
# - is_final: 마지막 assistant에 tool_use가 없으면 True
asst_text = None
is_final = True

if last_user_idx is not None:
    last_asst_content = None
    for entry in entries[last_user_idx + 1:]:
        if entry.get('type') == 'assistant':
            content = entry.get('message', {}).get('content', [])
            if isinstance(content, list):
                text = '\n'.join(c.get('text', '') for c in content if c.get('type') == 'text')
                if text:
                    asst_text = text
                last_asst_content = content

    if last_asst_content is not None:
        if any(c.get('type') == 'tool_use' for c in last_asst_content):
            is_final = False

with open(asst_file, 'w', encoding='utf-8') as f:
    f.write(asst_text or '')
with open(user_fallback_file, 'w', encoding='utf-8') as f:
    f.write(last_user_text or '')
with open(is_final_file, 'w') as f:
    f.write('true' if is_final else 'false')
PYEOF

        assistant_text=$(cat "$_tmp_asst")
        user_text_fallback=$(cat "$_tmp_user_fallback")
        is_final_stop=$(cat "$_tmp_is_final")
        rm -f "$_tmp_asst" "$_tmp_user_fallback" "$_tmp_is_final"

        if [ -z "$user_text" ]; then
            user_text="$user_text_fallback"
        fi

        # 도구 호출 중간 Stop이면 전송 스킵
        if [ "$is_final_stop" = "false" ]; then
            exit 0
        fi
    fi

    # 3. user_text 기본값
    user_text=${user_text:-"[질문 없음]"}

    # 4. 취소 여부에 따라 메시지 구성 (Slack mrkdwn 문법)
    if [ -z "$assistant_text" ]; then
        combined_message="*👤 질문:*
\`\`\`
${user_text}
\`\`\`

*⚠️ 취소됨*"
    else
        combined_message="*👤 질문:*
\`\`\`
${user_text}
\`\`\`

*🤖 답변:*
${assistant_text}"
    fi

    # 5. Slack 전송 (쓰레드 관리)
    existing_thread_ts=$(get_thread_ts "$thread_key")
    send_slack_message "$combined_message" "$existing_thread_ts" &
fi

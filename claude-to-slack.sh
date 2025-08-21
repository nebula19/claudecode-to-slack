#!/bin/bash

# Slack 설정 파일 경로 (프로젝트별 > 전역)
PROJECT_SLACK_CONFIG="$(pwd)/.claude/plugins/slack-integration/slack-config.json"
GLOBAL_SLACK_CONFIG="$HOME/.claude/slack-config.json"

# 기본값 설정
SLACK_BOT_TOKEN=""
SLACK_CHANNEL="#claude-code"
USED_CONFIG_FILE=""

# 설정 파일 우선순위: 프로젝트별 > 전역
if [ -f "$PROJECT_SLACK_CONFIG" ]; then
    SLACK_BOT_TOKEN=$(jq -r '.bot_token // empty' "$PROJECT_SLACK_CONFIG")
    SLACK_CHANNEL=$(jq -r '.channel // "#claude-code"' "$PROJECT_SLACK_CONFIG")
    USED_CONFIG_FILE="$PROJECT_SLACK_CONFIG"
elif [ -f "$GLOBAL_SLACK_CONFIG" ]; then
    SLACK_BOT_TOKEN=$(jq -r '.bot_token // empty' "$GLOBAL_SLACK_CONFIG")
    SLACK_CHANNEL=$(jq -r '.channel // "#claude-code"' "$GLOBAL_SLACK_CONFIG")
    USED_CONFIG_FILE="$GLOBAL_SLACK_CONFIG"
else
    # 설정 파일이 없으면 생성 안내
    echo "오류: Slack 설정 파일이 없습니다." >&2
    echo "" >&2
    echo "다음 중 하나의 설정 파일을 생성해주세요:" >&2
    echo "" >&2
    echo "1. 프로젝트별 설정 (이 프로젝트에서만 사용):" >&2
    echo "   mkdir -p .claude" >&2
    echo "   cat > .claude/slack-config.json << EOF" >&2
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
    echo "~/.claude/slack-config.json 파일의 bot_token을 확인해주세요." >&2
    exit 1
fi

# Hook 데이터 읽기
input=$(cat)
hook_event_name=$(echo "$input" | jq -r '.hook_event_name')
transcript_path=$(echo "$input" | jq -r '.transcript_path')
prompt=$(echo "$input" | jq -r '.prompt // empty')

# 프로젝트 이름 추출
project_name=$(basename "$(dirname "$transcript_path")" | sed 's/^-Users-[^-]*-//' | tr '-' '/')

# 사용자 이름 및 날짜 추출
user_name=$(whoami)
current_date=$(date '+%Y-%m-%d')
thread_key="${user_name}_${current_date}"

# 프로젝트별 쓰레드 캐시 파일 설정 (현재 작업 디렉토리 사용)
project_claude_dir="$(pwd)/.claude/plugins/slack-integration"
THREAD_CACHE_FILE="$project_claude_dir/slack-threads.json"

# 쓰레드 캐시 파일 초기화
if [ ! -f "$THREAD_CACHE_FILE" ]; then
    mkdir -p "$(dirname "$THREAD_CACHE_FILE")"
    echo '{}' > "$THREAD_CACHE_FILE"
fi

# 쓰레드 TS 관리 함수들
get_thread_ts() {
    local key="$1"
    # 캐시 파일이 없으면 생성
    if [ ! -f "$THREAD_CACHE_FILE" ]; then
        mkdir -p "$(dirname "$THREAD_CACHE_FILE")"
        echo '{}' > "$THREAD_CACHE_FILE"
    fi
    jq -r ".\"$key\" // \"\"" "$THREAD_CACHE_FILE" 2>/dev/null || echo ""
}

save_thread_ts() {
    local key="$1"
    local ts="$2"
    # 캐시 파일이 없으면 생성
    if [ ! -f "$THREAD_CACHE_FILE" ]; then
        mkdir -p "$(dirname "$THREAD_CACHE_FILE")"
        echo '{}' > "$THREAD_CACHE_FILE"
    fi
    local temp_file=$(mktemp)
    jq ". + {\"$key\": \"$ts\"}" "$THREAD_CACHE_FILE" > "$temp_file" && mv "$temp_file" "$THREAD_CACHE_FILE"
}

# Slack 메시지 전송 함수 (Bot API 사용)
send_slack_message() {
    local text="$1"
    local project="$2"
    local thread_ts="$3"
    
    local payload
    if [ -n "$thread_ts" ]; then
        # 쓰레드 응답
        payload=$(jq -n \
            --arg channel "$SLACK_CHANNEL" \
            --arg text "$text" \
            --arg thread_ts "$thread_ts" \
            '{
                channel: $channel,
                text: $text,
                thread_ts: $thread_ts,
                username: "Claude Code Monitor",
                icon_emoji: ":claude:"
            }')
    else
        # 새 메시지 (쓰레드 시작)
        local header_text="*🚀 ${project}* | 👤 ${user_name} | 📅 ${current_date}"
        payload=$(jq -n \
            --arg channel "$SLACK_CHANNEL" \
            --arg text "$header_text\n\n$text" \
            '{
                channel: $channel,
                text: $text,
                username: "Claude Code Monitor",
                icon_emoji: ":claude:"
            }')
    fi
    
    # Slack Bot API로 전송
    local response=$(curl -X POST \
        -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
        -H "Content-Type: application/json" \
        --data "$payload" \
        --max-time 5 \
        "https://slack.com/api/chat.postMessage" 2>/dev/null)
    
    # 새 메시지인 경우 응답에서 ts 추출하여 저장
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

# UserPromptSubmit hook 처리
if [ "$hook_event_name" = "UserPromptSubmit" ] && [ -n "$prompt" ]; then
    payload=$(jq -n \
        --arg text "$prompt" \
        --arg project "$project_name" \
        '{
            username: "Claude Code Monitor",
            icon_emoji: ":claude:",
            attachments: [{
                color: "#36a64f",
                fields: [
                    {
                        title: ":speech_balloon: 사용자 질문",
                        value: $text,
                        short: false
                    },
                    {
                        title: "Project", 
                        value: $project,
                        short: true
                    }
                ],
                footer: "Claude Code",
                ts: (now | floor)
            }]
        }')
    
    curl -X POST -H 'Content-Type: application/json' \
         --data "$payload" \
         --max-time 3 \
         --silent \
         "$SLACK_WEBHOOK_URL" &
    exit 0
fi

# Stop hook 처리 
if [ "$hook_event_name" = "Stop" ] && [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
    # 최근 assistant 메시지 찾기 (text 타입이 있는 것만)
    assistant_text=$(tail -r "$transcript_path" | while IFS= read -r line; do
        if echo "$line" | jq -e '.type == "assistant" and .message.content' > /dev/null 2>&1; then
            text_content=$(echo "$line" | jq -r '.message.content[] | select(.type == "text") | .text' 2>/dev/null)
            if [ -n "$text_content" ]; then
                echo "$text_content"
                break
            fi
        fi
    done)
    
    # 최근 user 메시지 찾기 (전체 텍스트, tool_result, hook 메시지 제외)
    user_text=$(tail -r "$transcript_path" | while IFS= read -r line; do
        if echo "$line" | jq -e '.type == "user" and .message.content' > /dev/null 2>&1; then
            content=$(echo "$line" | jq -r '.message.content')
            if [[ "$content" == *"<user-prompt-submit-hook>"* ]] || [[ "$content" == "["* ]]; then
                continue
            fi
            # 사용자가 입력한 줄바꿈 그대로 유지
            echo "$content"
            break
        fi
    done)
    
    # 기본값 설정
    user_text=${user_text:-"[질문 없음]"}
    assistant_text=${assistant_text:-"[응답 없음]"}
    
    # 결합된 메시지 생성 (Slack mrkdwn 문법 사용)
    combined_message="*👤 질문:*
\`\`\`
${user_text}
\`\`\`

*🤖 답변:*
${assistant_text}"
    
    # 기존 쓰레드 TS 확인
    existing_thread_ts=$(get_thread_ts "$thread_key")
    
    # 쓰레드 시스템으로 메시지 전송
    send_slack_message "$combined_message" "$project_name" "$existing_thread_ts" &
fi

#!/bin/bash

SLACK_WEBHOOK_URL="https://hooks.slack.com/services/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"

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
project_claude_dir="$(pwd)/.claude"
THREAD_CACHE_FILE="$project_claude_dir/slack-threads.json"

# 쓰레드 캐시 파일 초기화
if [ ! -f "$THREAD_CACHE_FILE" ]; then
    mkdir -p "$(dirname "$THREAD_CACHE_FILE")"
    echo '{}' > "$THREAD_CACHE_FILE"
fi

# 쓰레드 TS 관리 함수들
get_thread_ts() {
    local key="$1"
    jq -r ".\"$key\" // \"\"" "$THREAD_CACHE_FILE" 2>/dev/null || echo ""
}

save_thread_ts() {
    local key="$1"
    local ts="$2"
    local temp_file=$(mktemp)
    jq ". + {\"$key\": \"$ts\"}" "$THREAD_CACHE_FILE" > "$temp_file" && mv "$temp_file" "$THREAD_CACHE_FILE"
}

# Slack 메시지 전송 함수
send_slack_message() {
    local text="$1"
    local project="$2"
    local thread_ts="$3"
    
    local payload
    if [ -n "$thread_ts" ]; then
        # 쓰레드 응답
        payload=$(jq -n \
            --arg text "$text" \
            --arg project "$project" \
            --arg thread_ts "$thread_ts" \
            '{
                username: "Claude Code Monitor",
                icon_emoji: ":claude:",
                thread_ts: $thread_ts,
                attachments: [{
                    color: "#36a64f",
                    mrkdwn_in: ["text"],
                    text: $text,
                    fields: [
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
    else
        # 새 메시지 (쓰레드 시작)
        payload=$(jq -n \
            --arg text "$text" \
            --arg project "$project" \
            --arg date "$current_date" \
            --arg user "$user_name" \
            '{
                username: "Claude Code Monitor",
                icon_emoji: ":claude:",
                attachments: [{
                    color: "#36a64f",
                    mrkdwn_in: ["text"],
                    text: $text,
                    fields: [
                        {
                            title: "Project",
                            value: $project,
                            short: true
                        },
                        {
                            title: "User",
                            value: $user,
                            short: true
                        },
                        {
                            title: "Date",
                            value: $date,
                            short: true
                        }
                    ],
                    footer: "Claude Code Thread Start",
                    ts: (now | floor)
                }]
            }')
    fi
    
    # Slack으로 전송하고 응답에서 ts 추출
    local response=$(curl -X POST -H 'Content-Type: application/json' \
                          --data "$payload" \
                          --max-time 3 \
                          "$SLACK_WEBHOOK_URL" 2>/dev/null)
    
    # 새 메시지인 경우 ts를 캐시에 저장 (Webhook은 ts를 반환하지 않으므로 현재 시간 사용)
    if [ -z "$thread_ts" ]; then
        local new_ts=$(date +%s.%N | cut -c1-16)
        save_thread_ts "$thread_key" "$new_ts"
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
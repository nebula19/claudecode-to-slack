#!/bin/bash

SLACK_WEBHOOK_URL="https://hooks.slack.com/services/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"

# Hook 데이터 읽기
input=$(cat)
hook_event_name=$(echo "$input" | jq -r '.hook_event_name')
transcript_path=$(echo "$input" | jq -r '.transcript_path')
prompt=$(echo "$input" | jq -r '.prompt // empty')

# 프로젝트 이름 추출
project_name=$(basename "$(dirname "$transcript_path")" | sed 's/^-Users-[^-]*-//' | tr '-' '/')

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
    
    # 최근 user 메시지 찾기 (전체 텍스트, 줄바꿈 제거, tool_result, hook 메시지 제외)
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
    
    payload=$(jq -n \
        --arg text "$combined_message" \
        --arg project "$project_name" \
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
fi
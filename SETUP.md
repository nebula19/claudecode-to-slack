# Claude Code to Slack Integration Setup Guide

Claude Code CLI의 프롬프트와 AI 응답을 실시간으로 Slack 쓰레드에 전송하는 도구입니다.

## 🚀 빠른 설정

### 1. Slack Bot 생성
1. https://api.slack.com/apps 에서 "Create New App" 클릭
2. "From scratch" 선택
3. App 이름: "Claude Code Monitor" 
4. 워크스페이스 선택

### 2. Bot 권한 설정
1. **OAuth & Permissions** → **Bot Token Scopes**에 추가:
   - `chat:write` - 메시지 전송
   - `chat:write.public` - 퍼블릭 채널 접근
2. **Install to Workspace** 클릭
3. **Bot User OAuth Token** 복사 (`xoxb-...` 형태)

### 3. 채널 설정
1. Slack에서 `#claude-code` 채널 생성 (또는 원하는 이름)
2. 채널에 Bot 초대: `/invite @Claude Code Monitor`

### 4. 환경변수 설정
```bash
# Bot Token 설정 (필수)
export CLAUDE_SLACK_BOT_TOKEN="xoxb-your-bot-token-here"

# 채널 설정 (선택사항, 기본값: #claude-code)  
export CLAUDE_SLACK_CHANNEL="#your-channel-name"
```

### 5. 스크립트 설치
```bash
# 1. 스크립트 다운로드
curl -o ~/.claude/claude-to-slack.sh https://raw.githubusercontent.com/your-repo/claude-to-slack.sh

# 2. 실행 권한 부여
chmod +x ~/.claude/claude-to-slack.sh

# 3. Claude Code Hook 설정
cat > ~/.claude/settings.json << 'EOF'
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/claude-to-slack.sh"
          }
        ]
      }
    ]
  }
}
EOF
```

## 🔧 고급 설정

### 설정 파일 사용
환경변수 대신 설정 파일을 사용할 수 있습니다:

```bash
# ~/.claude/slack-config.json
{
  "bot_token": "xoxb-your-bot-token",
  "channel": "#claude-code"
}
```

### 다중 프로젝트 설정
각 프로젝트마다 다른 채널을 사용하려면:

```bash
# 프로젝트별 환경변수 설정
cd /path/to/project1
export CLAUDE_SLACK_CHANNEL="#project1-logs"

cd /path/to/project2  
export CLAUDE_SLACK_CHANNEL="#project2-logs"
```

## 📱 동작 방식

### 쓰레드 시스템
- **쓰레드 키**: `{사용자}_{날짜}` (예: `john_2025-08-21`)
- **첫 메시지**: 새로운 쓰레드 생성
- **후속 메시지**: 같은 쓰레드에 추가
- **새로운 날**: 새로운 쓰레드 생성

### 메시지 포맷
```
🚀 프로젝트명 | 👤 사용자명 | 📅 날짜

👤 질문:
```
사용자 질문 내용
```

🤖 답변:
AI 응답 내용
```

## 🔍 문제 해결

### 메시지가 전송되지 않는 경우
1. **Bot Token 확인**:
   ```bash
   curl -H "Authorization: Bearer $CLAUDE_SLACK_BOT_TOKEN" \
        "https://slack.com/api/auth.test"
   ```

2. **채널 접근 권한 확인**:
   - Bot이 채널에 초대되었는지 확인
   - 채널이 private인 경우 명시적 초대 필요

3. **Hook 실행 확인**:
   ```bash
   echo '{"hook_event_name":"Stop","transcript_path":"test"}' | \
   ~/.claude/claude-to-slack.sh
   ```

### 디버그 모드
스크립트 상단에 추가:
```bash
set -x  # 디버그 모드 활성화
```

## 🔒 보안 주의사항

- ❌ Bot Token을 코드에 하드코딩하지 마세요
- ✅ 환경변수나 설정파일 사용
- ✅ 설정파일은 권한 제한 (`chmod 600`)
- ✅ Git에 토큰 커밋 금지 (`.gitignore` 추가)

```bash
# 설정파일 권한 제한
chmod 600 ~/.claude/slack-config.json

# .gitignore에 추가  
echo "slack-config.json" >> .gitignore
```

## 📦 배포용 패키지

개인 정보 제거된 버전:
- ✅ 환경변수 기반 설정
- ✅ 기본값 제공
- ✅ 에러 처리 및 가이드
- ✅ 다중 워크스페이스 지원
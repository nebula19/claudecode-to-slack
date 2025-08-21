# Claude Code to Slack Integration Setup Guide

Claude Code CLI의 프롬프트와 AI 응답을 실시간으로 Slack 쓰레드에 전송하는 도구입니다.

## 🚀 빠른 설치 (원라인 설치)

### 자동 설치 스크립트 사용
```bash
curl -fsSL https://raw.githubusercontent.com/nebula19/claudecode-to-slack/main/install.sh | bash
```

스크립트가 다음을 자동으로 수행합니다:
- Bot Token 입력 받기
- 채널명 입력 받기  
- 설정 파일 자동 생성
- Claude Code Hook 자동 설정
- Bot 연결 테스트

## 📋 수동 설정 (필요시)

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
1. Slack에서 원하는 채널 생성 (예: `#claude-code`)
2. 채널에 Bot 초대: `/invite @Claude Code Monitor`

### 4. 수동 설정 파일 생성
```bash
# 프로젝트별 설정 (해당 프로젝트에서만 사용)
mkdir -p .claude/plugins/slack-integration
cat > .claude/plugins/slack-integration/slack-config.json << 'EOF'
{
  "bot_token": "xoxb-your-bot-token-here",
  "channel": "#your-channel-name"
}
EOF

# 권한 제한
chmod 600 .claude/plugins/slack-integration/slack-config.json
```

### 5. 수동 스크립트 설치
```bash
# 1. 프로젝트 .claude 디렉토리 생성
mkdir -p .claude/plugins/slack-integration

# 2. 스크립트 다운로드
curl -o .claude/plugins/slack-integration/claude-to-slack.sh https://raw.githubusercontent.com/nebula19/claudecode-to-slack/main/claude-to-slack.sh

# 3. 실행 권한 부여
chmod +x .claude/plugins/slack-integration/claude-to-slack.sh

# 4. Claude Code Hook 설정
cat > .claude/settings.local.json << 'EOF'
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "./.claude/plugins/slack-integration/claude-to-slack.sh"
          }
        ]
      }
    ]
  }
}
EOF
```

## 🔧 고급 설정

### 프로젝트별 설정
각 프로젝트마다 다른 채널을 사용하려면 프로젝트 디렉토리에 설정 파일을 생성:

```bash
# 프로젝트 루트에서
mkdir -p .claude/plugins/slack-integration
cat > .claude/plugins/slack-integration/slack-config.json << 'EOF'
{
  "bot_token": "xoxb-your-bot-token",
  "channel": "#project-specific-channel"
}
EOF

# .gitignore에 추가
echo ".claude/plugins/slack-integration/slack-config.json" >> .gitignore
```

### 설정 파일 우선순위
1. **프로젝트별 설정**: `./.claude/plugins/slack-integration/slack-config.json`
2. **전역 설정**: `~/.claude/slack-config.json`

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

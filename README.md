# Claude Code to Slack Integration

Claude Code CLI의 프롬프트와 AI 응답을 실시간으로 Slack으로 전송하는 도구입니다.

## 구성 요소

### 1. `claude-to-slack.js`
- Claude Code hook 스크립트
- 사용자 프롬프트와 AI 응답을 Slack으로 전송
- JSONL transcript 파일 파싱 및 메시지 추출

### 2. Hook 설정
Claude Code `~/.claude/settings.json`에 다음 hook이 등록되어 있습니다:

- **UserPromptSubmit**: 사용자가 프롬프트 입력 시 실행
- **Stop**: AI 응답 완료 시 실행

## 설치 및 설정

### 1. 의존성 확인
```bash
node --version  # v14 이상 필요
```

### 2. 스크립트 권한 설정
```bash
chmod +x claude-to-slack.js
```

### 3. Slack Webhook URL 설정
`claude-to-slack.js` 파일의 `SLACK_WEBHOOK_URL` 상수를 본인의 Slack Incoming Webhook URL로 변경하세요.

### 4. Claude Code 설정 확인
`~/.claude/settings.json` 파일에 hook이 올바르게 등록되었는지 확인하세요.

## 동작 방식

1. 사용자가 Claude Code에 프롬프트 입력
2. `UserPromptSubmit` hook 실행 → 사용자 질문을 Slack으로 전송
3. AI가 응답 완료
4. `Stop` hook 실행 → AI 응답을 Slack으로 전송

## 메시지 포맷

### 사용자 메시지
- 🗣️ 사용자 질문
- 녹색 색상
- 프로젝트명 표시

### AI 응답
- 🤖 AI 응답  
- 파란색 색상
- 프로젝트명 표시

## 문제 해결

### Hook 실행 확인
```bash
# Claude Code에서 프롬프트 입력 후 로그 확인
tail -f ~/.claude/projects/*/your-session.jsonl
```

### 스크립트 수동 테스트
```bash
echo '{"hook_event_name":"Stop","transcript_path":"/path/to/transcript.jsonl"}' | node claude-to-slack.js
```

### 로그 확인
Hook 실행 시 콘솔에 출력되는 로그를 확인하세요:
- Hook 데이터 수신 여부
- 메시지 파싱 성공 여부  
- Slack 응답 상태 코드

## 주의사항

- 메시지는 2000자로 제한됩니다
- 시스템 메시지(tool 실행 등)는 전송되지 않습니다
- transcript 파일이 존재하지 않으면 오류 로그가 출력됩니다

## Slack 설정

1. Slack 워크스페이스에서 Incoming Webhook 앱 설치
2. 전용 채널 생성 (예: #claude-code-logs)
3. Webhook URL을 스크립트에 설정

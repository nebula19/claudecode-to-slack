# Claude Code 로깅 시스템 개발 진행 상황

## 📅 작업 일자
**2025-08-20**

## 🎯 프로젝트 개요
Claude Code CLI의 자동 로깅 시스템 구축 및 Slack 연동 모니터링 도구 개발

## ✅ 완료된 작업들

### 1. Claude Code 자동 로깅 시스템 구축
- **위치**: `~/.claude/settings.json`, `~/.claude/claude-logger.sh`
- **기능**: 프롬프트, 도구 사용, 응답을 자동으로 로깅
- **로그 저장**: `~/claude-logs/session-YYYY-MM-DD.jsonl`

#### 주요 훅 설정
```json
{
  "hooks": {
    "UserPromptSubmit": [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/claude-logger.sh prompt"}]}],
    "PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/claude-logger.sh tool_start"}]}],
    "PostToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "$HOME/.claude/claude-logger.sh tool_end"}]}]
  }
}
```

#### 로깅 스크립트 기능
- 민감정보 자동 마스킹 (패스워드, API키, 토큰)
- JSON Lines 형태 로깅
- 실시간 append 방식

### 2. Transcript 파일 분석
- **위치**: `~/.claude/projects/-Users-nebula-aladin-*/[session-uuid].jsonl`
- **구조**: 전체 대화 내역이 JSON Lines 형태로 실시간 기록
- **특징**: 세션마다 새로운 UUID 파일 생성

#### Transcript JSON 구조
```json
{
  "message": {
    "role": "user|assistant",
    "content": [{"type": "text", "text": "실제 내용"}]
  },
  "timestamp": "2025-08-20T07:06:08.803Z",
  "sessionId": "797031e0-72cd-4ed6-ba9b-057836a5bed0"
}
```

### 3. Node.js 모니터링 도구 개발
- **파일**: `transcript-to-slack.js`
- **기능**: transcript 파일 실시간 모니터링 → Slack 전송
- **특징**: 외부 dependency 없음 (Node.js 기본 모듈만 사용)

#### 주요 기능
- 최신 transcript 파일 자동 감지
- 사용자 프롬프트와 Claude 응답만 필터링
- Slack webhook 연동
- 세션 자동 전환
- 민감정보 보호

## 📁 현재 프로젝트 구조

```
/Users/nebula/aladin/cclogmon/
├── transcript-to-slack.js  # 메인 모니터링 스크립트
├── package.json           # Node.js 패키지 설정  
├── README.md             # 사용법 가이드
└── PROGRESS.md           # 이 파일 (진행 상황)
```

## 🔧 설정 및 환경

### Claude Code 설정 파일들
- **전역 설정**: `~/.claude/settings.json` (모든 도구 사용 로깅)
- **프로젝트 설정**: `.claude/settings.local.json` (프롬프트 로깅)
- **로깅 스크립트**: `~/.claude/claude-logger.sh` (실행 권한 필요)

### 환경 변수
```bash
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

## 🚀 사용법

### 1. 기본 Claude Code 로깅 (이미 작동 중)
```bash
# 자동으로 다음에 로깅됨:
cat ~/claude-logs/session-$(date +%Y-%m-%d).jsonl
```

### 2. Slack 모니터링 실행
```bash
cd /Users/nebula/aladin/cclogmon
node transcript-to-slack.js
```

## 🎯 작동 원리

### 1. Claude Code Hooks → JSON Lines 로깅
```
사용자 입력 → UserPromptSubmit 훅 → claude-logger.sh prompt → logs/session-*.jsonl
도구 실행 → PreToolUse 훅 → claude-logger.sh tool_start → logs/session-*.jsonl  
도구 완료 → PostToolUse 훅 → claude-logger.sh tool_end → logs/session-*.jsonl
```

### 2. Transcript 모니터링 → Slack 전송
```
transcript/*.jsonl 감지 → JSON 파싱 → 사용자/Claude 메시지 추출 → Slack 전송
```

## ⚡ 핵심 발견사항

1. **Claude Code hooks 구조**: `matcher`와 `hooks` 배열 필요
2. **Transcript 파일명**: 세션마다 UUID 형태로 생성 (예측 불가)
3. **JSON stdin 처리**: hooks에서 JSON 데이터를 stdin으로 전달
4. **민감정보 마스킹**: 정규식 기반 자동 처리 필요
5. **실시간 모니터링**: `tail -f` 방식보다 주기적 polling이 안정적

## 🔍 테스트 결과

### ✅ 정상 작동 확인
- 프롬프트 자동 로깅: ✅
- 도구 사용 로깅: ✅  
- 도구 결과 로깅: ✅
- 민감정보 마스킹: ✅
- Transcript 파일 감지: ✅
- 세션별 파일 전환: ✅

### 🔧 해결된 문제들
1. **hooks 구조 오류** → 공식 문서 참조하여 올바른 구조로 수정
2. **도구 결과 누락** → PostToolUse의 `tool_response.stdout` 파싱 추가
3. **민감정보 노출** → 정규식 기반 마스킹 로직 구현
4. **파일명 예측 불가** → 최신 파일 자동 탐지 로직 구현

## 📋 향후 작업 계획

### 단기 (즉시 가능)
- [ ] Slack 웹훅 테스트 및 검증
- [ ] 에러 처리 강화 (파일 없음, 권한 등)
- [ ] 로그 순환 정책 (오래된 파일 정리)
- [ ] 설정 파일 기반 커스터마이징

### 중기 (추가 개발)
- [ ] 웹 대시보드 구축
- [ ] 다중 프로젝트 동시 모니터링
- [ ] Discord, Teams 등 다른 플랫폼 연동
- [ ] 메시지 필터링 및 키워드 알림

### 장기 (확장성)
- [ ] 분석 도구 (사용 패턴, 통계)
- [ ] API 서버화
- [ ] Docker 컨테이너화
- [ ] 클라우드 배포

## 🛠 기술 스택

- **Backend**: Node.js (기본 모듈)
- **File System**: 실시간 모니터링, JSON Lines 파싱
- **Integration**: Slack Webhooks, HTTPS
- **Monitoring**: File watchers, Polling
- **Security**: 정규식 기반 민감정보 마스킹

## 📚 참고 문서

- [Claude Code Hooks 공식 문서](https://docs.anthropic.com/en/docs/claude-code/hooks)
- [Claude Code Memory/Transcript](https://docs.anthropic.com/en/docs/claude-code/memory)
- [Slack Incoming Webhooks](https://api.slack.com/messaging/webhooks)

## 💡 핵심 교훈

1. **공식 문서 우선**: 추측보다는 공식 문서 확인이 중요
2. **실시간 모니터링의 복잡성**: 파일명 예측 불가, 세션 전환 등 고려사항 많음
3. **보안 중요성**: 민감정보 마스킹은 필수
4. **단순함의 가치**: 외부 dependency 없는 구현이 더 안정적
5. **디버깅의 중요성**: debug.log를 통한 실제 데이터 구조 파악 필수

---

**마지막 업데이트**: 2025-08-20 16:20
**작업자**: Claude Code + Human
**현재 상태**: 기본 기능 완성, 테스트 및 확장 단계
#!/usr/bin/env node

/**
 * Claude Code Transcript to Slack Monitor
 * 
 * Claude Code의 transcript 파일을 실시간으로 모니터링하여
 * 사용자 프롬프트와 Claude 응답을 슬랙으로 전송합니다.
 */

const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const https = require('https');

// 설정
const CONFIG = {
  // 슬랙 웹훅 URL (환경변수에서 읽어옴)
  SLACK_WEBHOOK_URL: process.env.SLACK_WEBHOOK_URL || '',
  
  // Claude 프로젝트 디렉토리
  CLAUDE_PROJECTS_DIR: path.join(process.env.HOME, '.claude', 'projects'),
  
  // 현재 프로젝트 디렉토리 (상대 경로를 절대 경로로 변환)
  CURRENT_PROJECT: process.cwd(),
  
  // 모니터링 간격 (ms)
  MONITOR_INTERVAL: 2000,
  
  // 슬랙 채널 설정
  SLACK_CHANNEL: '#claude-logs',
  SLACK_USERNAME: 'Claude Monitor',
  SLACK_ICON: ':robot_face:'
};

class TranscriptMonitor {
  constructor() {
    this.lastProcessedLine = 0;
    this.currentTranscriptPath = null;
    this.projectDirName = this.getProjectDirName();
  }

  // 현재 프로젝트의 디렉토리명 생성 (Claude 형식에 맞게)
  getProjectDirName() {
    return CONFIG.CURRENT_PROJECT.replace(/\//g, '-');
  }

  // 가장 최근 수정된 transcript 파일 찾기
  findLatestTranscript() {
    const projectTranscriptDir = path.join(
      CONFIG.CLAUDE_PROJECTS_DIR, 
      this.projectDirName
    );

    if (!fs.existsSync(projectTranscriptDir)) {
      console.log(`Project transcript directory not found: ${projectTranscriptDir}`);
      return null;
    }

    const files = fs.readdirSync(projectTranscriptDir)
      .filter(file => file.endsWith('.jsonl'))
      .map(file => {
        const filePath = path.join(projectTranscriptDir, file);
        const stats = fs.statSync(filePath);
        return { path: filePath, mtime: stats.mtime };
      })
      .sort((a, b) => b.mtime - a.mtime);

    return files.length > 0 ? files[0].path : null;
  }

  // transcript 파일에서 새로운 메시지 읽기
  readNewMessages(transcriptPath) {
    try {
      const content = fs.readFileSync(transcriptPath, 'utf8');
      const lines = content.split('\n').filter(line => line.trim());
      
      if (lines.length <= this.lastProcessedLine) {
        return [];
      }

      const newLines = lines.slice(this.lastProcessedLine);
      this.lastProcessedLine = lines.length;

      return newLines.map(line => {
        try {
          return JSON.parse(line);
        } catch (e) {
          console.log('Invalid JSON line:', e.message);
          return null;
        }
      }).filter(Boolean);
    } catch (error) {
      console.log('Error reading transcript:', error.message);
      return [];
    }
  }

  // 메시지 파싱 및 필터링
  parseMessage(entry) {
    if (!entry.message) return null;

    const message = entry.message;
    const timestamp = new Date(entry.timestamp).toLocaleString('ko-KR');

    // 사용자 메시지
    if (message.role === 'user') {
      const content = message.content;
      let text = '';
      
      if (typeof content === 'string') {
        text = content;
      } else if (Array.isArray(content)) {
        text = content
          .filter(item => item.type === 'text')
          .map(item => item.text)
          .join(' ');
      }

      if (text.trim()) {
        return {
          type: 'user',
          timestamp,
          content: text.trim()
        };
      }
    }

    // Claude 응답 (텍스트만)
    if (message.role === 'assistant' && Array.isArray(message.content)) {
      const textContent = message.content
        .filter(item => item.type === 'text')
        .map(item => item.text)
        .join(' ')
        .trim();

      if (textContent) {
        return {
          type: 'assistant',
          timestamp,
          content: textContent
        };
      }
    }

    return null;
  }

  // 슬랙 메시지 포맷팅
  formatSlackMessage(parsedMessage) {
    const icon = parsedMessage.type === 'user' ? ':bust_in_silhouette:' : ':robot_face:';
    const color = parsedMessage.type === 'user' ? '#36a64f' : '#4285f4';
    const title = parsedMessage.type === 'user' ? 'User Prompt' : 'Claude Response';

    return {
      channel: CONFIG.SLACK_CHANNEL,
      username: CONFIG.SLACK_USERNAME,
      icon_emoji: CONFIG.SLACK_ICON,
      attachments: [
        {
          color: color,
          title: `${icon} ${title}`,
          text: parsedMessage.content,
          footer: `Claude Code Monitor`,
          ts: Math.floor(new Date(parsedMessage.timestamp).getTime() / 1000),
          mrkdwn_in: ['text']
        }
      ]
    };
  }

  // 슬랙으로 메시지 전송
  sendToSlack(slackMessage) {
    if (!CONFIG.SLACK_WEBHOOK_URL) {
      console.log('⚠️  SLACK_WEBHOOK_URL이 설정되지 않았습니다.');
      console.log('📝 메시지:', slackMessage.attachments[0].text.substring(0, 100) + '...');
      return;
    }

    const postData = JSON.stringify(slackMessage);
    const url = new URL(CONFIG.SLACK_WEBHOOK_URL);

    const options = {
      hostname: url.hostname,
      port: 443,
      path: url.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(postData)
      }
    };

    const req = https.request(options, (res) => {
      if (res.statusCode === 200) {
        console.log('✅ 슬랙 전송 성공');
      } else {
        console.log(`❌ 슬랙 전송 실패: ${res.statusCode}`);
      }
    });

    req.on('error', (error) => {
      console.error('슬랙 전송 에러:', error.message);
    });

    req.write(postData);
    req.end();
  }

  // 모니터링 시작
  start() {
    console.log('🚀 Claude Code Transcript Monitor 시작');
    console.log(`📂 프로젝트: ${this.projectDirName}`);
    console.log(`📁 모니터링 디렉토리: ${path.join(CONFIG.CLAUDE_PROJECTS_DIR, this.projectDirName)}`);
    
    if (CONFIG.SLACK_WEBHOOK_URL) {
      console.log('📢 슬랙 연동: 활성화');
    } else {
      console.log('📢 슬랙 연동: 비활성화 (SLACK_WEBHOOK_URL 환경변수 필요)');
    }

    console.log('👀 모니터링 중...\n');

    const monitor = () => {
      try {
        // 최신 transcript 파일 찾기
        const latestTranscript = this.findLatestTranscript();
        
        if (!latestTranscript) {
          console.log('transcript 파일을 찾을 수 없습니다.');
          return;
        }

        // 새 파일이면 초기화
        if (this.currentTranscriptPath !== latestTranscript) {
          console.log(`📄 새 transcript 파일: ${path.basename(latestTranscript)}`);
          this.currentTranscriptPath = latestTranscript;
          this.lastProcessedLine = 0;
        }

        // 새 메시지 읽기
        const newEntries = this.readNewMessages(latestTranscript);
        
        newEntries.forEach(entry => {
          const parsedMessage = this.parseMessage(entry);
          if (parsedMessage) {
            const slackMessage = this.formatSlackMessage(parsedMessage);
            this.sendToSlack(slackMessage);
          }
        });

      } catch (error) {
        console.error('모니터링 에러:', error.message);
      }
    };

    // 초기 실행
    monitor();
    
    // 주기적 모니터링
    setInterval(monitor, CONFIG.MONITOR_INTERVAL);
  }

  // 정리 및 종료
  stop() {
    console.log('\n🛑 모니터링 중지');
    process.exit(0);
  }
}

// 메인 실행
if (require.main === module) {
  const monitor = new TranscriptMonitor();

  // 종료 시그널 처리
  process.on('SIGINT', () => monitor.stop());
  process.on('SIGTERM', () => monitor.stop());

  // 도움말 표시
  if (process.argv.includes('--help') || process.argv.includes('-h')) {
    console.log(`
Claude Code Transcript to Slack Monitor

사용법:
  node transcript-to-slack.js

환경변수:
  SLACK_WEBHOOK_URL    슬랙 웹훅 URL (필수)

예시:
  export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
  node transcript-to-slack.js
`);
    process.exit(0);
  }

  // 모니터링 시작
  monitor.start();
}

module.exports = TranscriptMonitor;
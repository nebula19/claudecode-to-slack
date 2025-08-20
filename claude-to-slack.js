#!/usr/bin/env node

const fs = require('fs');
const https = require('https');
const path = require('path');

const SLACK_WEBHOOK_URL = 'https://hooks.slack.com/services/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';

/**
 * Slack으로 메시지 전송
 * @param {string} text - 전송할 메시지
 * @param {string} type - 메시지 타입 (user|assistant)
 * @param {string} project - 프로젝트 이름
 */
function sendToSlack(text, type = 'user', project = 'unknown') {
  const emoji = type === 'user' ? ':speech_balloon:' : (type === 'conversation' ? ':left_right_arrow:' : ':robot_face:');
  const color = type === 'user' ? '#36a64f' : (type === 'conversation' ? '#FF9500' : '#3AA3E3');
  
  const payload = {
    username: 'Claude Code Monitor',
    icon_emoji: ':claude:',
    attachments: [{
      color: color,
      fields: [
        {
          title: `${emoji} ${type === 'user' ? '사용자 질문' : (type === 'conversation' ? '대화' : 'AI 응답')}`,
          value: text.length > 2000 ? text.substring(0, 1997) + '...' : text,
          short: false
        },
        {
          title: 'Project',
          value: project,
          short: true
        }
      ],
      footer: 'Claude Code',
      ts: Math.floor(Date.now() / 1000)
    }]
  };

  const data = JSON.stringify(payload);
  const url = new URL(SLACK_WEBHOOK_URL);
  
  const options = {
    hostname: url.hostname,
    port: 443,
    path: url.pathname,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(data)
    }
  };

  const req = https.request(options, (res) => {
    console.log(`Slack response: ${res.statusCode}`);
    // 응답 데이터 소비하여 연결 해제
    res.on('data', () => {});
    res.on('end', () => {});
  });

  req.on('error', (error) => {
    console.error('Slack 전송 오류:', error);
  });

  // 타임아웃 설정 (3초)
  req.setTimeout(3000, () => {
    console.log('Slack 요청 타임아웃');
    req.destroy();
  });

  req.write(data);
  req.end();
}

/**
 * JSONL 파일에서 최신 메시지 추출
 * @param {string} transcriptPath - transcript 파일 경로
 * @returns {Object|null} 최신 메시지 객체
 */
function getLatestMessage(transcriptPath) {
  try {
    if (!fs.existsSync(transcriptPath)) {
      console.error(`Transcript 파일을 찾을 수 없습니다: ${transcriptPath}`);
      return null;
    }

    const content = fs.readFileSync(transcriptPath, 'utf8');
    const lines = content.trim().split('\n').filter(line => line.trim());
    
    if (lines.length === 0) return null;
    
    // 가장 최근 메시지 파싱
    const lastLine = lines[lines.length - 1];
    return JSON.parse(lastLine);
  } catch (error) {
    console.error('JSONL 파싱 오류:', error);
    return null;
  }
}

/**
 * JSONL 파일에서 최근 대화 쌍(사용자 질문 + AI 응답) 추출
 * @param {string} transcriptPath - transcript 파일 경로
 * @returns {Object|null} {userMessage, assistantMessage}
 */
function getLatestConversationPair(transcriptPath) {
  try {
    if (!fs.existsSync(transcriptPath)) {
      console.error(`Transcript 파일을 찾을 수 없습니다: ${transcriptPath}`);
      return null;
    }

    const content = fs.readFileSync(transcriptPath, 'utf8');
    const lines = content.trim().split('\n').filter(line => line.trim());
    
    if (lines.length === 0) return null;
    
    // 뒤에서부터 찾기
    let assistantMessage = null;
    let userMessage = null;
    
    for (let i = lines.length - 1; i >= 0; i--) {
      const message = JSON.parse(lines[i]);
      
      if (!assistantMessage && message.type === 'assistant') {
        assistantMessage = message;
      } else if (assistantMessage && !userMessage && message.type === 'user') {
        // tool_result 메시지와 hook 메시지는 제외하고 실제 사용자 입력 메시지만 찾기
        if (message.message && message.message.content && 
            typeof message.message.content === 'string' &&
            !message.message.content.includes('<user-prompt-submit-hook>') &&
            !Array.isArray(message.message.content)) {
          userMessage = message;
          break;
        }
      }
    }
    
    return { userMessage, assistantMessage };
  } catch (error) {
    console.error('대화 쌍 파싱 오류:', error);
    return null;
  }
}

/**
 * 프로젝트 이름 추출 (디렉토리명에서)
 * @param {string} transcriptPath - transcript 파일 경로
 * @returns {string} 프로젝트 이름
 */
function extractProjectName(transcriptPath) {
  const dirName = path.dirname(transcriptPath);
  const projectDir = path.basename(dirName);
  return projectDir.replace(/^-Users-[^-]+-/, '').replace(/-/g, '/');
}

/**
 * 메시지 내용 정리 (툴 호출 등 제거)
 * @param {Object} message - 메시지 객체
 * @returns {string} 정리된 텍스트
 */
function extractTextContent(message) {
  if (!message.message || !message.message.content) {
    return '[내용 없음]';
  }

  const content = message.message.content;
  
  if (typeof content === 'string') {
    return content;
  }
  
  if (Array.isArray(content)) {
    return content
      .filter(item => item.type === 'text')
      .map(item => item.text)
      .join('\n')
      .trim() || '[텍스트 내용 없음]';
  }
  
  return JSON.stringify(content);
}

/**
 * 사용자 메시지에서 순수 텍스트만 추출 (시스템 메시지 제거)
 * @param {Object} message - 사용자 메시지 객체
 * @returns {string} 순수 텍스트
 */
function extractUserPrompt(message) {
  if (!message || !message.message || !message.message.content) {
    return '[내용 없음]';
  }

  const content = message.message.content;
  
  // 문자열인 경우 그대로 반환
  if (typeof content === 'string') {
    // Caveat 메시지 제거
    return content.replace(/^Caveat:.*?\n\n/s, '').trim();
  }
  
  // 배열인 경우 text 타입만 추출
  if (Array.isArray(content)) {
    const textContent = content
      .filter(item => item.type === 'text')
      .map(item => item.text)
      .join('\n')
      .trim();
      
    // Caveat 메시지 제거
    return textContent.replace(/^Caveat:.*?\n\n/s, '').trim() || '[텍스트 내용 없음]';
  }
  
  console.log('디버그 - content 타입:', typeof content, content);
  return JSON.stringify(content);
}

/**
 * Hook 이벤트 처리 메인 함수
 */
function main() {
  try {
    // stdin으로부터 hook 데이터 읽기
    let inputData = '';
    
    if (process.stdin.isTTY) {
      console.error('이 스크립트는 Claude Code hook으로만 실행되어야 합니다.');
      process.exit(1);
    }
    
    process.stdin.on('data', (chunk) => {
      inputData += chunk;
    });
    
    process.stdin.on('end', () => {
      try {
        const hookData = JSON.parse(inputData);
        console.log('Hook 데이터 수신:', JSON.stringify(hookData, null, 2));
        
        const { hook_event_name, transcript_path, prompt } = hookData;
        const projectName = extractProjectName(transcript_path || '');
        
        // UserPromptSubmit hook의 경우 prompt 필드에서 직접 사용자 메시지 가져오기
        if (hook_event_name === 'UserPromptSubmit' && prompt) {
          console.log(`사용자 프롬프트를 Slack으로 전송: ${prompt.substring(0, 100)}...`);
          sendToSlack(prompt, 'user', projectName);
          return;
        }
        
        // Stop hook의 경우 transcript 파일에서 대화 쌍 가져오기
        if (hook_event_name === 'Stop' && transcript_path) {
          const conversationPair = getLatestConversationPair(transcript_path);
          
          if (!conversationPair || !conversationPair.assistantMessage) {
            console.error('AI 응답을 찾을 수 없습니다.');
            return;
          }
          
          // 사용자 질문과 AI 응답을 함께 전송
          const userText = conversationPair.userMessage ? 
            extractUserPrompt(conversationPair.userMessage) : '[질문 없음]';
          const assistantText = extractTextContent(conversationPair.assistantMessage);
          
          const combinedMessage = `**👤 질문:**\n${userText}\n\n**🤖 답변:**\n${assistantText}`;
          
          console.log('대화 쌍을 Slack으로 전송:', combinedMessage.substring(0, 100) + '...');
          sendToSlack(combinedMessage, 'conversation', projectName);
          return;
        }
        
        console.log(`처리되지 않은 hook 이벤트: ${hook_event_name}`);
        
      } catch (error) {
        console.error('Hook 데이터 파싱 오류:', error);
      }
    });
    
  } catch (error) {
    console.error('Hook 처리 오류:', error);
  }
}

// 스크립트가 직접 실행될 때만 main 함수 호출
if (require.main === module) {
  main();
}

module.exports = { sendToSlack, getLatestMessage, extractProjectName, extractTextContent };
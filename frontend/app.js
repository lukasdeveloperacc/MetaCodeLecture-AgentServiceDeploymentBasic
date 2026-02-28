/**
 * RAG/Agent Demo Service - Frontend
 * Server-Sent Events (SSE) 기반 Streaming 응답 처리
 */

const API_BASE_URL = 'http://localhost:8000';

// 현재 활성화된 EventSource 추적
let currentEventSource = null;

// 탭 전환
document.querySelectorAll('.tab').forEach(tab => {
    tab.addEventListener('click', () => {
        const tabName = tab.dataset.tab;

        // 모든 탭 비활성화
        document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));

        // 선택한 탭 활성화
        tab.classList.add('active');
        document.getElementById(`${tabName}-tab`).classList.add('active');

        // 기존 EventSource 종료
        closeEventSource();

        // 응답 영역 초기화
        clearResponse(tabName);
    });
});

// Ask 폼 제출
document.getElementById('ask-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const question = document.getElementById('ask-input').value.trim();
    if (!question) return;

    await handleStreaming('ask', question);
});

// RAG 폼 제출
document.getElementById('rag-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const question = document.getElementById('rag-input').value.trim();
    if (!question) return;

    await handleStreaming('rag', question);
});

// Agent 폼 제출
document.getElementById('agent-form').addEventListener('submit', async (e) => {
    e.preventDefault();
    const question = document.getElementById('agent-input').value.trim();
    if (!question) return;

    await handleStreaming('agent', question);
});

/**
 * SSE Streaming 처리
 */
async function handleStreaming(endpoint, question) {
    closeEventSource();

    const responseBox = document.getElementById(`${endpoint}-response`);
    const traceInfo = document.getElementById(`${endpoint}-trace`);
    const submitBtn = document.querySelector(`#${endpoint}-form button[type="submit"]`);

    // UI 초기화
    clearResponse(endpoint);
    responseBox.classList.add('streaming');
    submitBtn.disabled = true;
    submitBtn.innerHTML = '<span class="spinner"></span>전송 중...';

    // EventSource URL 생성
    const url = `${API_BASE_URL}/${endpoint}`;

    try {
        // POST 요청으로 SSE 시작 (URL에 쿼리 파라미터로 전달)
        const eventSource = new EventSource(`${url}?question=${encodeURIComponent(question)}`);
        currentEventSource = eventSource;

        let fullResponse = '';
        let traceId = null;

        eventSource.onmessage = (event) => {
            const data = JSON.parse(event.data);

            // Trace ID 저장
            if (data.trace_id) {
                traceId = data.trace_id;
            }

            // 이벤트 타입별 처리
            switch (data.type) {
                case 'classification':
                    // Agent 분류 결과 표시
                    showClassification(data.result);
                    break;

                case 'sources':
                    // RAG/Agent 소스 문서 표시
                    showSources(endpoint, data.data);
                    break;

                case 'token':
                    // 스트리밍 토큰 추가
                    fullResponse += data.content;
                    responseBox.textContent = fullResponse;
                    break;

                case 'done':
                    // 완료
                    responseBox.classList.remove('streaming');
                    traceInfo.textContent = `✓ 완료 | Trace ID: ${traceId}`;
                    submitBtn.disabled = false;
                    submitBtn.textContent = '전송';
                    eventSource.close();
                    currentEventSource = null;
                    break;

                case 'error':
                    // 에러
                    responseBox.classList.remove('streaming');
                    responseBox.classList.add('error');
                    responseBox.textContent = `오류 발생: ${data.message}`;
                    traceInfo.textContent = `✗ 오류 | Trace ID: ${traceId}`;
                    submitBtn.disabled = false;
                    submitBtn.textContent = '전송';
                    eventSource.close();
                    currentEventSource = null;
                    break;
            }
        };

        eventSource.onerror = (error) => {
            console.error('SSE Error:', error);

            // 연결 상태 확인
            if (eventSource.readyState === EventSource.CLOSED) {
                responseBox.classList.remove('streaming');

                if (!fullResponse) {
                    responseBox.classList.add('error');
                    responseBox.textContent = '서버 연결 오류 발생. 백엔드 서버가 실행 중인지 확인하세요.';
                }

                submitBtn.disabled = false;
                submitBtn.textContent = '전송';
                eventSource.close();
                currentEventSource = null;
            }
        };

    } catch (error) {
        console.error('Request Error:', error);
        responseBox.classList.remove('streaming');
        responseBox.classList.add('error');
        responseBox.textContent = `요청 오류: ${error.message}`;
        submitBtn.disabled = false;
        submitBtn.textContent = '전송';
    }
}

/**
 * Agent 분류 결과 표시
 */
function showClassification(classification) {
    const classificationArea = document.getElementById('agent-classification');
    classificationArea.classList.add('show');

    const badgeClass = classification.toLowerCase();
    const badgeText = classification === 'RAG' ? 'RAG 경로' : 'Direct LLM 경로';

    classificationArea.innerHTML = `
        <div style="margin-bottom: 0.5rem; color: var(--text-secondary); font-size: 0.9rem;">
            분류 결과:
        </div>
        <span class="classification-badge ${badgeClass}">${badgeText}</span>
    `;
}

/**
 * RAG/Agent 소스 문서 표시
 */
function showSources(endpoint, sources) {
    const sourcesArea = document.getElementById(`${endpoint}-sources`);
    sourcesArea.classList.add('show');

    let html = '<div class="sources-title">📚 참고 문서:</div>';

    sources.forEach((source, index) => {
        const filename = source.metadata?.source || 'Unknown';
        const content = source.content || '';

        html += `
            <div class="source-item">
                <div class="source-filename">${index + 1}. ${filename}</div>
                <div class="source-content">${content}...</div>
            </div>
        `;
    });

    sourcesArea.innerHTML = html;
}

/**
 * 응답 영역 초기화
 */
function clearResponse(endpoint) {
    const responseBox = document.getElementById(`${endpoint}-response`);
    const traceInfo = document.getElementById(`${endpoint}-trace`);
    const sourcesArea = document.getElementById(`${endpoint}-sources`);
    const classificationArea = document.getElementById(`${endpoint}-classification`);

    responseBox.textContent = '';
    responseBox.className = 'response-box';
    traceInfo.textContent = '';

    if (sourcesArea) {
        sourcesArea.classList.remove('show');
        sourcesArea.innerHTML = '';
    }

    if (classificationArea) {
        classificationArea.classList.remove('show');
        classificationArea.innerHTML = '';
    }
}

/**
 * EventSource 종료
 */
function closeEventSource() {
    if (currentEventSource) {
        currentEventSource.close();
        currentEventSource = null;
    }
}

// 페이지 종료 시 EventSource 정리
window.addEventListener('beforeunload', closeEventSource);

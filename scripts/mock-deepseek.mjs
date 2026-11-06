// Minimal OpenAI-compatible SSE mock for DSHKit integration tests.
// Usage: node mock-deepseek.mjs [port]
import http from 'node:http';

const port = Number(process.argv[2] || 18081);

function sse(res, payload) {
  res.write(`data: ${JSON.stringify(payload)}\n\n`);
}

const server = http.createServer(async (req, res) => {
  if (req.method !== 'POST' || !req.url.endsWith('/chat/completions')) {
    res.writeHead(404).end('not found');
    return;
  }
  let body = '';
  for await (const chunk of req) body += chunk;
  let parsed = {};
  try { parsed = JSON.parse(body); } catch {}
  const messages = parsed.messages || [];
  const hasToolResult = messages.some((m) => m.role === 'tool');
  console.log(`[mock] request model=${parsed.model} messages=${messages.length} tools=${(parsed.tools || []).length} toolResult=${hasToolResult}`);

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    Connection: 'keep-alive',
  });

  const lastUser = [...messages].reverse().find((m) => m.role === 'user');
  const wantsWrite = String(lastUser?.content || '').toLowerCase().includes('write');
  if (!hasToolResult) {
    const call = wantsWrite
      ? {
          index: 0,
          id: 'call_mock_write',
          type: 'function',
          function: { name: 'write_file', arguments: JSON.stringify({ path: 'out.txt', content: 'written by mock\n' }) },
        }
      : {
          index: 0,
          id: 'call_mock_1',
          type: 'function',
          function: { name: 'read_file', arguments: JSON.stringify({ path: 'hello.txt' }) },
        };
    sse(res, { choices: [{ index: 0, delta: { tool_calls: [call] }, finish_reason: null }] });
    sse(res, { choices: [{ index: 0, delta: {}, finish_reason: 'tool_calls' }] });
    sse(res, { choices: [], usage: { prompt_tokens: 42, completion_tokens: 8 } });
    res.write('data: [DONE]\n\n');
    res.end();
    return;
  }

  const chunks = wantsWrite
    ? ['Wrote ', 'out.txt ', 'after approval.']
    : ['The file ', 'contains: ', 'hello from mock'];
  for (const text of chunks) {
    sse(res, { choices: [{ index: 0, delta: { content: text }, finish_reason: null }] });
    await new Promise((r) => setTimeout(r, 25));
  }
  sse(res, { choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] });
  sse(res, { choices: [], usage: { prompt_tokens: 55, completion_tokens: 12 } });
  res.write('data: [DONE]\n\n');
  res.end();
});

server.listen(port, '127.0.0.1', () => {
  console.log(`mock deepseek listening on http://127.0.0.1:${port}`);
});

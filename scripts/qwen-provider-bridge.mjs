#!/usr/bin/env node
// Persistent JSONL bridge to Qwen Code's official OpenAI provider layer.
// It exposes raw model responses only; Hermes remains the sole agent/tool loop.

import { createInterface } from 'node:readline';
import { readFile, readdir } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
import path from 'node:path';

const qwenRoot = process.env.QWEN_CODE_ROOT;
if (!qwenRoot) throw new Error('QWEN_CODE_ROOT is required');

async function loadProviderFactory() {
  const chunks = path.join(qwenRoot, 'chunks');
  for (const name of await readdir(chunks)) {
    if (!name.endsWith('.js')) continue;
    const file = path.join(chunks, name);
    const source = await readFile(file, 'utf8');
    if (!source.includes('function determineProvider') || !source.includes('createOpenAIContentGenerator')) continue;
    const module = await import(pathToFileURL(file).href);
    if (typeof module.determineProvider === 'function') return module.determineProvider;
  }
  throw new Error('Compatible Qwen Code provider module was not found');
}

const determineProvider = await loadProviderFactory();
const config = {
  authType: 'openai',
  apiKey: process.env.OPENAI_API_KEY,
  baseUrl: process.env.OPENAI_BASE_URL || 'https://agentrouter.org/v1',
  timeout: 900000,
  maxRetries: 2,
};
const cliConfig = {
  getCliVersion: () => process.env.QWEN_CODE_VERSION || '0.19.3',
  getProxy: () => undefined,
};
const provider = determineProvider(config, cliConfig);
const client = provider.buildClient();

function emit(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

async function streamRequest(request, onChunk) {
  const body = {
    model: request.model || 'glm-5.2',
    messages: request.messages || [],
    stream: true,
    stream_options: { include_usage: true },
  };
  if (Array.isArray(request.tools) && request.tools.length) body.tools = request.tools;
  if (request.tool_choice !== undefined && request.tool_choice !== null) body.tool_choice = request.tool_choice;
  if (request.reasoning_effort === 'none') {
    body.thinking = { type: 'disabled' };
    body.reasoning = false;
  } else if (request.reasoning_effort) {
    body.thinking = { type: 'enabled' };
    body.reasoning = { effort: request.reasoning_effort === 'xhigh' ? 'max' : request.reasoning_effort };
  }
  for (const key of ['temperature', 'max_tokens', 'max_completion_tokens', 'top_p', 'stop']) {
    if (request[key] !== undefined && request[key] !== null) body[key] = request[key];
  }
  const stream = await client.chat.completions.create(body);
  for await (const chunk of stream) await onChunk(chunk);
}

if (process.argv.includes('--check')) {
  let content = '';
  try {
    await streamRequest({
      model: process.env.OPENAI_MODEL || 'glm-5.2',
      messages: [{ role: 'user', content: 'Reply exactly AGENTROUTER_GLM52_OK' }],
      reasoning_effort: 'none',
      max_completion_tokens: 128,
    }, (chunk) => {
      content += chunk?.choices?.[0]?.delta?.content || '';
    });
    if (content.trim() !== 'AGENTROUTER_GLM52_OK') throw new Error(`Unexpected check response: ${content.trim()}`);
    process.stdout.write('AGENTROUTER_GLM52_OK\n');
  } catch (error) {
    process.stderr.write(`${String(error?.message || error)}\n`);
    process.exitCode = 1;
  }
} else {
const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
for await (const line of input) {
  const cleanLine = line.replace(/^\uFEFF/, '');
  if (!cleanLine.trim()) continue;
  let request;
  try {
    request = JSON.parse(cleanLine);
    await streamRequest(request, (chunk) => emit({ id: request.id, type: 'chunk', chunk }));
    emit({ id: request.id, type: 'done' });
  } catch (error) {
    emit({ id: request?.id, type: 'error', error: String(error?.message || error) });
  }
}
}

const { ClassicLevel } = require('classic-level');

const dbPath = process.argv[2];
if (!dbPath) throw new Error('LevelDB path is required');
const selectedModel = process.argv[3] || 'glm-5.2';
const selectedProvider = process.argv[4] || 'copilot-acp';

const db = new ClassicLevel(dbPath, { keyEncoding: 'buffer', valueEncoding: 'buffer' });
const wanted = new Map([
  ['hermes.desktop.composer.model', selectedModel],
  ['hermes.desktop.composer.provider', selectedProvider],
]);
const defaultKey = name => Buffer.from(`_file://\x00\x01${name}`, 'utf8');

(async () => {
  await db.open();
  const found = new Map();
  let lastSessionKey = null;
  for await (const [key] of db.iterator()) {
    const text = key.toString('utf8');
    for (const name of wanted.keys()) if (text.endsWith(name)) found.set(name, Buffer.from(key));
    if (text.endsWith('hermes.desktop.lastSessionId')) lastSessionKey = Buffer.from(key);
  }

  const ops = [];
  for (const [name, value] of wanted) {
    const key = found.get(name) || defaultKey(name);
    found.set(name, key);
    ops.push({ type: 'put', key, value: Buffer.from(`\x01${value}`, 'utf8') });
  }
  if (lastSessionKey) ops.push({ type: 'del', key: lastSessionKey });
  await db.batch(ops);

  for (const [name, expected] of wanted) {
    const actual = (await db.get(found.get(name))).subarray(1).toString('utf8');
    if (actual !== expected) throw new Error(`Verification failed for ${name}`);
    console.log(`${name}=${actual}`);
  }
  await db.close();
})().catch(async error => {
  try { await db.close(); } catch {}
  console.error(error.stack || String(error));
  process.exit(1);
});

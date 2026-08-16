import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { persistCredentialsToDshEnv, upsertEnv } from '../dist/setup.js';

test('upsertEnv preserves unrelated values and replaces credentials', () => {
  const result = upsertEnv('OTHER=kept\nQQBOT_SECRET="old"\n', {
    QQBOT_APPID: 'new-app',
    QQBOT_SECRET: 'new-secret',
  });
  assert.match(result, /OTHER=kept/);
  assert.match(result, /QQBOT_APPID="new-app"/);
  assert.match(result, /QQBOT_SECRET="new-secret"/);
  assert.equal(result.includes('old'), false);
});

test('credential persistence never logs the secret', () => {
  const home = mkdtempSync(join(tmpdir(), 'dsh-qqbot-safe-'));
  const logs = [];
  const logger = { info: (line) => logs.push(line), warn: (line) => logs.push(line) };
  const secret = 'do-not-log-this';
  assert.equal(persistCredentialsToDshEnv({
    appId: '12345',
    appSecret: secret,
    userOpenid: 'private-user-openid',
  }, home, logger), true);
  const saved = readFileSync(join(home, '.env'), 'utf8');
  assert.match(saved, /QQBOT_SECRET="do-not-log-this"/);
  assert.match(saved, /QQBOT_C2C_ALLOW="private-user-openid"/);
  assert.equal(logs.join('\n').includes(secret), false);
});

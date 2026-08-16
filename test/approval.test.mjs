import test from 'node:test';
import assert from 'node:assert/strict';
import { parseApprovalCommand, QqApprovalController } from '../dist/approval.js';

test('approval parser accepts explicit commands and ignores ordinary chat', () => {
  assert.deepEqual(parseApprovalCommand('/approve A1B2C3'), {
    outcome: 'allowed-once',
    code: 'A1B2C3',
  });
  assert.deepEqual(parseApprovalCommand('拒绝 a1b2c3'), {
    outcome: 'rejected',
    code: 'A1B2C3',
  });
  assert.equal(parseApprovalCommand('允许这次操作'), null);
});

test('approval is one-shot and bound to the originating QQ sender', async () => {
  const agent = {};
  const record = {
    agent,
    scope: 'c2c',
    peerId: 'user-openid',
    senderId: 'user-openid',
    replyTarget: { scope: 'c2c', targetId: 'user-openid', msgId: 'msg-1' },
  };
  const sent = [];
  const sender = {
    async sendMarkdown(target, content) {
      sent.push({ target, content });
    },
  };
  const logger = { info() {}, warn() {}, error() {}, debug() {} };
  const manager = { findByAgent(value) { return value === agent ? record : undefined; } };
  const controller = new QqApprovalController(manager, sender, logger, 5000);

  const decision = controller.request(
    { agent, toolName: 'pwsh', reason: 'write E:\\111' },
    async () => 'unavailable',
  );
  await new Promise((resolve) => setImmediate(resolve));
  const code = sent[0].content.match(/\/approve ([A-F0-9]{6})/)[1];

  const consumed = await controller.handleInbound({
    message: { kind: 'c2c', senderId: 'user-openid', content: `/approve ${code}` },
    replyTarget: record.replyTarget,
  });

  assert.equal(consumed, true);
  assert.equal(await decision, 'allowed-once');
  assert.match(sent.at(-1).content, /已允许本次操作/);
  controller.dispose();
});

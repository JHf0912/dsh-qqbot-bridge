/** QQ Bot QR onboarding with secret-safe persistence. */
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { qrConnect } from '@tencent-connect/qqbot-connector';

export interface SetupCredentials {
  appId: string;
  appSecret: string;
  /** QQ Open Platform user OpenID returned by the official bind flow. */
  userOpenid?: string;
}

interface SetupLogger {
  info(msg: string, ...args: unknown[]): void;
  warn(msg: string, ...args: unknown[]): void;
}

export async function runQrSetup(source = 'dsh-qqbot-safe'): Promise<SetupCredentials | null> {
  console.log('\n══════════════════════════════════════════════════════');
  console.log('  QQ Bot 凭据未配置，启动腾讯官方扫码绑定');
  console.log('══════════════════════════════════════════════════════\n');

  try {
    console.log('请使用手机 QQ 扫描下方二维码完成绑定...\n');
    const credentials = await qrConnect({ source });
    const cred = credentials?.[0];
    if (!cred?.appId || !cred.appSecret) {
      console.error('[im-qqbot] 扫码未返回有效凭据');
      return null;
    }
    console.log(`\n✔ 绑定成功！AppID: ${maskAppId(cred.appId)}\n`);
    return {
      appId: cred.appId,
      appSecret: cred.appSecret,
      ...(cred.userOpenid ? { userOpenid: cred.userOpenid } : {}),
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`[im-qqbot] 扫码绑定失败: ${message}`);
    console.error('[im-qqbot] 也可以在启动环境中设置 QQBOT_APPID 和 QQBOT_SECRET。');
    return null;
  }
}

/**
 * Save QQ credentials to DSH_HOME/.env without ever writing them to the profile
 * patch or terminal. Existing unrelated .env lines are preserved.
 */
export function persistCredentialsToDshEnv(
  credentials: SetupCredentials,
  dshHome?: string,
  logger: SetupLogger = console,
): boolean {
  const home = resolve(dshHome || process.env.DSH_HOME || join(homedir(), '.dsh'));
  const envPath = join(home, '.env');

  try {
    mkdirSync(dirname(envPath), { recursive: true, mode: 0o700 });
    const existing = existsSync(envPath) ? readFileSync(envPath, 'utf8') : '';
    const values: Record<string, string> = {
      QQBOT_APPID: credentials.appId,
      QQBOT_SECRET: credentials.appSecret,
    };
    if (credentials.userOpenid) values.QQBOT_C2C_ALLOW = credentials.userOpenid;
    const updated = upsertEnv(existing, values);
    const temporary = `${envPath}.${process.pid}.${Date.now()}.tmp`;
    writeFileSync(temporary, updated, { encoding: 'utf8', mode: 0o600 });
    renameSync(temporary, envPath);
    chmodSync(envPath, 0o600);
    logger.info(`✔ QQ Bot 凭据已保存到 DSH 用户凭据层: ${envPath}`);
    logger.info('  Secret 未写入 cordis.patch.yml，也不会打印到终端');
    if (credentials.userOpenid) logger.info('  扫码用户 OpenID 已写入本机私聊白名单');
    return true;
  } catch (error) {
    logger.warn(`凭据保存失败: ${error instanceof Error ? error.message : String(error)}`);
    logger.warn('请在启动环境中设置 QQBOT_APPID 和 QQBOT_SECRET；不要提交到 Git。');
    return false;
  }
}

export function upsertEnv(content: string, values: Record<string, string>): string {
  const pending = new Map(Object.entries(values));
  const lines = content.replace(/\r\n/g, '\n').split('\n');
  const output: string[] = [];

  for (const line of lines) {
    const match = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=/.exec(line);
    const key = match?.[1];
    if (key && pending.has(key)) {
      output.push(`${key}=${quoteEnv(pending.get(key) ?? '')}`);
      pending.delete(key);
    } else if (line.length > 0) {
      output.push(line);
    }
  }

  for (const [key, value] of pending) output.push(`${key}=${quoteEnv(value)}`);
  return `${output.join('\n')}\n`;
}

function quoteEnv(value: string): string {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n')}"`;
}

function maskAppId(appId: string): string {
  if (appId.length <= 4) return '****';
  return `${appId.slice(0, 2)}***${appId.slice(-2)}`;
}

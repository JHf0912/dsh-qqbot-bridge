import { readdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join, relative } from 'node:path';

const root = new URL('../', import.meta.url).pathname.replace(/^\/(.:\/)/, '$1');
const ignoredDirectories = new Set(['.git', 'dist', 'node_modules', 'coverage', 'qqbot-workspace']);
const textExtensions = new Set([
  '', '.cjs', '.js', '.json', '.md', '.mjs', '.ps1', '.sh', '.ts', '.txt', '.yaml', '.yml',
]);
const findings = [];

function unquote(value) {
  const trimmed = value.trim().replace(/\s+#.*$/, '').trim();
  if (
    trimmed.length >= 2
    && ((trimmed.startsWith('"') && trimmed.endsWith('"'))
      || (trimmed.startsWith("'") && trimmed.endsWith("'")))
  ) {
    return trimmed.slice(1, -1).trim();
  }
  return trimmed;
}

function looksLikeCredential(key, rawValue) {
  const value = unquote(rawValue);
  if (!value || /^(?:\.{3}|\*{3}|<.+>)$/.test(value) || value.startsWith('${')) return false;
  if (/(?:你的|机器人|用户|示例|占位|example|placeholder)/i.test(value)) return false;

  switch (key) {
    case 'QQBOT_APPID':
      return /^\d{6,20}$/.test(value);
    case 'QQBOT_C2C_ALLOW':
      return /(?:^|[,\s])[A-Fa-f0-9]{32}(?:$|[,\s])/.test(value);
    case 'DEEPSEEK_API_KEY':
      return /^sk-[A-Za-z0-9_-]{16,}$/.test(value);
    case 'QQBOT_SECRET':
      return value.length >= 16 && /^[A-Za-z0-9._~+/=-]+$/.test(value);
    default:
      return false;
  }
}

function walk(directory) {
  for (const entry of readdirSync(directory)) {
    if (ignoredDirectories.has(entry)) continue;
    const path = join(directory, entry);
    const stat = statSync(path);
    if (stat.isDirectory()) {
      walk(path);
      continue;
    }
    if (!textExtensions.has(extname(entry).toLowerCase())) continue;
    inspect(path);
  }
}

function inspect(path) {
  const name = relative(root, path).replaceAll('\\', '/');
  const text = readFileSync(path, 'utf8');
  const lines = text.split(/\r?\n/);
  lines.forEach((line, index) => {
    const env = /^\s*(?:export\s+)?(QQBOT_APPID|QQBOT_SECRET|QQBOT_C2C_ALLOW|DEEPSEEK_API_KEY)\s*=\s*(.*)$/.exec(line);
    if (env && looksLikeCredential(env[1], env[2])) {
      findings.push(`${name}:${index + 1} contains a non-placeholder ${env[1]}`);
    }
    if (/^\s*-\s*["']?[A-Fa-f0-9]{32}["']?\s*$/.test(line)) {
      findings.push(`${name}:${index + 1} looks like an inline QQ OpenID`);
    }
    if (/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/.test(line)) {
      findings.push(`${name}:${index + 1} contains a private key header`);
    }
  });
}

walk(root);
if (findings.length > 0) {
  console.error('Privacy check failed:');
  for (const finding of findings) console.error(`- ${finding}`);
  process.exitCode = 1;
} else {
  console.log('Privacy check passed: no committed credentials or inline QQ OpenIDs detected.');
}

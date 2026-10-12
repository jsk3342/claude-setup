import { copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const source = dirname(fileURLToPath(import.meta.url))
const configDir = resolve(process.argv[2] || process.env.CLAUDE_CONFIG_DIR || join(homedir(), '.claude'))
const modeDir = join(configDir, 'claude-setup', 'usage-mode')
const settingsPath = join(configDir, 'settings.json')
const statePath = join(modeDir, 'previous-statusline.json')

function readObject(path) {
  const value = JSON.parse(readFileSync(path, 'utf8').replace(/^\uFEFF/, ''))
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${path}: JSON 객체가 필요합니다.`)
  return value
}

function quote(path) {
  if (process.platform === 'win32') {
    if (/["%$`\r\n]/.test(path)) throw new Error('명령 경로에 지원하지 않는 문자가 있습니다. 기존 설정은 유지합니다.')
    return `"${path.replaceAll('\\', '/')}"`
  }
  return `'${path.replace(/'/g, "'\\''")}'`
}

const settings = existsSync(settingsPath) ? readObject(settingsPath) : {}
const command = `${process.platform === 'win32' ? 'node' : quote(process.execPath)} ${quote(join(modeDir, 'usage-line.mjs'))}`
let previous = settings.statusLine ?? null
if (previous && (previous.type !== 'command' || typeof previous.command !== 'string')) {
  throw new Error('기존 statusLine 형식을 연결할 수 없습니다. 설정을 덮어쓰지 않습니다.')
}
if (previous?.command === command) {
  if (!existsSync(statePath)) throw new Error('이전 상태줄 기록이 없습니다. 자동 재설치를 중단합니다.')
  previous = readObject(statePath).statusLine
} else if (previous?.command?.includes(join(modeDir, 'usage-line.mjs'))) {
  throw new Error('다른 Node 경로로 설치된 사용량 모드입니다. 기존 연결을 확인한 뒤 변경하세요.')
}

mkdirSync(modeDir, { recursive: true })
for (const name of ['usage-line.mjs', 'render.mjs', 'LICENSE']) {
  copyFileSync(join(source, name), join(modeDir, name))
}
// Verify installed imports before touching the user's settings.
await import(pathToFileURL(join(modeDir, 'render.mjs')))
if (existsSync(settingsPath)) {
  copyFileSync(settingsPath, `${settingsPath}.claude-setup-${Date.now()}.bak`)
}
writeFileSync(statePath, JSON.stringify({ statusLine: previous }, null, 2) + '\n', { mode: 0o600 })
settings.statusLine = { ...(settings.statusLine || {}), type: 'command', command }
const tempPath = `${settingsPath}.${process.pid}.tmp`
writeFileSync(tempPath, JSON.stringify(settings, null, 2) + '\n', { mode: 0o600, flag: 'wx' })
renameSync(tempPath, settingsPath)
console.log('사용량 모드 연결 완료 · 기존 상태줄과 다른 설정은 유지했습니다.')
console.log('한도 숫자는 계정의 첫 응답 뒤 표시될 수 있습니다. 미확인 값은 0으로 표시하지 않습니다.')

import { execFileSync, spawnSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { render } from './render.mjs'

function runPrevious(command, input) {
  const options = { input, encoding: 'utf8', timeout: 3000 }
  if (process.platform !== 'win32') return spawnSync(command, { ...options, shell: true })
  const candidates = [process.env.CLAUDE_CODE_GIT_BASH_PATH]
  for (const prefix of [process.env.ProgramFiles, process.env.ProgramW6432]) {
    if (prefix) candidates.push(join(prefix, 'Git', 'bin', 'bash.exe'))
  }
  const scoop = process.env.SCOOP || (process.env.USERPROFILE && join(process.env.USERPROFILE, 'scoop'))
  if (scoop) candidates.push(join(scoop, 'apps', 'git', 'current', 'bin', 'bash.exe'))
  try {
    for (const git of execFileSync('where.exe', ['git.exe'], { encoding: 'utf8', timeout: 1000 }).trim().split(/\r?\n/)) {
      candidates.push(join(dirname(git), 'bash.exe'), join(dirname(git), '..', 'bin', 'bash.exe'))
    }
  } catch { /* Git Bash is optional; Claude uses PowerShell when absent. */ }
  const bash = candidates.find(path => path && existsSync(path))
  return bash
    ? spawnSync(bash, ['-c', command], options)
    : spawnSync('powershell.exe', ['-NoProfile', '-Command', command], options)
}

let stdin = ''
process.stdin.setEncoding('utf8')
for await (const chunk of process.stdin) stdin += chunk
const lines = []
try {
  const previous = JSON.parse(readFileSync(join(dirname(fileURLToPath(import.meta.url)), 'previous-statusline.json'), 'utf8')).statusLine
  if (previous?.type === 'command' && previous.command) {
    const run = runPrevious(previous.command, stdin)
    const output = run.stdout?.trimEnd()
    if (output) lines.push(output)
  }
} catch { /* A broken previous command must not hide the usage line. */ }

try {
  const input = JSON.parse(stdin)
  const pct = input?.context_window?.used_percentage
  lines.push(`대화 컨텍스트: ${Number.isFinite(pct) ? `${Math.round(pct)}%` : '확인 전'}`)
  // Reuse Kai's existing renderer, without personal files or quota logging.
  const usage = render(input, Date.now() / 1000)
  lines.push(usage || '사용 한도: 확인 전 (계정·첫 응답에 따라 표시)')
} catch { /* Invalid input leaves the original status line alone. */ }
if (lines.length) process.stdout.write(lines.join('\n') + '\n')

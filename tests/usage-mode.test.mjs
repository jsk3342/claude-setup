import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = dirname(dirname(fileURLToPath(import.meta.url)))
function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), "usage-mode with space and 'quote-"))
  t.after(() => rmSync(dir, { recursive: true, force: true }))
  return dir
}
function install(dir) {
  return spawnSync(process.execPath, [join(root, 'usage-mode/install.mjs'), dir], { encoding: 'utf8' })
}
const read = path => JSON.parse(readFileSync(path, 'utf8'))
const strip = text => text.replace(/\x1b\[[0-9;]*m/g, '')

test('preserves other settings and previous output, and does not chain itself on reinstall', t => {
  const dir = fixture(t)
  const path = join(dir, 'settings.json')
  const original = { permissions: { deny: ['Read(secret)'] }, env: { EXAMPLE: 'kept' }, statusLine: { type: 'command', command: 'echo original-line', padding: 2 } }
  writeFileSync(path, JSON.stringify(original))
  assert.equal(install(dir).status, 0)
  assert.equal(install(dir).status, 0)
  const configured = read(path)
  assert.deepEqual(configured.permissions, original.permissions)
  assert.deepEqual(configured.env, original.env)
  assert.equal(configured.statusLine.padding, 2)
  const state = read(join(dir, 'claude-setup/usage-mode/previous-statusline.json'))
  assert.deepEqual(state.statusLine, original.statusLine)
  assert.ok(readdirSync(dir).some(name => name.endsWith('.bak')))
  // Execute the actual configured shell command, including paths with spaces/quotes.
  const output = spawnSync(configured.statusLine.command, { shell: true, input: JSON.stringify({ context_window: { used_percentage: 37 }, rate_limits: { five_hour: { used_percentage: 17 } } }), encoding: 'utf8' })
  assert.equal(output.status, 0, output.stderr)
  assert.match(output.stdout, /original-line/)
  assert.match(strip(output.stdout), /컨텍스트: 37%/)
  assert.match(strip(output.stdout), /5h.*17%/)
})

test('invalid JSON and unsupported statusLine fail without overwriting', t => {
  const dir = fixture(t)
  const path = join(dir, 'settings.json')
  for (const text of ['{broken', JSON.stringify({ statusLine: { type: 'other' } }), '[]']) {
    writeFileSync(path, text)
    assert.notEqual(install(dir).status, 0)
    assert.equal(readFileSync(path, 'utf8'), text)
    assert.ok(!existsSync(join(dir, 'claude-setup/usage-mode/previous-statusline.json')))
  }
})

test('missing quota is unknown, and a failed original status line does not hide the mode', t => {
  const dir = fixture(t)
  writeFileSync(join(dir, 'settings.json'), JSON.stringify({ statusLine: { type: 'command', command: 'exit 1' } }))
  assert.equal(install(dir).status, 0)
  const command = read(join(dir, 'settings.json')).statusLine.command
  const run = spawnSync(command, { shell: true, input: '{}', encoding: 'utf8' })
  assert.equal(run.status, 0)
  assert.match(run.stdout, /컨텍스트: 확인 전/)
  assert.match(run.stdout, /사용 한도: 확인 전/)
  assert.doesNotMatch(run.stdout, /0%/)
  const bad = spawnSync(command, { shell: true, input: '{broken', encoding: 'utf8' })
  assert.equal(bad.status, 0)
  assert.equal(bad.stdout, '')
})

test('a later user statusline change is preserved on the next installation', t => {
  const dir = fixture(t)
  assert.equal(install(dir).status, 0)
  const path = join(dir, 'settings.json')
  const settings = read(path)
  settings.statusLine = { type: 'command', command: 'echo newer-user-line' }
  writeFileSync(path, JSON.stringify(settings))
  assert.equal(install(dir).status, 0)
  assert.equal(read(join(dir, 'claude-setup/usage-mode/previous-statusline.json')).statusLine.command, 'echo newer-user-line')
})

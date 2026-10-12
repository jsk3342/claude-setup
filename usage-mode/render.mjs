// 하단 사용량 줄: 상태줄 입력(rate_limits·prompt_cache)으로 그린다. 순수 함수(Node import 없음)라 테스트가 그대로 불러 쓴다.
// 가져온 곳:
//   줄 모양(색·막대 그라데이션·남은 시간 표기) = usage-band(CC-Usage-Band 60cd609) hooks/register.tsx
//   7일 페이스 = ClaudeBar UsageQuota.dailyBudgetRemainingDelta + StatusBarUsageLabel.paceText/paceColor
//   캐시 남은 시간 = cache-clock(hamzafer/claude-code-mods adf9d72) statusline/render.mjs
// 컨텍스트는 윗줄(원래 상태줄)에 있으니 넣지 않는다(Kai 10/7).

const HUE = { five: '#5cc4d6' }
const RED = '#e5685f'
const AMBER = '#e8c35f'
const GREEN = '#72cf9f'
const ORANGE = '#f0a24b'
const TRACK = '#4a4f5c'
const BAR_CELLS = 8
// 5시간 한도: Usage Quota mod의 75% 노랑 / 90% 빨강
const LIMIT_AT = { warn: 75, alert: 90 }
// 7일 페이스: ClaudeBar paceColor — 여유(+) 초록, 초과(-) 주황, -15p 이하 빨강
const PACE_RED_AT = -15
// 캐시: cache-clock — 남은 수명이 20% 아래면 노랑
const TTL_SECONDS = { '5m': 5 * 60, '1h': 60 * 60 }
const CACHE_WARN_SHARE = 0.2

const DAY = 24 * 60 * 60
const WEEK = 7 * DAY

const RESET = '\x1b[0m'
const DIM = '\x1b[2m'
const fg = hex => {
  const n = parseInt(hex.slice(1), 16)
  return `\x1b[38;2;${(n >> 16) & 255};${(n >> 8) & 255};${n & 255}m`
}
const paint = (hex, text) => `${fg(hex)}${text}${RESET}`
const dim = text => `${DIM}${text}${RESET}`

// usage-band: 흰색(t > 0)이나 검정(t < 0) 쪽으로 |t|만큼 섞는다
const lighten = (hex, t) => {
  const n = parseInt(hex.slice(1), 16)
  const target = t >= 0 ? 255 : 0
  const ch = v => Math.round(v + (target - v) * Math.abs(t)).toString(16).padStart(2, '0')
  return `#${ch((n >> 16) & 255)}${ch((n >> 8) & 255)}${ch(n & 255)}`
}

// usage-band bar()에서 움직이는 하이라이트만 뺐다(상태줄은 30초마다 다시 그려서 애니메이션이 없다)
export function bar(pct, color, cells = BAR_CELLS) {
  const filled = Math.max(pct > 0 ? 1 : 0, Math.min(cells, Math.round((pct / 100) * cells)))
  let out = ''
  for (let i = 0; i < filled; i++) {
    const shade = filled === 1 ? 0 : -0.15 + (0.35 * i) / (filled - 1)
    out += paint(lighten(color, shade), '■')
  }
  if (cells > filled) out += paint(TRACK, '■'.repeat(cells - filled))
  return out
}

// usage-band fmtLeft (초 단위로 받는다)
export function fmtLeft(seconds) {
  const mins = Math.max(0, Math.round(seconds / 60))
  const d = Math.floor(mins / 1440)
  const h = Math.floor((mins % 1440) / 60)
  const m = mins % 60
  if (d > 0) return `${d}d${h}h`
  if (h > 0) return `${h}h${m}m`
  return `${m}m`
}

// ClaudeBar dailyBudgetRemainingDelta: 리셋 7일 전을 시작으로 하루마다 100/7씩 연다.
// 남은 % − 오늘 칸까지 남아 있어야 할 % = 여유(+) 또는 초과(−)
export function pace(usedPct, resetsAt, now) {
  const start = resetsAt - WEEK
  const elapsed = Math.min(WEEK, Math.max(0, now - start))
  const bucket = Math.min(7, Math.max(1, Math.floor(elapsed / DAY) + 1))
  const expectedRemaining = Math.max(0, 100 - bucket * (100 / 7))
  return 100 - usedPct - expectedRemaining
}

// ClaudeBar paceText
export function paceText(delta) {
  const r = Math.round(delta)
  return r === 0 ? '0p' : `${r > 0 ? '+' : ''}${r}p`
}

// ClaudeBar paceColor (0이면 회색 = 없음)
export function paceColor(delta) {
  const r = Math.round(delta)
  if (r > 0) return GREEN
  if (delta <= PACE_RED_AT) return RED
  if (r < 0) return ORANGE
  return null
}

const tone = pct => (pct >= LIMIT_AT.alert ? RED : pct >= LIMIT_AT.warn ? AMBER : HUE.five)

function fiveHour(l, now) {
  const pct = Math.round(l.used_percentage)
  const color = tone(pct)
  let s = `${paint(color, '5h')} ${bar(pct, color)} ${paint(color, `${pct}%`)}`
  if (typeof l.resets_at === 'number') s += dim(` · ${fmtLeft(l.resets_at - now)}`)
  return s
}

function sevenDay(l, now) {
  const pct = Math.round(l.used_percentage)
  const delta = typeof l.resets_at === 'number' ? pace(l.used_percentage, l.resets_at, now) : null
  const color = pct >= LIMIT_AT.alert ? RED : (delta === null ? null : paceColor(delta)) ?? '#8b8f97'
  let s = `${paint(color, '7d')} ${bar(pct, color)} ${paint(color, `${pct}%`)}`
  if (delta !== null) s += ` ${paint(color, paceText(delta))}`
  if (typeof l.resets_at === 'number') s += dim(` · ${fmtLeft(l.resets_at - now)}`)
  return s
}

// cache-clock warmLine/coldLine을 한 칸으로 줄였다
function cache(c, now) {
  if (!c || typeof c !== 'object' || c.caching_observed === false) return ''
  const left = typeof c.expires_at === 'number' ? c.expires_at - now : null
  if (c.warm !== false && left !== null && left > 0) {
    const ttl = TTL_SECONDS[c.ttl]
    const color = ttl && left < ttl * CACHE_WARN_SHARE ? AMBER : GREEN
    const time = left >= 60 ? `${Math.floor(left / 60)}m` : `${Math.max(1, Math.floor(left))}s`
    return `${paint(color, `cache ● ${time}`)}${c.ttl ? dim(` /${c.ttl}`) : ''}`
  }
  const recache = typeof c.recache_tokens_if_cold === 'number' && c.recache_tokens_if_cold > 0
    ? dim(` · 다음 메시지 ${c.recache_tokens_if_cold >= 1000 ? `${Math.round(c.recache_tokens_if_cold / 1000)}k` : c.recache_tokens_if_cold} 재캐시`)
    : ''
  return `${paint(RED, 'cache ○ 식음')}${recache}`
}

// input = 상태줄 JSON, now = epoch 초. 보여줄 게 없으면 ''
export function render(input, now) {
  const parts = []
  const rl = input?.rate_limits
  if (rl?.five_hour && typeof rl.five_hour.used_percentage === 'number') parts.push(fiveHour(rl.five_hour, now))
  if (rl?.seven_day && typeof rl.seven_day.used_percentage === 'number') parts.push(sevenDay(rl.seven_day, now))
  const c = cache(input?.prompt_cache, now)
  if (c) parts.push(c)
  return parts.join('  ')
}

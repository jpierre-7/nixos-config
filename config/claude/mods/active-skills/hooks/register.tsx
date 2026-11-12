import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { UsedSkill } from '../types'

const auto = atom({ plugin: 'active-skills', key: 'auto' } as const, [] as string[])
const used = atom({ plugin: 'active-skills', key: 'used' } as const, [] as UsedSkill[])
const turn = atom({ plugin: 'active-skills', key: 'turn' } as const, 0)
const seen = atom({ plugin: 'active-skills', key: 'seen' } as const, 0)
const isAutoSeen = atom({ plugin: 'active-skills', key: 'isAutoSeen' } as const, false)

// A skill a CLAUDE.md @-imports reaches the context as its SKILL.md file.
const SKILL_FILE = /\/skills\/([^/]+)\/SKILL\.md$/
const skillsIn = (paths: readonly string[]) =>
  [...new Set(paths.flatMap(p => SKILL_FILE.exec(p)?.[1] ?? []))]

// Band shows at most this many names, then "+N".
const BAND_MAX = 3
// /active lists this many unused skills unless asked for "all".
const UNUSED_MAX = 8

const clock = (ms: number) => {
  const d = new Date(ms)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

const clip = (names: string[], max: number) =>
  names.length > max ? `${names.slice(0, max).join(', ')} +${names.length - max}` : names.join(', ')

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'active',
      description: 'List active plugins and skills (add "all" for every unused skill)',
    })
    // prompt.context fires only when the context is (re)built. A reload in a
    // running session reads the memory files the context already holds.
    if ((await read($, auto)).length === 0) {
      try {
        const usage = await $.session.usage({ breakdown: 'summary' })
        const names = skillsIn((usage.context.breakdown?.memoryFiles ?? []).map(f => f.path))
        if (names.length > 0) await update($, auto, () => names)
      } catch {
        // Nothing to show is fine; the next compaction or /clear fills it.
      }
    }
    return next(e)
  })

  on('prompt.context', async ($, e, next) => {
    const names = skillsIn((e.instructionFiles ?? []).map(f => f.path))
    await update($, auto, () => names)
    return next(e)
  })

  on('prompt.submit', async ($, e, next) => {
    // Sending a prompt counts as having seen the band: it goes quiet until the
    // next change.
    const count = (await read($, used)).length
    await update($, seen, () => count)
    await update($, isAutoSeen, () => true)
    await update($, turn, n => n + 1)
    return next(e)
  })

  on('skill.prompt', async ($, e, next) => {
    const at = await $.clock.now()
    const t = await read($, turn)
    await update($, used, list => [...list, { name: e.skill, plugin: e.pluginName, turn: t, at }].slice(-200))
    return next(e)
  })

  on('command.run', { command: 'active' }, async ($, e) => {
    await update($, isAutoSeen, () => true)
    const count = (await read($, used)).length
    await update($, seen, () => count)

    const autoList = await read($, auto)
    const usedList = await read($, used)
    const enabled = Object.entries(
      ((await $.settings.read({ key: 'enabledPlugins' })) ?? {}) as Record<string, unknown>,
    )
      .filter(([, isOn]) => isOn === true)
      .map(([id]) => id)

    let available: string[] = []
    try {
      const usage = await $.session.usage({ breakdown: 'summary' })
      available = (usage.context.breakdown?.skills?.skillFrontmatter ?? []).map(s =>
        s.pluginName ? `${s.pluginName}:${s.name.replace(`${s.pluginName}:`, '')}` : s.name,
      )
    } catch {
      // Left empty: the unused section says so.
    }
    const usedNames = new Set([...autoList, ...usedList.map(u => u.name)])
    const unused = available.filter(n => !usedNames.has(n) && !usedNames.has(n.split(':').pop()!)).sort()
    const isAll = e.args.trim() === 'all'

    const lines = [
      `Always on (CLAUDE.md import): ${autoList.join(', ') || 'none'}`,
      `Used this session (${usedList.length}):`,
      ...(usedList.length === 0
        ? ['  none yet']
        : usedList.map(u => `  t${u.turn}  ${clock(u.at)}  ${u.plugin ? `${u.plugin}:` : ''}${u.name.replace(`${u.plugin}:`, '')}`)),
      `Plugins enabled (${enabled.length}): ${enabled.map(id => id.split('@')[0]).join(', ')}`,
      available.length === 0
        ? 'Available, unused: unknown (no skill listing yet)'
        : `Available, unused (${unused.length}): ${isAll ? unused.join(', ') : clip(unused, UNUSED_MAX)}${!isAll && unused.length > UNUSED_MAX ? '  (/active all)' : ''}`,
    ]
    return { text: lines.join('\n') }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const rest = await next(e)
    const autoList = await read($, auto)
    const usedList = await read($, used)
    const fresh = usedList.slice(await read($, seen))
    const showAuto = !(await read($, isAutoSeen)) && autoList.length > 0
    if (e.props.hasSurvey || e.props.isWorking || (!showAuto && fresh.length === 0)) return rest

    const { Box, Text } = $.ui.resolve(e)
    const freshNames = [...new Set(fresh.map(u => u.name))]
    const mine = (
      <Box flexDirection="row">
        <Text dimColor wrap="truncate-end">
          {showAuto ? `on: ${clip(autoList, BAND_MAX)}` : ''}
          {showAuto && freshNames.length > 0 ? '  ·  ' : ''}
          {freshNames.length > 0 ? `just used: ${clip(freshNames, BAND_MAX)} (t${fresh.at(-1)?.turn})` : ''}
          {'  ·  /active'}
        </Text>
      </Box>
    )
    return rest ? (
      <Box flexDirection="column">
        {mine}
        {rest}
      </Box>
    ) : (
      mine
    )
  })
}

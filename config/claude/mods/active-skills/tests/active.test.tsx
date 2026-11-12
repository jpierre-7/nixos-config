import { expect, test } from 'claude-code/testing'

const BAND = {
  plugin: 'active-skills',
  component: 'AbovePrompt',
  surface: 'terminal',
  props: {
    hasSurvey: false,
    isWorking: false,
    maxRows: 10,
    bodyColumns: 100,
    scroll: { offset: 0, bodyRows: 10 },
    view: {},
  },
} as const

test('band: auto skill, quiet after a prompt, back on a new skill; /active lists all', async ($, on) => {
  on('command.register', () => ({ value: { command: 'active' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.usage', () => ({
    value: {
      startedAt: 0,
      context: {
        breakdown: {
          memoryFiles: [
            { path: '/home/u/.claude/CLAUDE.md', type: 'User', tokens: 10 },
            { path: '/nix/store/x/.claude/skills/i-have-adhd/SKILL.md', type: 'User', tokens: 10 },
          ],
          skills: {
            totalSkills: 3,
            includedSkills: 3,
            skillFrontmatter: [
              { name: 'i-have-adhd', source: 'userSettings', tokens: 1 },
              { name: 'caveman', source: 'userSettings', tokens: 1 },
              { name: 'diff-notes', source: 'userSettings', tokens: 1 },
            ],
          },
        },
      },
    },
  }))
  on('settings.read', () => ({ value: { enabledPlugins: { 'ponytail@ponytail': true, 'x@y': false } } }))
  on('clock.now', () => ({ value: 0 }))
  on('prompt.submit', (_, e) => e)
  on('skill.prompt', (_, e) => ({ text: e.text }))
  // The engine's own band: an empty box.
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box />
  })

  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })

  let ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /on: i-have-adhd/ }))?.text).toContain('/active')
  await ui.unmount()

  await $.prompt.submit({ text: 'hi' })
  ui = await $.ui.mount(BAND)
  expect(await ui.find({ type: 'Text', text: /\/active/ })).toBeUndefined()
  await ui.unmount()

  await $.skill.prompt({ skill: 'caveman', text: 'grunt' })
  ui = await $.ui.mount(BAND)
  expect((await ui.find({ type: 'Text', text: /just used/ }))?.text).toContain('caveman (t1)')
  await ui.unmount()

  const out = await $.command.run({ command: 'active', args: '' })
  expect(out.text).toContain('Always on (CLAUDE.md import): i-have-adhd')
  expect(out.text).toMatch(/t1  \d\d:\d\d  caveman/)
  expect(out.text).toContain('Plugins enabled (1): ponytail')
  expect(out.text).toContain('Available, unused (1): diff-notes')
})

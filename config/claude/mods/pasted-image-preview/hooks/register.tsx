/**
 * pasted-image-preview: a thumbnail of each image pasted into the prompt box,
 * drawn in the band above it, so you see what you're about to send.
 *
 * Claude Code lets a mod read a pasted image's bytes only from a
 * `prompt.submit` hook, once it is already being sent. What a mod does see
 * first is the `[Image #N]` token: Ctrl+V reads the clipboard, then puts the
 * token in the box as a `prompt.change` with origin `engine`. So on a new token
 * this runs `claude-paste-preview` (config/claude/paste-preview.sh), which
 * thumbnails what the clipboard holds at that moment: the image Claude Code
 * just read from it.
 *
 * A token is previewed while it stays in the box: delete it and its thumbnail
 * goes, send the prompt and the band empties. The thumbnails live in this
 * module's memory, so a reload drops them (each shows its alt text instead).
 *
 * The `Image` element draws through the kitty graphics protocol, which herdr
 * passes on (`kitty_graphics` in config/herdr/config.toml) and Claude Code uses
 * only when asked (`CLAUDE_CODE_FORCE_TERMINAL_IMAGES`, set in herdr's panes by
 * modules/home/shell.nix). Elsewhere it shows the alt text, which says so:
 * plain WezTerm can't draw kitty's placeholders, and Claude Code uses iTerm2
 * images only for a terminal reporting itself as iTerm2 3.5+ (README).
 *
 * Options (pluginConfigs["pasted-image-preview@skills-dir"].options):
 *   rows: number   height of a thumbnail in terminal rows (default 8)
 */
import type { EngineInterface, Register } from 'claude-code'

type Preview = { width: number; height: number; png: string } | { missing: string }

const TOKEN = /\[Image #(\d+)\]/g
// Drawn in the thumbnail's place where the terminal can't draw it: outside
// herdr, the caption under it would otherwise show twice.
const NO_PICTURE = 'preview needs herdr'
// Terminal cells are about twice as tall as they are wide.
const CELL_ASPECT = 2

// image id -> its thumbnail, or why there is none
const previews = new Map<number, Preview>()
const pending = new Set<number>()
// the ids the prompt box holds now, in order
let shown: number[] = []

function idsIn(text: string): number[] {
  return [...new Set([...text.matchAll(TOKEN)].map(m => Number(m[1])))]
}

function show($: EngineInterface, ids: number[]) {
  if (ids.length === shown.length && ids.every((id, i) => id === shown[i])) return
  shown = ids
  $.ui.invalidate('ui.render')
}

async function capture($: EngineInterface, id: number) {
  pending.add(id)
  $.ui.invalidate('ui.render')
  let preview: Preview
  try {
    const run = await $.process.run(['claude-paste-preview'], { timeoutMs: 10_000 })
    const [size = '', png = ''] = run.stdout.split('\n')
    const m = /^(\d+)x(\d+)$/.exec(size)
    preview =
      run.exitCode === 0 && m && png
        ? { width: Number(m[1]), height: Number(m[2]), png }
        : { missing: 'no image on the clipboard to preview' }
  } catch {
    preview = { missing: 'claude-paste-preview is not on PATH' }
  }
  pending.delete(id)
  previews.set(id, preview)
  $.ui.invalidate('ui.render')
}

// Columns for a thumbnail `rows` tall that keeps the picture's shape.
const columnsFor = (p: { width: number; height: number }, rows: number) =>
  Math.max(4, Math.min(255, Math.round((rows * CELL_ASPECT * p.width) / p.height)))

export const register: Register = (on, options) => {
  const wantRows = typeof options.rows === 'number' && options.rows >= 2 ? Math.floor(options.rows) : 8

  on('prompt.edit', async ($, e, next) => {
    const box = await next(e)
    show($, idsIn(box.text))
    return box
  })

  on('prompt.change', async ($, e, next) => {
    const ids = idsIn(e.text)
    // `engine` is a paste landing. History and undo bring back an old token,
    // whose image the clipboard no longer says anything about.
    if (e.origin.kind === 'engine') {
      for (const id of ids) {
        if (!shown.includes(id) && !pending.has(id)) void capture($, id)
      }
    }
    show($, ids)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const rest = await next(e)
    const items = shown.filter(id => previews.has(id) || pending.has(id))
    if (e.props.hasSurvey || items.length === 0) return rest

    const elements = $.ui.resolve(e)
    const { Box, Text } = elements
    // Only the terminal has an Image element; elsewhere the captions alone.
    const Image = 'Image' in elements ? elements.Image : undefined
    const width = e.props.bodyColumns
    // One row for the captions, one for the band's other rows.
    let rows = Math.max(2, Math.min(wantRows, e.props.maxRows - 2))
    const pictures = items.map(id => previews.get(id)).filter(p => p && 'png' in p) as { width: number; height: number }[]
    // Shrink the row until every thumbnail fits side by side, down to 2.
    const total = (r: number) => pictures.reduce((sum, p) => sum + columnsFor(p, r) + 2, 0)
    while (rows > 2 && total(rows) > width) rows -= 1

    const tiles = items.map(id => {
      const p = previews.get(id)
      const label = `Image #${id}`
      if (!p) {
        return (
          <Box flexDirection="column">
            <Text dimColor>{label}: reading the clipboard…</Text>
          </Box>
        )
      }
      if ('missing' in p) {
        return (
          <Box flexDirection="column">
            <Text dimColor>
              {label}: {p.missing}
            </Text>
          </Box>
        )
      }
      const caption = `${label} · ${p.width}×${p.height}`
      if (!Image) return <Text dimColor>{caption}</Text>
      return (
        <Box flexDirection="column">
          <Image source={{ png: p.png }} columns={columnsFor(p, rows)} rows={rows} alt={NO_PICTURE} />
          <Text dimColor wrap="truncate-end">
            {caption}
          </Text>
        </Box>
      )
    })

    const mine = (
      <Box flexDirection="row" flexWrap="wrap" columnGap={2}>
        {tiles}
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

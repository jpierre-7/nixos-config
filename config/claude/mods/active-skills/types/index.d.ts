export type UsedSkill = { name: string; plugin?: string; turn: number; at: number }

declare module 'claude-code' {
  interface PluginState {
    'active-skills': {
      // Skills a CLAUDE.md pulls in with an @ import: on from the first turn.
      auto: string[]
      used: UsedSkill[]
      turn: number
      // How many of `used` (and whether `auto`) the person has already seen.
      seen: number
      isAutoSeen: boolean
    }
  }
}

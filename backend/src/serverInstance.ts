import type { ServerType } from '@hono/node-server'

let _server: ServerType | null = null

export function setServer(s: ServerType) {
  _server = s
}

export function getServer(): ServerType | null {
  return _server
}

import { DurableObject } from "cloudflare:workers";

export class AccountRealtimeHub extends DurableObject<Env> {
  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket") {
      return new Response("WebSocket upgrade required", { status: 426 });
    }
    const deviceID = request.headers.get("x-mino-device-id");
    if (!deviceID) return new Response("Missing authenticated device", { status: 401 });
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair) as [WebSocket, WebSocket];
    this.ctx.acceptWebSocket(server, [deviceID]);
    server.serializeAttachment({ deviceID });
    server.send(JSON.stringify({ type: "ready" }));
    return new Response(null, { status: 101, webSocket: client });
  }

  notify(): void {
    const payload = JSON.stringify({ type: "events_available" });
    for (const socket of this.ctx.getWebSockets()) {
      try {
        socket.send(payload);
      } catch {
        try { socket.close(1011, "notification_failed"); } catch { /* already closed */ }
      }
    }
  }

  webSocketMessage(socket: WebSocket, _message: string | ArrayBuffer): void {
    socket.close(1008, "business_messages_not_supported");
  }

  webSocketClose(_socket: WebSocket, _code: number, _reason: string, _wasClean: boolean): void {
    // Hibernation API removes disconnected sockets from getWebSockets().
  }

  webSocketError(socket: WebSocket): void {
    try { socket.close(1011, "websocket_error"); } catch { /* already closed */ }
  }
}

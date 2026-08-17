import type { WebSocket } from "ws";
import type { FriendshipEvent } from "../domain.js";

interface SocketSubscription {
  socket: WebSocket;
  paused: boolean;
  pendingPayloads: Array<{ eventID: string; payload: string }>;
}

export interface EventSubscription {
  remove(): void;
  activate(excludingEventIDs?: ReadonlySet<string>): void;
}

export class EventHub {
  private readonly sockets = new Map<string, Set<SocketSubscription>>();

  add(friendshipID: string, socket: WebSocket, paused = false): EventSubscription {
    const group = this.sockets.get(friendshipID) ?? new Set<SocketSubscription>();
    const subscription: SocketSubscription = { socket, paused, pendingPayloads: [] };
    group.add(subscription);
    this.sockets.set(friendshipID, group);
    return {
      remove: () => {
        group.delete(subscription);
        if (group.size === 0) this.sockets.delete(friendshipID);
      },
      activate: (excludingEventIDs = new Set<string>()) => {
        if (!subscription.paused) return;
        if (socket.readyState === socket.OPEN) {
          for (const pending of subscription.pendingPayloads) {
            if (!excludingEventIDs.has(pending.eventID)) socket.send(pending.payload);
          }
        }
        subscription.pendingPayloads = [];
        subscription.paused = false;
      }
    };
  }

  publish(events: FriendshipEvent[]): void {
    for (const event of events) {
      const payload = JSON.stringify({ type: "friendship_event", data: event });
      for (const subscription of this.sockets.get(event.friendshipID) ?? []) {
        if (subscription.paused) {
          subscription.pendingPayloads.push({ eventID: event.id, payload });
        } else if (subscription.socket.readyState === subscription.socket.OPEN) {
          subscription.socket.send(payload);
        }
      }
    }
  }
}

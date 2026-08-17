import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import type { WebSocket } from "ws";
import type { FriendshipEvent } from "../src/domain.js";
import { EventHub } from "../src/events/hub.js";

function event(friendshipID: string, sequence: number): FriendshipEvent {
  return {
    id: randomUUID(),
    sequence,
    friendshipID,
    type: "test_event",
    actorType: "system",
    actorID: null,
    payload: {},
    timelineVisible: false,
    occurredAt: new Date().toISOString()
  };
}

describe("EventHub paused subscriptions", () => {
  it("buffers the catch-up race, flushes in order, and then becomes realtime", () => {
    const sent: string[] = [];
    const socket = {
      OPEN: 1,
      readyState: 1,
      send(payload: string) { sent.push(payload); }
    } as unknown as WebSocket;
    const hub = new EventHub();
    const subscription = hub.add("friendship-a", socket, true);
    const first = event("friendship-a", 1);
    const second = event("friendship-a", 2);
    const third = event("friendship-a", 3);

    hub.publish([first, second]);
    expect(sent).toEqual([]);
    // `first` was already returned by the PostgreSQL backlog query. It must
    // not be flushed a second time from the in-process race buffer.
    subscription.activate(new Set([first.id]));
    hub.publish([third]);

    expect(sent.map((payload) => JSON.parse(payload).data.id)).toEqual([
      second.id,
      third.id
    ]);

    subscription.remove();
    hub.publish([event("friendship-a", 4)]);
    expect(sent).toHaveLength(2);
  });
});

/**
 * Analytics 的唯一出口。
 *
 * 组件不允许直接调用任何 SDK——需要埋点就在这里加事件名，底层实现之后可以整体替换成
 * Cloudflare Web Analytics / PostHog / Plausible / Umami，调用方不用改。
 */

/** 只定义页面上真实存在的动作。没有对应交互的事件不预先占位。 */
export type MinoEvent =
  | 'page_view'
  | 'cta_click'
  | 'install_command_copy'
  | 'github_click'
  | 'docs_click'
  | 'demo_play'
  | 'character_view';

type Properties = Record<string, string | number | boolean | undefined>;

declare global {
  interface Window {
    /** Cloudflare Web Analytics / 其他 SDK 接入后挂在这里。 */
    __minoTrack?: (event: string, properties?: Properties) => void;
  }
}

export function track(event: MinoEvent, properties: Properties = {}): void {
  if (typeof window === 'undefined') return;

  const sink = window.__minoTrack;
  if (sink) {
    sink(event, properties);
    return;
  }

  // 还没接入 SDK 时不静默丢弃，开发环境打出来便于核对埋点是否触发。
  if (import.meta.env.DEV) {
    console.debug('[analytics]', event, properties);
  }
}

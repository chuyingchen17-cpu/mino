/**
 * 安装命令的复制交互。
 *
 * 这是页面上唯一需要客户端状态的 CTA：写剪贴板 + 复制成功反馈 + 埋点。
 * 成功与失败都用「图标 + 文字」表达，不只靠颜色。
 */

import { useEffect, useRef, useState } from 'react';
import { Check, Copy, X } from 'lucide-react';
import { track } from '~/lib/analytics';

interface Props {
  command: string;
  variant: 'nightly' | 'tag' | 'source';
  label?: string;
}

type CopyState = 'idle' | 'copied' | 'failed';

export default function InstallCommand({ command, variant, label }: Props) {
  const [state, setState] = useState<CopyState>('idle');
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    };
  }, []);

  const resetSoon = () => {
    if (timerRef.current !== null) window.clearTimeout(timerRef.current);
    timerRef.current = window.setTimeout(() => setState('idle'), 2400);
  };

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(command);
      setState('copied');
      track('install_command_copy', { variant });
    } catch {
      // 非 HTTPS 或用户拒绝授权时会走到这里，需要让用户知道可以手动选中。
      setState('failed');
    }
    resetSoon();
  };

  const icons = {
    idle: <Copy size={15} aria-hidden="true" />,
    copied: <Check size={15} aria-hidden="true" />,
    failed: <X size={15} aria-hidden="true" />,
  };

  const texts = {
    idle: '复制',
    copied: '已复制',
    failed: '复制失败',
  };

  return (
    <div className="min-w-0 rounded-card border border-line bg-surface-raised shadow-card">
      {label && (
        <p className="border-b border-line px-4 py-2 text-xs font-semibold text-faint">{label}</p>
      )}
      <div className="flex items-center gap-3 p-3 sm:p-4">
        <code className="min-w-0 flex-1 overflow-x-auto font-mono text-[13px] leading-relaxed whitespace-pre text-ink">
          {command}
        </code>
        <button
          type="button"
          onClick={copy}
          aria-label={`复制命令：${command}`}
          className="inline-flex h-9 shrink-0 items-center gap-1.5 rounded-control border border-line bg-surface px-3 text-xs font-semibold text-ink transition-colors duration-200 hover:bg-coral-soft hover:text-coral focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus"
        >
          {icons[state]}
          {texts[state]}
        </button>
      </div>
      {/* 复制结果同时播报给读屏软件。 */}
      <p role="status" aria-live="polite" className="sr-only">
        {state === 'copied' ? '命令已复制到剪贴板' : state === 'failed' ? '复制失败，请手动选中命令' : ''}
      </p>
    </div>
  );
}

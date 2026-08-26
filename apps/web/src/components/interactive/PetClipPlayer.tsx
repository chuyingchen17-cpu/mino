/**
 * 角色帧播放器。
 *
 * 播放规则跟随 app 的 manifest，不在网页上另定一套：
 * - 按 clip 声明的 framesPerSecond 播放，不把少量关键帧拉伸成慢放；
 * - loops 为 false 的动作播完停在末帧，不自动循环；
 * - 画布固定，只替换当前可见帧，脚底线不随帧漂移；
 * - Reduce Motion 下只显示该 clip 自己的静态帧，不推进帧序列。
 */

import { useEffect, useRef, useState } from 'react';
import { track } from '~/lib/analytics';
import { clipMeta, frameUrls, type CharacterId, type ClipId } from '~/lib/petFrames';

interface Props {
  character: CharacterId;
  clip: ClipId;
  /** 渲染边长，显式声明以避免 CLS。 */
  size?: number;
  /** auto 在挂载后播放；hover / click 由用户触发。 */
  trigger?: 'auto' | 'hover' | 'click';
  /** 首屏的帧需要立刻解码，其余交给浏览器懒加载。 */
  eager?: boolean;
  label?: string;
  className?: string;
}

function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false);

  useEffect(() => {
    const query = window.matchMedia('(prefers-reduced-motion: reduce)');
    setReduced(query.matches);

    const onChange = (event: MediaQueryListEvent) => setReduced(event.matches);
    query.addEventListener('change', onChange);
    return () => query.removeEventListener('change', onChange);
  }, []);

  return reduced;
}

export default function PetClipPlayer({
  character,
  clip,
  size = 160,
  trigger = 'auto',
  eager = false,
  label,
  className = '',
}: Props) {
  const meta = clipMeta(character, clip);
  const frames = frameUrls(character, clip);
  const reducedMotion = usePrefersReducedMotion();

  const [frame, setFrame] = useState(0);
  const [playing, setPlaying] = useState(trigger === 'auto');
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    if (reducedMotion || !playing) return;

    const frameDuration = 1000 / meta.framesPerSecond;
    let last = performance.now();
    let current = frame;

    const step = (now: number) => {
      if (now - last >= frameDuration) {
        last = now;
        current += 1;

        if (current >= meta.frameCount) {
          if (meta.loops) {
            current = 0;
          } else {
            // 非循环动作停在末帧，由下一次触发重新开始。
            setFrame(meta.frameCount - 1);
            setPlaying(false);
            return;
          }
        }
        setFrame(current);
      }
      rafRef.current = requestAnimationFrame(step);
    };

    rafRef.current = requestAnimationFrame(step);

    return () => {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
    };
    // frame 不作为依赖：它由 rAF 内部推进，加进来会每帧重启循环。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [playing, reducedMotion, meta.framesPerSecond, meta.frameCount, meta.loops]);

  const replay = () => {
    if (reducedMotion) return;
    setFrame(0);
    setPlaying(true);
    track('demo_play', { character, clip });
  };

  const visibleFrame = reducedMotion ? meta.reduceMotionFrameIndex : frame;
  const interactive = trigger !== 'auto';

  const content = (
    <span
      className="relative block"
      style={{ width: size, height: size }}
      onMouseEnter={trigger === 'hover' && !playing ? replay : undefined}
    >
      {frames.map((url, index) => (
        <img
          key={url}
          src={url}
          alt={index === 0 ? (label ?? '') : ''}
          aria-hidden={index === 0 ? undefined : true}
          data-pet-frame
          width={size}
          height={size}
          loading={eager && index === 0 ? 'eager' : 'lazy'}
          fetchPriority={eager && index === 0 ? 'high' : 'auto'}
          draggable={false}
          className="absolute inset-0 h-full w-full select-none"
          style={{ opacity: index === visibleFrame ? 1 : 0 }}
        />
      ))}
    </span>
  );

  if (!interactive) return <span className={className}>{content}</span>;

  return (
    <button
      type="button"
      onClick={replay}
      aria-label={label ? `播放${label}动作` : '播放动作'}
      className={`cursor-pointer rounded-card focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-focus ${className}`}
    >
      {content}
    </button>
  );
}

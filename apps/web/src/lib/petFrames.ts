/**
 * 角色帧的 Web 侧读取层。
 *
 * 帧元数据由 scripts/sync-pet-frames.mjs 从 app 的 manifest.json 生成，
 * 这里只负责拼路径和暴露类型，不重新定义帧率、帧数或画布。
 */

import { PET_CLIPS, PET_FRAME_CANVAS } from './petFramesGenerated';

export type CharacterId = keyof typeof PET_CLIPS;
export type ClipId = keyof (typeof PET_CLIPS)[CharacterId];

export interface ClipMeta {
  frameCount: number;
  framesPerSecond: number;
  loops: boolean;
  reduceMotionFrameIndex: number;
}

export const canvas = PET_FRAME_CANVAS;

export function clipMeta(character: CharacterId, clip: ClipId): ClipMeta {
  return PET_CLIPS[character][clip];
}

/** 帧文件名固定为 frame-NNN.png，从 000 开始连续。 */
export function frameUrl(character: CharacterId, clip: ClipId, index: number): string {
  return `/pet-frames/${character}/${clip}/frame-${String(index).padStart(3, '0')}.png`;
}

export function frameUrls(character: CharacterId, clip: ClipId): string[] {
  const { frameCount } = clipMeta(character, clip);
  return Array.from({ length: frameCount }, (_, index) => frameUrl(character, clip, index));
}

/** Reduce Motion 下每个 clip 用 manifest 指定的静态帧，不统一借用 idle。 */
export function reduceMotionFrameUrl(character: CharacterId, clip: ClipId): string {
  return frameUrl(character, clip, clipMeta(character, clip).reduceMotionFrameIndex);
}

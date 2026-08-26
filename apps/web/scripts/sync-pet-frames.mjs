/**
 * 把 macOS 客户端的真实角色帧同步到 public/pet-frames/。
 *
 * 帧资产的唯一来源是 apps/macos/Sources/MinoPresentation/Resources/PetFrames，
 * 产品页只是它的第二个消费者——不重画角色、不生成替身、不改画布。
 * 仓库里一共 236 帧 17 个 clip，这里只复制产品页真正用到的 clip，避免把无关资产打进站点。
 */

import { cp, mkdir, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const webRoot = dirname(fileURLToPath(new URL('../package.json', import.meta.url)));
const framesSource = join(
  webRoot,
  '../macos/Sources/MinoPresentation/Resources/PetFrames',
);
const framesTarget = join(webRoot, 'public/pet-frames');

const CHARACTERS = ['maltese-white', 'retriever-yellow'];
/** 产品页用到的 clip。新增 Section 需要别的动作时在这里加。 */
const CLIPS = ['idle', 'walk', 'pet_receive', 'eat', 'play', 'wave', 'welcome'];

if (!existsSync(framesSource)) {
  console.error(`找不到帧资产目录：${framesSource}`);
  console.error('产品页必须与 macOS 客户端在同一个仓库内构建。');
  process.exit(1);
}

const manifest = JSON.parse(await readFile(join(framesSource, 'manifest.json'), 'utf8'));

await rm(framesTarget, { recursive: true, force: true });
await mkdir(framesTarget, { recursive: true });

/** 记录每个 clip 的真实帧数，播放器据此决定序列长度，不靠猜。 */
const index = { canvas: manifest.canvas, groundAnchor: manifest.groundAnchor, clips: {} };
let copied = 0;

for (const character of CHARACTERS) {
  index.clips[character] = {};

  for (const clip of CLIPS) {
    const clipSource = join(framesSource, character, clip);
    if (!existsSync(clipSource)) {
      console.error(`缺少 clip：${character}/${clip}`);
      process.exit(1);
    }

    const frames = (await readdir(clipSource))
      .filter((name) => name.endsWith('.png'))
      .sort();

    // 帧号必须从 frame-000 开始连续，缺号要在构建阶段就暴露出来。
    frames.forEach((name, position) => {
      const expected = `frame-${String(position).padStart(3, '0')}.png`;
      if (name !== expected) {
        console.error(`${character}/${clip} 帧号不连续：期望 ${expected}，实际 ${name}`);
        process.exit(1);
      }
    });

    const declared = manifest.clips.find((entry) => entry.id === clip);
    if (!declared) {
      console.error(`manifest.json 未声明 clip：${clip}`);
      process.exit(1);
    }
    if (frames.length < declared.minimumFrames) {
      console.error(`${character}/${clip} 帧数不足：${frames.length} < ${declared.minimumFrames}`);
      process.exit(1);
    }

    await cp(clipSource, join(framesTarget, character, clip), { recursive: true });
    copied += frames.length;

    index.clips[character][clip] = {
      frameCount: frames.length,
      framesPerSecond: declared.framesPerSecond,
      loops: declared.loops,
      reduceMotionFrameIndex: declared.reduceMotionFrameIndex,
    };
  }
}

// 同时生成 TS 元数据，让播放器在构建期就拿到真实帧数与帧率，
// 而不是运行时再请求一份 JSON。app 的 manifest 是唯一事实来源，这里不手写数值。
const generated = `// 由 scripts/sync-pet-frames.mjs 生成，请勿手改。
// 事实来源：apps/macos/Sources/MinoPresentation/Resources/PetFrames/manifest.json

export const PET_FRAME_CANVAS = ${JSON.stringify(index.canvas)} as const;
export const PET_GROUND_ANCHOR = ${JSON.stringify(index.groundAnchor)} as const;
export const PET_CLIPS = ${JSON.stringify(index.clips, null, 2)} as const;
`;

await writeFile(join(webRoot, 'src/lib/petFramesGenerated.ts'), generated);

console.log(
  `已同步 ${copied} 帧（${CHARACTERS.length} 角色 × ${CLIPS.length} clip）到 public/pet-frames/`,
);

/**
 * 把仓库根的 Scripts/install.sh 同步到 public/install.sh，让站点在 /install.sh 提供它。
 *
 * 这样安装命令可以写成 `curl -fsSL https://mino.pet/install.sh | zsh`，
 * 比 raw.githubusercontent 的长链接短得多，也不把 GitHub 的路径结构写进对外文案。
 *
 * 唯一事实来源是 Scripts/install.sh，这里只是它的副本，和 sync-pet-frames.mjs
 * 对 PetFrames 的关系一样。副本被 .gitignore 排除，只在构建时生成：
 * 仓库里存两份 zsh 脚本迟早会分叉，而分叉过的安装脚本是会静默装错版本的。
 *
 * 顺带校验脚本首行是 shebang。public/ 下的文件按原样对外提供，
 * 一个被截断或写错的脚本被 curl 管进 zsh 会当场执行，构建期拦住比线上再发现便宜。
 */

import { copyFile, mkdir, readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const webRoot = dirname(fileURLToPath(new URL('../package.json', import.meta.url)));
const source = join(webRoot, '../../Scripts/install.sh');
const target = join(webRoot, 'public/install.sh');

if (!existsSync(source)) {
  console.error(`找不到安装脚本：${source}`);
  console.error('产品页必须与 Scripts/install.sh 在同一个仓库内构建。');
  process.exit(1);
}

const script = await readFile(source, 'utf8');

if (!script.startsWith('#!')) {
  console.error(`${source} 首行不是 shebang，拒绝作为可执行脚本对外提供。`);
  process.exit(1);
}

await mkdir(dirname(target), { recursive: true });
await copyFile(source, target);

console.log(`已同步 Scripts/install.sh 到 public/install.sh（${script.split('\n').length} 行）`);

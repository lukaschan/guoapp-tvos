#!/usr/bin/env python3
"""把 fork 对上游核心的改动覆盖到 submodule 工作区。

构建前必跑（scripts/build_tvos.py 的 build_core 会自动调它）。
幂等，可反复跑：

1. 先把上次补丁改过的文件还原到 submodule 指针版本；
2. 删掉上次拷入的 fork 新增文件；
3. 重新拷入 fork/core/*.go；
4. 按文件名顺序打上 fork/patches/*.patch。

只动 fork 清单里的文件，不碰 submodule 其他内容。补丁打不上时直接报错
退出，绝不带着半合入的核心继续构建——这时需要人工把该补丁重排到新版
上游上（改 fork/patches 里对应的 .patch 文件），再重跑。

注意：跑完后 `git status` 会显示 upstream/ 有修改，这是正常的构建态，
不要在 upstream/ 里提交；下次构建会先还原再重打。
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
upstream = root / 'upstream'
core = upstream / 'native' / 'core'
fork_dir = root / 'fork'


def run(args, **kwargs):
    subprocess.run(args, check=True, **kwargs)


def main():
    if not core.is_dir():
        raise SystemExit(
            '找不到 upstream/native/core，请先初始化 submodule：'
            'git submodule update --init --recursive')
    patches = sorted((fork_dir / 'patches').glob('*.patch'))
    if not patches:
        raise SystemExit('fork/patches 里没有补丁文件')
    # 1. 还原被补丁改过的文件（补丁文件名即目标文件名）。文件若已在上游
    # 被删掉则跳过还原，后面打补丁时会以补丁自己的报错停住。
    patched = [p.name[:-len('.patch')] for p in patches]
    existing = []
    for name in patched:
        probe = subprocess.run(
            ['git', '-C', str(upstream), 'cat-file', '-e',
             f'HEAD:native/core/{name}'],
            capture_output=True)
        if probe.returncode == 0:
            existing.append(f'native/core/{name}')
    if existing:
        run(['git', '-C', str(upstream), 'checkout', '--'] + existing)
    # 2. 删掉上次拷入的 fork 新增文件。
    for source in (fork_dir / 'core').glob('*.go'):
        target = core / source.name
        if target.exists():
            target.unlink()
    # 3. 拷入 fork 新增文件。
    for source in sorted((fork_dir / 'core').glob('*.go')):
        shutil.copy2(source, core / source.name)
    # 4. 打补丁（先逐个 --check，报错时指出是哪个文件）。
    # 补丁文件在 Windows 检出时可能被转成 CRLF，而目标 .go 文件固定是 LF，
    # 行尾不一致时 git apply 会直接失败；这里先统一转成 LF 再打。
    with tempfile.TemporaryDirectory() as tmp:
        normalized = []
        for patch in patches:
            data = patch.read_bytes()
            if b'\r\n' in data:
                target = Path(tmp) / patch.name
                target.write_bytes(data.replace(b'\r\n', b'\n'))
                normalized.append(target)
            else:
                normalized.append(patch)
        for patch, source in zip(normalized, patches):
            check = subprocess.run(
                ['git', '-C', str(upstream), 'apply', '--check', str(patch)],
                capture_output=True, text=True)
            if check.returncode != 0:
                print(check.stderr, file=sys.stderr)
                raise SystemExit(
                    f'补丁打不上：{source.name}，上游改了同处代码，'
                    '请人工重排该补丁后再构建（不要强行跳过）。')
            run(['git', '-C', str(upstream), 'apply', str(patch)])
    print(f'fork 覆盖层已合入：{len(patched)} 个补丁，'
          f'{len(list((fork_dir / "core").glob("*.go")))} 个新增文件。')


if __name__ == '__main__':
    main()

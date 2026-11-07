"""签名构建红果鉴 / 真果鉴并安装到 Apple TV 真机（Xcode 自动签名 + devicectl）。

免费开发者账号的描述文件 7 天过期：过期后重跑本脚本即可续签并重装。

本机签名参数不进仓库，优先级：命令行参数 > 环境变量 > 仓库根目录的
tvos-deploy.local.json（已 gitignore，可用 --save 写入）：

  team       GUOAPP_TEAM_ID     Xcode › Settings › Accounts 里已登录账号的 Team ID
  bundle_id  GUOAPP_BUNDLE_ID   自己账号下唯一的包名（工程默认的 com.duanju.guoapp.tv
                                已被其他开发者注册，无法用于你的账号）
  device     GUOAPP_TV_DEVICE   Apple TV 名称（`xcrun devicectl list devices` 中的 Name）

真果鉴（--all-sources）的包名自动加 `.all` 后缀，两个版本可同时装在一台电视上。
Apple TV 需先与本机配对：电视上打开 设置 › 遥控器与设备 › 遥控器 App 与设备。
"""

import argparse
import json
import os
import shutil
import subprocess
import tempfile
from dataclasses import asdict, dataclass
from pathlib import Path

from app_build import BuildVariant, add_variant_argument
from build_tvos import (app_name, build_core, project, read_version, require_core, resolve_packages, root, run,
                        verify_display_name, xcode_settings)

local_config = root / 'tvos-deploy.local.json'
derived = root / 'tvos' / 'GuoAppTV' / 'build' / 'device'
configuration = 'Release'


@dataclass(frozen=True)
class DeploySettings:
    team: str
    bundle_id: str
    device: str


def read_saved_settings() -> dict:
    if not local_config.is_file():
        return {}
    try:
        saved = json.loads(local_config.read_text())
    except json.JSONDecodeError as error:
        raise SystemExit(f'{local_config.name} 不是有效的 JSON：{error}')
    if not isinstance(saved, dict):
        raise SystemExit(f'{local_config.name} 应为 JSON 对象，例如 {{"team": "...", "bundle_id": "...", "device": "..."}}')
    return saved


def load_settings(options: argparse.Namespace) -> DeploySettings:
    saved = read_saved_settings()
    sources = {
        'team': (options.team, 'GUOAPP_TEAM_ID'),
        'bundle_id': (options.bundle_id, 'GUOAPP_BUNDLE_ID'),
        'device': (options.device, 'GUOAPP_TV_DEVICE'),
    }
    values = {key: flag or os.environ.get(env) or saved.get(key, '') for key, (flag, env) in sources.items()}
    missing = [f'--{key.replace("_", "-")}（或环境变量 {sources[key][1]}）' for key, value in values.items() if not value]
    if missing:
        raise SystemExit('缺少部署参数：' + '、'.join(missing) + f'；也可写进 {local_config.name}。')
    return DeploySettings(**values)


def find_device(name: str) -> str:
    """按名称找已配对的 Apple TV 真机，返回 CoreDevice 标识符（模拟器同名也不会误选）。"""
    with tempfile.TemporaryDirectory() as directory:
        listing = Path(directory) / 'devices.json'
        try:
            subprocess.run(['xcrun', 'devicectl', 'list', 'devices', '--json-output', str(listing)],
                           check=True, capture_output=True, text=True)
            devices = json.loads(listing.read_text())['result']['devices']
        except FileNotFoundError:
            raise SystemExit('找不到 xcrun / devicectl：需要安装完整 Xcode。')
        except subprocess.CalledProcessError as error:
            raise SystemExit('devicectl 列设备失败：' + (error.stderr or error.stdout or str(error)).strip())
        except (json.JSONDecodeError, KeyError) as error:
            raise SystemExit(f'无法解析 devicectl 的设备列表：{error!r}')
    for device in devices:
        hardware = device.get('hardwareProperties', {})
        if (device.get('deviceProperties', {}).get('name') == name
                and hardware.get('platform') == 'tvOS' and hardware.get('reality') == 'physical'):
            if device.get('connectionProperties', {}).get('pairingState') != 'paired':
                break
            return device['identifier']
    raise SystemExit(f'找不到已配对的 Apple TV「{name}」。请在电视上打开 设置 › 遥控器与设备 › '
                     '遥控器 App 与设备，再用 Xcode › Window › Devices and Simulators 配对。')


def build_signed_app(settings: DeploySettings, bundle_id: str, variant: BuildVariant, device_id: str) -> Path:
    application = derived / 'Build' / 'Products' / f'{configuration}-appletvos' / f'{app_name}.app'
    # 先删旧包：构建失败时绝不会把上一次的旧包装到电视上。
    shutil.rmtree(application, ignore_errors=True)
    resolve_packages(derived)
    log = derived / 'deploy-build.log'
    log.parent.mkdir(parents=True, exist_ok=True)
    arguments = [
        'xcodebuild', '-project', str(project), '-scheme', app_name,
        '-configuration', configuration, '-destination', f'platform=tvOS,id={device_id}',
        '-derivedDataPath', str(derived), '-onlyUsePackageVersionsFromResolvedFile',
        # 让 xcodebuild 无界面地注册包名、生成 / 续签开发描述文件。
        '-allowProvisioningUpdates',
        'CODE_SIGN_STYLE=Automatic', f'DEVELOPMENT_TEAM={settings.team}',
        f'PRODUCT_BUNDLE_IDENTIFIER={bundle_id}', *xcode_settings(variant, read_version()), 'build',
    ]
    with open(log, 'w') as output:
        result = subprocess.run(arguments, cwd=root, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode != 0:
        lines = log.read_text().splitlines()
        # 只列出 error 行（去重）；没有 error 行时（例如被中断）给出日志末尾。
        details = list(dict.fromkeys(line for line in lines if 'error:' in line))[:10] or lines[-30:]
        raise SystemExit('签名构建失败（完整日志：' + str(log) + '）：\n' + '\n'.join(details))
    if not application.is_dir():
        raise SystemExit('构建成功但找不到 ' + str(application))
    verify_display_name(application, variant)
    return application


def main() -> None:
    parser = argparse.ArgumentParser(description='签名构建并安装到 Apple TV 真机')
    parser.add_argument('--team', help='开发团队 Team ID')
    parser.add_argument('--bundle-id', help='自己账号下唯一的包名')
    parser.add_argument('--device', help='Apple TV 名称')
    parser.add_argument('--skip-core', action='store_true', help='复用已编好的同版本 Go 核心 xcframework')
    parser.add_argument('--no-launch', action='store_true', help='只安装，不启动')
    parser.add_argument('--save', action='store_true', help=f'把本次参数写入 {local_config.name}')
    add_variant_argument(parser)
    options = parser.parse_args()
    settings = load_settings(options)
    if options.save:
        local_config.write_text(json.dumps(asdict(settings), ensure_ascii=False, indent=2) + '\n')
        print('已保存部署参数到 ' + str(local_config))
    variant = BuildVariant(options.all_sources)
    bundle_id = settings.bundle_id + ('.all' if variant.all_sources else '')

    print(f'==> 查找 Apple TV「{settings.device}」')
    device_id = find_device(settings.device)
    print('    ' + device_id)
    if options.skip_core:
        require_core(variant)
    else:
        print('==> 编译 Go 核心')
        build_core(variant=variant)
    print(f'==> 签名构建 {variant.display_name}（{bundle_id}）')
    application = build_signed_app(settings, bundle_id, variant, device_id)
    print(f'==> 安装到 {settings.device}')
    run(['xcrun', 'devicectl', 'device', 'install', 'app', '--device', device_id, str(application)])
    if not options.no_launch:
        print('==> 启动')
        run(['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', device_id,
             '--terminate-existing', bundle_id])
    print('完成。免费账号的描述文件 7 天后过期，届时重跑本脚本即可。')


if __name__ == '__main__':
    main()

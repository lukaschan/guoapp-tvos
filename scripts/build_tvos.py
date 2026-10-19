import argparse
import os
import platform
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

from app_build import BuildVariant, add_variant_argument

root = Path(__file__).resolve().parents[1]
project = root / 'tvos' / 'GuoAppTV' / 'GuoAppTV.xcodeproj'
app_name = 'GuoAppTV'
# Go 核心在上游仓库的 native/ 目录；上游整仓以 git submodule 形式
# 放在 upstream/（见 .gitmodules），核心路径即 upstream/native。
core = root / 'upstream' / 'native'


def run(arguments, **kwargs):
    subprocess.run(arguments, cwd=kwargs.pop('cwd', root), check=True, **kwargs)


def validate_unsigned_application(application):
    executable = application / app_name
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise SystemExit('tvOS 包缺少可执行的 GuoAppTV。')
    run(['xcrun', 'lipo', str(executable), '-verify_arch', 'arm64'])
    if (application / 'embedded.mobileprovision').exists():
        raise SystemExit('未签名 tvOS 包不应包含 provisioning profile。')
    signature = subprocess.run(['codesign', '-d', str(application)],
                               capture_output=True, text=True)
    if signature.returncode == 0 or 'not signed at all' not in signature.stderr:
        raise SystemExit('GuoAppTV.app 未通过无签名检查：' + signature.stderr)


def validate_package(package, prefix):
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        for name in [prefix + '/GuoAppTV', prefix + '/Info.plist']:
            if name not in names or archive.getinfo(name).file_size == 0:
                raise SystemExit('tvOS 压缩包缺少必要文件：' + name)
        # 安装工具靠 Info.plist 里的 CFBundleExecutable 找可执行文件；
        # 这里直接读包内 plist 校验，缺失就让 CI 失败，不再产出装不上的包。
        info = plistlib.loads(archive.read(prefix + '/Info.plist'))
        executable = info.get('CFBundleExecutable')
        if not executable:
            raise SystemExit('tvOS 压缩包 Info.plist 缺少 CFBundleExecutable，安装工具无法确定可执行文件。')
        if prefix + '/' + executable not in names:
            raise SystemExit('tvOS 压缩包缺少可执行文件：' + executable)
        print('tvOS 包可执行文件：' + executable)
        corrupt = archive.testzip()
        if corrupt:
            raise SystemExit('tvOS 压缩包损坏：' + corrupt)


def build_core(simulator=False, variant=BuildVariant()):
    if platform.system() != 'Darwin':
        raise SystemExit('tvOS 构建需要 macOS 和完整 Xcode。')
    go = shutil.which('go')
    if not go:
        raise SystemExit('请安装 Go 1.24.1 或更新版本。')
    environment = os.environ.copy()
    environment.setdefault('GOPROXY', 'https://goproxy.cn,direct')
    environment.setdefault('GOSUMDB', 'off')
    environment['CGO_ENABLED'] = '1'
    environment['GOTOOLCHAIN'] = os.environ.get('GOTOOLCHAIN', 'auto')
    # Go 没有 tvos GOOS：用 GOOS=ios + tvOS SDK 编译是 Go 维护者确认的
    # “最接近 tvOS” 的组合（golang/go#63203），与 iOS 核心同理；
    # CGO 对象与最终链接都必须用 tvOS SDK，否则会报未定义符号
    # （如 _darwin_arm_init_mach_exception_handler）。
    # 注意：GOOS=ios 下 internal/cpu 不检测 ARM64 加密扩展，AES-GCM /
    # SHA-256 走纯 Go 实现，CPU 占用会高于 iOS；如需优化可用 -overlay
    # 替换 cpu_arm64_other.go（sing-box#4486 的做法）。
    slices = [('appletvos', 'arm64', 'arm64-apple-tvos16.0')]
    if simulator:
        slices.extend([
            ('appletvsimulator', 'arm64', 'arm64-apple-tvos16.0-simulator'),
            ('appletvsimulator', 'amd64', 'x86_64-apple-tvos16.0-simulator'),
        ])
    libraries = []
    for sdk, architecture, triple in slices:
        sdk_path = subprocess.check_output(['xcrun', '--sdk', sdk, '--show-sdk-path'], text=True).strip()
        compiler = subprocess.check_output(['xcrun', '--sdk', sdk, '--find', 'clang'], text=True).strip()
        directory = core / 'build' / 'tvos' / f'{sdk}-{architecture}'
        headers = directory / 'Headers'
        headers.mkdir(parents=True, exist_ok=True)
        output = directory / 'libDuanjuCore.a'
        flags = shlex.join(['-isysroot', sdk_path, '-target', triple])
        build_env = environment | {
            'GOOS': 'ios', 'GOARCH': architecture, 'CC': compiler,
            'CGO_CFLAGS': flags, 'CGO_LDFLAGS': flags,
        }
        run([go, 'build', '-trimpath', '-buildmode=c-archive', '-ldflags=' + variant.linker_flags,
             '-o', str(output), './bridge'], cwd=core, env=build_env)
        shutil.copy2(output.with_suffix('.h'), headers / 'DuanjuCore.h')
        libraries.append((sdk, output, headers))
    arguments = ['xcodebuild', '-create-xcframework']
    device = libraries[0]
    arguments.extend(['-library', str(device[1]), '-headers', str(device[2])])
    if simulator:
        universal = core / 'build' / 'tvos' / 'simulator-universal'
        universal.mkdir(parents=True, exist_ok=True)
        archive = universal / 'libDuanjuCore.a'
        run(['xcrun', 'lipo', '-create', str(libraries[1][1]), str(libraries[2][1]), '-output', str(archive)])
        arguments.extend(['-library', str(archive), '-headers', str(libraries[1][2])])
    framework = root / 'tvos' / 'DuanjuCore' / 'DuanjuCore.xcframework'
    if framework.exists():
        shutil.rmtree(framework)
    run(arguments + ['-output', str(framework)])
    # 桥接头 #import "DuanjuCore.h"：把生成的 C 头文件复制到 Swift 工程目录，
    # 与 GuoAppTV-Bridging-Header.h 同目录，clang 按引号包含规则找到它。
    header = root / 'tvos' / 'GuoAppTV' / 'GuoAppTV' / 'DuanjuCore.h'
    shutil.copy2(device[2] / 'DuanjuCore.h', header)


def read_version():
    # 独立仓用根目录 VERSION 文件；旧 fork 里兼容 pubspec.yaml。
    version_file = root / 'VERSION'
    if version_file.is_file():
        return version_file.read_text().strip()
    return re.search(r'^version:\s*(\S+)', (root / 'pubspec.yaml').read_text(), re.MULTILINE).group(1)


def main():
    parser = argparse.ArgumentParser(description='构建红果鉴 / 真果鉴 tvOS 核心和应用')
    parser.add_argument('--core-only', action='store_true')
    parser.add_argument('--simulator', action='store_true', help='额外生成模拟器核心；不启动模拟器')
    parser.add_argument('--export-options', type=Path, help='使用自己的 Xcode 签名配置导出 IPA')
    add_variant_argument(parser)
    options = parser.parse_args()
    variant = BuildVariant(options.all_sources)
    build_core(options.simulator, variant)
    if options.core_only:
        return
    if not project.is_dir():
        raise SystemExit('缺少 tvOS 工程：' + str(project))
    output = root / 'dist' / 'tvos'
    output.mkdir(parents=True, exist_ok=True)
    version = read_version()
    artifacts = []
    derived = root / 'tvos' / 'GuoAppTV' / 'build'
    if options.export_options:
        config = options.export_options.expanduser().resolve()
        if not config.is_file():
            raise SystemExit('ExportOptions.plist 不存在。')
        archive = derived / 'GuoAppTV.xcarchive'
        if archive.exists():
            shutil.rmtree(archive)
        # 先解析 SPM 依赖（MPVKit 的 libmpv 二进制）：拉取失败时直接报错，
        # 不等到 archive/build 阶段才暴露。
        run(['xcodebuild', '-project', str(project), '-scheme', app_name,
             '-resolvePackageDependencies'])
        # 注意：xcodebuild 要求 -derivedDataPath 必须配合 -scheme，
        # 用 -target 会直接报错退出（exit 64）。
        run(['xcodebuild', '-project', str(project), '-scheme', app_name,
             '-sdk', 'appletvos', '-configuration', 'Release',
             '-derivedDataPath', str(derived), '-archivePath', str(archive), 'archive'])
        exported = derived / 'export'
        if exported.exists():
            shutil.rmtree(exported)
        run(['xcodebuild', '-exportArchive', '-archivePath', str(archive),
             '-exportOptionsPlist', str(config), '-exportPath', str(exported)])
        for package in exported.glob('*.ipa'):
            destination = output / f'{variant.slug}-{version}-tvos.ipa'
            shutil.copy2(package, destination)
            artifacts.append(destination)
    else:
        # 先解析 SPM 依赖（MPVKit 的 libmpv 二进制）：拉取失败时直接报错。
        run(['xcodebuild', '-project', str(project), '-scheme', app_name,
             '-resolvePackageDependencies'])
        run(['xcodebuild', '-project', str(project), '-scheme', app_name,
             '-sdk', 'appletvos', '-configuration', 'Release',
             '-derivedDataPath', str(derived), 'CODE_SIGNING_ALLOWED=NO', 'build'])
        application = derived / 'Build' / 'Products' / 'Release-appletvos' / f'{app_name}.app'
        validate_unsigned_application(application)
        # 两个版本共用一个工程：按版本改包内显示名（红果鉴 / 真果鉴）。
        display_name = '真果鉴' if variant.all_sources else '红果鉴'
        run(['/usr/libexec/PlistBuddy', '-c', f'Set :CFBundleDisplayName {display_name}',
             str(application / 'Info.plist')])
        symbols = subprocess.check_output(['xcrun', 'nm', '-gU', str(application / app_name)], text=True)
        for symbol in ['_DuanjuRequest', '_DuanjuFree']:
            if symbol not in symbols:
                raise SystemExit('tvOS 包缺少 FFI 入口：' + symbol)
        # IPA 结构为 zip 内 Payload/GuoAppTV.app；Apple TV 需在 Mac 上用 Xcode
        # 签名后安装，未签名包不能直接在设备上安装。
        payload = output / 'Payload'
        if payload.exists():
            shutil.rmtree(payload)
        payload.mkdir(parents=True)
        shutil.copytree(application, payload / application.name, symlinks=True)
        ipa = output / f'{variant.slug}-{version}-tvos-unsigned.ipa'
        if ipa.exists():
            ipa.unlink()
        run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(payload), str(ipa)])
        validate_package(ipa, 'Payload/GuoAppTV.app')
        shutil.rmtree(payload)
        artifacts.append(ipa)
    if not artifacts:
        raise SystemExit('未生成 tvOS 安装包。')
    for artifact in artifacts:
        print(artifact)


if __name__ == '__main__':
    main()

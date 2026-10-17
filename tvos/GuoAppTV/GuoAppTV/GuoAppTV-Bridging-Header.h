// 桥接头：把 Go 核心生成的 C 头文件暴露给 Swift。
// DuanjuCore.h 由 scripts/build_tvos.py 在构建核心时生成到本目录（已 gitignore），
// 不要手写；先跑 `python3 scripts/build_tvos.py --core-only` 再用 Xcode 打开工程。
#import "DuanjuCore.h"

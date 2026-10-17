# native/ 来源与固定版本

`native/` 是上游仓库 [Xanerix/guoapp](https://github.com/Xanerix/guoapp) 中
`native/` 目录的**快照副本**（vendored snapshot），不是 git submodule。
本仓没有 git 子模块依赖，下载 ZIP 即可直接构建。

- 上游仓库：https://github.com/Xanerix/guoapp
- 固定 commit：`d7e69fb0cd5b25da4107450738aabac11a1f260a`
- 快照日期：2026-10-16（上游该 commit 时间）
- 包含：`bridge/`（Go 桥接，`DuanjuRequest` FFI 入口）、`core/`（Go 核心）、
  `go.mod`、`go.sum`
- 不包含：上游的 Flutter 应用、Android / iOS / Windows 构建脚本

## 如何更新到上游新版本

1. 从上游仓库该 commit 复制 `native/` 覆盖本目录；
2. 把本文件的「固定 commit」与「快照日期」改成新值；
3. 在 Mac 上跑一次 `python3 scripts/build_tvos.py`（或跑 CI），确认通过；
4. 在 CHANGELOG.md「未发布」一节记一笔 native/ 同步到的 commit。

## 为什么不用 submodule

本仓面向网页上传（无本地 git 环境），submodule 需要 git 命令才能拉取；
快照副本下载即用，且构建结果完全由本仓文件决定，可复现。

package main

/*
#include <stdlib.h>
*/
import "C"
import "duanjuapp/native/core"

// 挂起恢复补丁的桥接出口，见 fork/core/tvos_stream_revive.go。
// 返回的字符串由调用方用 DuanjuFree 释放。

//export DuanjuReviveStream
func DuanjuReviveStream() *C.char { return C.CString(core.ReviveNativeStream()) }

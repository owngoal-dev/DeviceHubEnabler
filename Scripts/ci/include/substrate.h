// SPDX-License-Identifier: MIT
//
// The one function of the substrate-compatible interface this tweak calls. On
// the device the bootstrap's mobilesubstrate provider (ElleKit) exports it; CI
// links a stub that names where each bootstrap installs that library, as
// Apelin's on-device build does (lib/<bootstrap>/libsubstrate.tbd beside this
// header).
#pragma once

#include <objc/runtime.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Redirects the function at `symbol` to `replace`. When `result` is not NULL
/// it receives a callable trampoline to the original function.
extern void MSHookFunction(void *symbol, void *replace, void **result);

#ifdef __cplusplus
}
#endif

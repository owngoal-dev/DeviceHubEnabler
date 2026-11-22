// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lakr233
//
// DeviceHubEnabler lets Xcode's DeviceHub view the screen and play the system
// audio of an iOS 17–26 device running custom firmware. Rewritten for Apelin
// from yyyywaiwai/DeviceHubEnabler (MIT); the design comes from the DeviceHubFix
// research in Lakr233/vphone-cli.
//
// Only dtremotedisplayd, the screen-viewing daemon of the Developer Disk Image
// (DDI), is injected: the filter in apelin-project.json names its executable.
// Before a stream starts, DeviceHub asks the daemon which media stream features
// the device has and keeps asking until the answer is non-empty. On a
// production device the DDI's CoreDeviceUtilities answers 0 by policy (the
// device is "customer-restricted" and runs a pre-27.0 OS), not because the
// stream is impossible, so two of its getters are replaced and the view opens.
//
// The build defines APELIN_PACKAGE_ID, APELIN_VERSION and APELIN_BUILD_ID as
// string literals on every compile.
#import <Foundation/Foundation.h>
#import <os/log.h>
#import <substrate.h>
#import <dlfcn.h>
#import <stdatomic.h>
#import <stdbool.h>
#import <stdint.h>
#import <stdlib.h>
#import <sys/sysctl.h>

// MediaStreamSupportedFeatures bits, as CoreDeviceUtilities names them. The
// Mac reports the same set for itself (raw 0x8c).
#define DEVICEHUB_PRIMARY_VIDEO 0x04  // primary display mirrored output
#define DEVICEHUB_SYSTEM_AUDIO 0x08   // system audio output
#define DEVICEHUB_DISPLAY_INFO 0x80   // display information
#define DEVICEHUB_STREAM_FEATURES \
    (DEVICEHUB_PRIMARY_VIDEO | DEVICEHUB_SYSTEM_AUDIO | DEVICEHUB_DISPLAY_INFO)
_Static_assert(DEVICEHUB_STREAM_FEATURES == 0x8c,
               "Primary video, system audio and display information must add up to 0x8c");

// Swift symbols of the DDI's CoreDeviceUtilities. The framework is not in the
// SDK and its private symbols may change with a DDI update, so they are looked
// up by their mangled names and nothing is hooked unless all three are found.
// MediaStreamSupportedFeatures.current.getter: a resilient struct, which the
// getter returns indirectly through x8.
static const char *const kCurrentFeaturesGetter =
    "$s19CoreDeviceUtilities28MediaStreamSupportedFeaturesV7currentACvgZ";
// MediaStreamSupportedFeatures.init(rawValue: UInt64), which builds the struct.
static const char *const kRawValueInit =
    "$s19CoreDeviceUtilities28MediaStreamSupportedFeaturesV8rawValueACs6UInt64V_tcfC";
// CurrentDevice.isCustomerRestricted.getter -> Bool.
static const char *const kIsCustomerRestrictedGetter =
    "$s19CoreDeviceUtilities07CurrentB0V20isCustomerRestrictedSbvg";

// The DDI's own initializer, so the value it writes has the DDI's layout,
// which this tweak cannot know.
typedef void __attribute__((swiftcall)) (*FeatureInit)(
    void *__attribute__((swift_indirect_result)) result, uint64_t rawValue);
static FeatureInit InitFeatures;

static os_log_t TweakLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create(APELIN_PACKAGE_ID, "tweak");
    });
    return log;
}

// The first calls are logged, to see the hooks fire when a Mac connects; the
// question stops once DeviceHub has its answer.
#define DEVICEHUB_LOGGED_CALLS 8

static _Atomic int32_t CurrentFeaturesCalls;

// Replaces MediaStreamSupportedFeatures.current.getter.
static void __attribute__((swiftcall)) HookedCurrentFeatures(
    void *__attribute__((swift_indirect_result)) result) {
    InitFeatures(result, DEVICEHUB_STREAM_FEATURES);
    if (atomic_fetch_add(&CurrentFeaturesCalls, 1) < DEVICEHUB_LOGGED_CALLS) {
        os_log(TweakLog(), "MediaStreamSupportedFeatures.current -> 0x%{public}llx",
               (unsigned long long)DEVICEHUB_STREAM_FEATURES);
    }
}

static _Atomic int32_t IsCustomerRestrictedCalls;

// Replaces CurrentDevice.isCustomerRestricted.getter.
static bool __attribute__((swiftcall)) HookedIsCustomerRestricted(void) {
    if (atomic_fetch_add(&IsCustomerRestrictedCalls, 1) < DEVICEHUB_LOGGED_CALLS) {
        os_log(TweakLog(), "CurrentDevice.isCustomerRestricted -> false");
    }
    return false;
}

// The OS major version, or -1 when kern.osproductversion cannot be read or
// does not start with a number.
static long SystemMajorVersion(void) {
    char version[32];
    size_t length = sizeof(version);
    if (sysctlbyname("kern.osproductversion", version, &length, NULL, 0) != 0 ||
        length == 0 || version[length - 1] != '\0') {
        return -1;
    }
    char *end = NULL;
    long major = strtol(version, &end, 10);
    if (end == version || (*end != '.' && *end != '\0')) {
        return -1;
    }
    return major;
}

__attribute__((constructor)) static void TweakInitialize(void) {
    // Apelin's confirm_loaded looks for this exact marker and build id under
    // the package id's subsystem. Keep the line, and keep it public.
    os_log(TweakLog(), "ApelinLoaded %{public}s in %{public}s", APELIN_BUILD_ID, getprogname());

    // Only iOS 17.0 through 26.x: older systems use the legacy developer disk
    // image, which Xcode 27 does not connect, and 27.0 and later report the
    // features on their own.
    long major = SystemMajorVersion();
    if (major < 17 || major >= 27) {
        os_log(TweakLog(), "OS major version %{public}ld is outside 17–26, no hooks", major);
        return;
    }
    os_log(TweakLog(), "OS major version %{public}ld, looking for the DDI's symbols", major);

    void *current = dlsym(RTLD_DEFAULT, kCurrentFeaturesGetter);
    InitFeatures = (FeatureInit)dlsym(RTLD_DEFAULT, kRawValueInit);
    void *restricted = dlsym(RTLD_DEFAULT, kIsCustomerRestrictedGetter);
    os_log(TweakLog(), "MediaStreamSupportedFeatures.current: %{public}s",
           current != NULL ? "found" : "missing");
    os_log(TweakLog(), "MediaStreamSupportedFeatures.init(rawValue:): %{public}s",
           InitFeatures != NULL ? "found" : "missing");
    os_log(TweakLog(), "CurrentDevice.isCustomerRestricted: %{public}s",
           restricted != NULL ? "found" : "missing");
    if (current == NULL || InitFeatures == NULL || restricted == NULL) {
        os_log(TweakLog(), "A symbol is missing, system behaviour kept");
        return;
    }

    // The originals are not needed: the replacement is the whole answer.
    MSHookFunction(current, (void *)HookedCurrentFeatures, NULL);
    MSHookFunction(restricted, (void *)HookedIsCustomerRestricted, NULL);
    os_log(TweakLog(), "Hooks installed: current -> 0x%{public}llx, isCustomerRestricted -> false",
           (unsigned long long)DEVICEHUB_STREAM_FEATURES);
}

#include <jni.h>

// Tracy is an optional frame/profiling transport. Mojang's current Windows
// binary is linked to the UCRT and post-XP ETW/Winsock entry points even when
// no profiler is attached. This JNI-compatible replacement keeps every game
// call valid while disabling only the optional Tracy capture stream.

extern "C" {

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM*, void*) { return JNI_VERSION_1_8; }

JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_startup(JNIEnv*, jclass) {}
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_shutdown(JNIEnv*, jclass) {}
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_markFrame(JNIEnv*, jclass, jlong) {}
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_markFrameStart(JNIEnv*, jclass, jlong) {}
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_markFrameEnd(JNIEnv*, jclass, jlong) {}

JNIEXPORT jint JNICALL Java_com_mojang_jtracy_TracyBindings_beginZone(
    JNIEnv*, jclass, jstring, jstring, jstring, jint) { return 0; }
JNIEXPORT jint JNICALL Java_com_mojang_jtracy_TracyBindings_frameImage(
    JNIEnv*, jclass, jobject, jint, jint, jint, jboolean) { return 0; }
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_endZone(
    JNIEnv*, jclass, jint) {}
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_addZoneText(
    JNIEnv*, jclass, jint, jstring) {}
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_setZoneColor(
    JNIEnv*, jclass, jint, jint) {}
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_addZoneValue(
    JNIEnv*, jclass, jint, jlong) {}

JNIEXPORT jlong JNICALL Java_com_mojang_jtracy_TracyBindings_mallocNamed(
    JNIEnv*, jclass, jlong, jlong, jint) { return 0; }
JNIEXPORT jlong JNICALL Java_com_mojang_jtracy_TracyBindings_freeNamed(
    JNIEnv*, jclass, jlong, jlong) { return 0; }
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_setThreadName(
    JNIEnv*, jclass, jstring, jint) {}
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_plotValue(
    JNIEnv*, jclass, jlong, jdouble) {}
JNIEXPORT jlong JNICALL Java_com_mojang_jtracy_TracyBindings_leakName(
    JNIEnv*, jclass, jstring) { return 0; }
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_appInfo(
    JNIEnv*, jclass, jstring) {}
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_message(
    JNIEnv*, jclass, jstring) {}
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_messageColored(
    JNIEnv*, jclass, jstring, jint) {}

JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_newGpuContext(
    JNIEnv*, jclass, jint, jlong, jfloat, jint, jint) {}
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_setGpuContextName(
    JNIEnv*, jclass, jint, jstring) {}
JNIEXPORT jint JNICALL Java_com_mojang_jtracy_TracyBindings_beginGpuZone(
    JNIEnv*, jclass, jint, jint, jstring, jstring, jstring, jint) { return 0; }
JNIEXPORT jint JNICALL Java_com_mojang_jtracy_TracyBindings_endGpuZone(
    JNIEnv*, jclass, jint, jint) { return 0; }
JNIEXPORT jint JNICALL Java_com_mojang_jtracy_TracyBindings_submitQueryTimestamp(
    JNIEnv*, jclass, jint, jint, jlong) { return 0; }

// Added by jtracy 1.14.x (Minecraft 26.3). Keep the no-op transport ABI
// complete so a future code path cannot fail with UnsatisfiedLinkError.
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_sectionSetup(
    JNIEnv*, jclass, jint, jstring) {}
JNIEXPORT jint JNICALL Java_com_mojang_jtracy_TracyBindings_sectionEnter(
    JNIEnv*, jclass, jint, jstring) { return 0; }
JNIEXPORT void JNICALL Java_com_mojang_jtracy_TracyBindings_sectionLeave(
    JNIEnv*, jclass, jint) {}

}  // extern "C"

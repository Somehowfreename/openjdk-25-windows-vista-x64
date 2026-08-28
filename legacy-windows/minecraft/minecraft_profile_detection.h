/*
 * Copyright (c) 2026 Legacy Windows OpenJDK contributors.
 *
 * GPLv2 with Classpath Exception. See the repository LICENSE files.
 */

#ifndef LEGACY_WINDOWS_MINECRAFT_PROFILE_DETECTION_H
#define LEGACY_WINDOWS_MINECRAFT_PROFILE_DETECTION_H

#include <ctype.h>
#include <stddef.h>
#include <string.h>

enum MinecraftCompatibilityProfile {
  MINECRAFT_PROFILE_UNKNOWN = 0,
  MINECRAFT_PROFILE_1_20 = 120,
  MINECRAFT_PROFILE_1_20_2 = 1202,
  MINECRAFT_PROFILE_1_21 = 121,
  MINECRAFT_PROFILE_1_21_11 = 12111,
  MINECRAFT_PROFILE_26 = 260
};

static int minecraft_ascii_equal_ignore_case(char left, char right) {
  return tolower((unsigned char)left) == tolower((unsigned char)right);
}

static int minecraft_starts_with_ignore_case(const char* value,
                                             const char* prefix) {
  if (value == NULL || prefix == NULL) return 0;
  while (*prefix != '\0') {
    if (*value == '\0' ||
        !minecraft_ascii_equal_ignore_case(*value, *prefix)) {
      return 0;
    }
    ++value;
    ++prefix;
  }
  return 1;
}

static const char* minecraft_find_ignore_case(const char* value,
                                              const char* needle) {
  const char* candidate;
  if (value == NULL || needle == NULL || *needle == '\0') return value;
  for (candidate = value; *candidate != '\0'; ++candidate) {
    if (minecraft_starts_with_ignore_case(candidate, needle)) {
      return candidate;
    }
  }
  return NULL;
}

static int minecraft_is_version_suffix(char value) {
  return value == '\0' || value == '.' || value == '-' || value == '_' ||
         value == '+';
}

static enum MinecraftCompatibilityProfile minecraft_classify_version(
    const char* value) {
  if (value == NULL) return MINECRAFT_PROFILE_UNKNOWN;
  if (minecraft_starts_with_ignore_case(value, "1.20.2") &&
      minecraft_is_version_suffix(value[6])) {
    return MINECRAFT_PROFILE_1_20_2;
  }
  if (minecraft_starts_with_ignore_case(value, "1.21.11") &&
      minecraft_is_version_suffix(value[7])) {
    return MINECRAFT_PROFILE_1_21_11;
  }
  if (minecraft_starts_with_ignore_case(value, "1.20") &&
      minecraft_is_version_suffix(value[4])) {
    return MINECRAFT_PROFILE_1_20;
  }
  if (minecraft_starts_with_ignore_case(value, "1.21") &&
      minecraft_is_version_suffix(value[4])) {
    return MINECRAFT_PROFILE_1_21;
  }
  if (minecraft_starts_with_ignore_case(value, "26") &&
      minecraft_is_version_suffix(value[2])) {
    return MINECRAFT_PROFILE_26;
  }
  return MINECRAFT_PROFILE_UNKNOWN;
}

static enum MinecraftCompatibilityProfile minecraft_profile_from_path(
    const char* value) {
  static const char* const one_twenty_two_markers[] = {
      "\\versions\\1.20.2", "/versions/1.20.2",
      "\\net.minecraft\\1.20.2", "/net.minecraft/1.20.2",
      "\\minecraft\\1.20.2", "/minecraft/1.20.2"};
  static const char* const one_twenty_one_eleven_markers[] = {
      "\\versions\\1.21.11", "/versions/1.21.11",
      "\\net.minecraft\\1.21.11", "/net.minecraft/1.21.11",
      "\\minecraft\\1.21.11", "/minecraft/1.21.11"};
  static const char* const one_twenty_markers[] = {
      "\\versions\\1.20", "/versions/1.20", "\\net.minecraft\\1.20",
      "/net.minecraft/1.20", "\\minecraft\\1.20", "/minecraft/1.20"};
  static const char* const one_twenty_one_markers[] = {
      "\\versions\\1.21", "/versions/1.21", "\\net.minecraft\\1.21",
      "/net.minecraft/1.21", "\\minecraft\\1.21", "/minecraft/1.21"};
  static const char* const twenty_six_markers[] = {
      "\\versions\\26", "/versions/26", "\\net.minecraft\\26",
      "/net.minecraft/26", "\\minecraft\\26", "/minecraft/26"};
  size_t index;

  if (value == NULL) return MINECRAFT_PROFILE_UNKNOWN;
  for (index = 0;
       index < sizeof(one_twenty_two_markers) /
                   sizeof(one_twenty_two_markers[0]);
       ++index) {
    if (minecraft_find_ignore_case(value, one_twenty_two_markers[index]) !=
        NULL) {
      return MINECRAFT_PROFILE_1_20_2;
    }
  }
  for (index = 0;
       index < sizeof(one_twenty_one_eleven_markers) /
                   sizeof(one_twenty_one_eleven_markers[0]);
       ++index) {
    if (minecraft_find_ignore_case(
            value, one_twenty_one_eleven_markers[index]) != NULL) {
      return MINECRAFT_PROFILE_1_21_11;
    }
  }
  for (index = 0;
       index < sizeof(one_twenty_markers) / sizeof(one_twenty_markers[0]);
       ++index) {
    if (minecraft_find_ignore_case(value, one_twenty_markers[index]) != NULL) {
      return MINECRAFT_PROFILE_1_20;
    }
  }
  for (index = 0;
       index < sizeof(one_twenty_one_markers) /
                   sizeof(one_twenty_one_markers[0]);
       ++index) {
    if (minecraft_find_ignore_case(value, one_twenty_one_markers[index]) !=
        NULL) {
      return MINECRAFT_PROFILE_1_21;
    }
  }
  for (index = 0;
       index < sizeof(twenty_six_markers) / sizeof(twenty_six_markers[0]);
       ++index) {
    if (minecraft_find_ignore_case(value, twenty_six_markers[index]) != NULL) {
      return MINECRAFT_PROFILE_26;
    }
  }
  return MINECRAFT_PROFILE_UNKNOWN;
}

static enum MinecraftCompatibilityProfile minecraft_detect_profile(
    int argc, char** argv) {
  int index;
  enum MinecraftCompatibilityProfile path_profile =
      MINECRAFT_PROFILE_UNKNOWN;

  if (argc < 1 || argv == NULL) return MINECRAFT_PROFILE_UNKNOWN;
  for (index = 1; index < argc; ++index) {
    const char* argument = argv[index];
    enum MinecraftCompatibilityProfile candidate;
    if (argument == NULL) continue;

    if ((strcmp(argument, "--version") == 0 ||
         strcmp(argument, "--versionName") == 0) &&
        index + 1 < argc) {
      candidate = minecraft_classify_version(argv[index + 1]);
      if (candidate != MINECRAFT_PROFILE_UNKNOWN) return candidate;
    }
    if (minecraft_starts_with_ignore_case(argument, "--version=")) {
      candidate = minecraft_classify_version(argument + 10);
      if (candidate != MINECRAFT_PROFILE_UNKNOWN) return candidate;
    }
    if (minecraft_starts_with_ignore_case(
            argument, "-Dlegacy.windows.minecraft.version=")) {
      static const char version_property[] =
          "-Dlegacy.windows.minecraft.version=";
      candidate = minecraft_classify_version(argument +
                                               strlen(version_property));
      if (candidate != MINECRAFT_PROFILE_UNKNOWN) return candidate;
    }
    if (path_profile == MINECRAFT_PROFILE_UNKNOWN) {
      path_profile = minecraft_profile_from_path(argument);
    }
  }
  return path_profile;
}

#endif  /* LEGACY_WINDOWS_MINECRAFT_PROFILE_DETECTION_H */

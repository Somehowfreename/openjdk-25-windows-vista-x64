/* GPLv2 with Classpath Exception. See the repository LICENSE files. */

#include <stdio.h>

#include "../minecraft_profile_detection.h"

struct ProfileCase {
  const char* name;
  int argc;
  char** argv;
  enum MinecraftCompatibilityProfile expected;
};

static int run_case(const struct ProfileCase* test) {
  const enum MinecraftCompatibilityProfile actual =
      minecraft_detect_profile(test->argc, test->argv);
  if (actual != test->expected) {
    fprintf(stderr, "%s: expected %d, got %d\n", test->name,
            (int)test->expected, (int)actual);
    return 0;
  }
  return 1;
}

int main(void) {
  char* minecraft_120[] = {"javaw", "--version", "1.20"};
  char* minecraft_1202[] = {"javaw", "--version", "1.20.2"};
  char* minecraft_121[] = {"javaw", "--version", "1.21"};
  char* minecraft_12111[] = {"javaw", "--version", "1.21.11"};
  char* minecraft_261[] = {"javaw", "--version", "26.1"};
  char* minecraft_263[] = {"javaw", "--version=26.3-snapshot-9"};
  char* multimc_121[] = {
      "javaw", "-cp",
      "C:\\MultiMC\\libraries\\com\\mojang\\minecraft\\1.21\\minecraft-1.21-client.jar",
      "org.multimc.EntryPoint"};
  char* multimc_12111[] = {
      "javaw", "-cp",
      "C:\\MultiMC\\libraries\\com\\mojang\\minecraft\\1.21.11\\minecraft-1.21.11-client.jar",
      "org.multimc.EntryPoint"};
  char* multimc_1202[] = {
      "javaw", "-cp",
      "C:\\MultiMC\\libraries\\com\\mojang\\minecraft\\1.20.2\\minecraft-1.20.2-client.jar",
      "org.multimc.EntryPoint"};
  char* multimc_120[] = {
      "javaw", "-cp",
      "C:\\MultiMC\\libraries\\com\\mojang\\minecraft\\1.20\\minecraft-1.20-client.jar",
      "org.multimc.EntryPoint"};
  char* multimc_26[] = {
      "javaw", "-cp",
      "C:\\MultiMC\\libraries\\com\\mojang\\minecraft\\26.2\\minecraft-26.2-client.jar",
      "org.multimc.EntryPoint"};
  char* mixed_case_121[] = {
      "javaw", "-cp",
      "C:\\MultiMC\\Libraries\\COM\\MOJANG\\MINECRAFT\\1.21\\client.jar",
      "org.multimc.EntryPoint"};
  char* property_26[] = {
      "javaw", "-Dlegacy.windows.minecraft.version=26.2", "-cp", "client.jar"};
  char* property_120[] = {
      "javaw", "-Dlegacy.windows.minecraft.version=1.20.1", "-cp",
      "client.jar"};
  char* unrelated[] = {"javaw", "-version"};
  char* incomplete[] = {"javaw", "--version"};
  char* not_121[] = {"javaw", "--version", "1.210"};
  char* not_120[] = {"javaw", "--version", "1.200"};
  char* not_26[] = {"javaw", "--version", "260.1"};
  struct ProfileCase cases[] = {
      {"Minecraft 1.20", 3, minecraft_120, MINECRAFT_PROFILE_1_20},
      {"Minecraft 1.20.2", 3, minecraft_1202, MINECRAFT_PROFILE_1_20_2},
      {"Minecraft 1.21", 3, minecraft_121, MINECRAFT_PROFILE_1_21},
      {"Minecraft 1.21.11", 3, minecraft_12111,
       MINECRAFT_PROFILE_1_21_11},
      {"Minecraft 26.1", 3, minecraft_261, MINECRAFT_PROFILE_26},
      {"Minecraft 26.3 snapshot", 2, minecraft_263, MINECRAFT_PROFILE_26},
      {"MultiMC 1.20 classpath", 4, multimc_120, MINECRAFT_PROFILE_1_20},
      {"MultiMC 1.20.2 classpath", 4, multimc_1202,
       MINECRAFT_PROFILE_1_20_2},
      {"MultiMC 1.21 classpath", 4, multimc_121, MINECRAFT_PROFILE_1_21},
      {"MultiMC 1.21.11 classpath", 4, multimc_12111,
       MINECRAFT_PROFILE_1_21_11},
      {"MultiMC 26 classpath", 4, multimc_26, MINECRAFT_PROFILE_26},
      {"Mixed-case 1.21 classpath", 4, mixed_case_121,
       MINECRAFT_PROFILE_1_21},
      {"Explicit 26 property", 4, property_26, MINECRAFT_PROFILE_26},
      {"Explicit 1.20 property", 4, property_120, MINECRAFT_PROFILE_1_20},
      {"JVM version query", 2, unrelated, MINECRAFT_PROFILE_UNKNOWN},
      {"Incomplete version option", 2, incomplete, MINECRAFT_PROFILE_UNKNOWN},
      {"Reject 1.200", 3, not_120, MINECRAFT_PROFILE_UNKNOWN},
      {"Reject 1.210", 3, not_121, MINECRAFT_PROFILE_UNKNOWN},
      {"Reject 260.1", 3, not_26, MINECRAFT_PROFILE_UNKNOWN},
  };
  size_t index;
  for (index = 0; index < sizeof(cases) / sizeof(cases[0]); ++index) {
    if (!run_case(&cases[index])) return 1;
  }
  puts("MINECRAFT_PROFILE_DETECTION_TEST_PASS");
  return 0;
}

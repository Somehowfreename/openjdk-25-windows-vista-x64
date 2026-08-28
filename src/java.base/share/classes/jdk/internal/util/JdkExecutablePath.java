/*
 * Copyright (c) 2026, Somehowfreename. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  Oracle designates this
 * particular file as subject to the "Classpath" exception as provided
 * by Oracle in the LICENSE file that accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 */

package jdk.internal.util;

import java.io.File;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;

/**
 * Resolves executables in both conventional JDK images and the private
 * executable layout used by the legacy Windows distribution.
 */
public final class JdkExecutablePath {
    private static final Path LEGACY_WINDOWS_EXECUTABLES = Path.of(
            "lib", "legacy-windows", "internal", "launcher", "executables");

    private JdkExecutablePath() {
    }

    public static Path resolve(Path javaHome, String executable) {
        Path standard = javaHome.resolve("bin").resolve(executable);
        Path resolved = existingWindowsExecutable(standard);
        if (resolved != null) {
            return resolved;
        }

        if (File.separatorChar == '\\') {
            Path privateExecutable = javaHome.resolve(LEGACY_WINDOWS_EXECUTABLES)
                    .resolve(executable);
            resolved = existingWindowsExecutable(privateExecutable);
            if (resolved != null) {
                return resolved;
            }
        }

        return standard;
    }

    public static String resolve(String javaHome, String executable) {
        return resolve(Path.of(javaHome), executable).toString();
    }

    private static Path existingWindowsExecutable(Path path) {
        if (Files.isRegularFile(path)) {
            return path;
        }
        if (File.separatorChar == '\\' &&
                !path.getFileName().toString().toLowerCase(Locale.ROOT).endsWith(".exe")) {
            Path executablePath = path.resolveSibling(path.getFileName() + ".exe");
            if (Files.isRegularFile(executablePath)) {
                return executablePath;
            }
        }
        return null;
    }
}

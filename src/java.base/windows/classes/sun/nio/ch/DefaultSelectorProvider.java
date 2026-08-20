/*
 * Copyright (c) 2001, 2024, Oracle and/or its affiliates. All rights reserved.
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
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 */

package sun.nio.ch;

/**
 * Creates this platform's default SelectorProvider
 */

public class DefaultSelectorProvider {
    private static final SelectorProviderImpl INSTANCE = create();

    private static SelectorProviderImpl create() {
        // The AFD polling protocol used by wepoll is not compatible with the
        // Windows XP AFD driver. Retain the modern provider on Windows 7 and
        // newer, and use the maintained select(2)-based implementation that
        // is already shipped in java.base only on NT 5.x.
        String version = System.getProperty("os.version", "");
        if (version.startsWith("5.")) {
            return new WindowsSelectorProvider();
        }
        return new WEPollSelectorProvider();
    }

    /**
     * Prevent instantiation.
     */
    private DefaultSelectorProvider() { }

    /**
     * Returns the default SelectorProvider implementation.
     */
    public static SelectorProviderImpl get() {
        return INSTANCE;
    }
}

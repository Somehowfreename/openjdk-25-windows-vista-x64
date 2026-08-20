/*
 * Copyright (c) 2026, OpenJDK XP Backport contributors. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.  This particular file is subject
 * to the "Classpath" exception as provided in the LICENSE file that
 * accompanied this code.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 */

/*
 * The Windows vector routines are hand-written assembly.  MASM emits a
 * reference to this marker when floating-point instructions are present, but
 * no runtime implementation is required.  Defining it locally allows the DLL
 * to use /NOENTRY and avoid an otherwise unnecessary Universal CRT startup.
 */
int _fltused = 0;

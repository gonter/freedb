freedb Windows Database Updater
-------------------------------

Copyright (C) 2001-2003 Florian Maul (florian@freedb.org) and Marco Hellmann
Optimizations by Fidel in 2002.

General info / About:
---------------------

This tool updates the freedb Windows format database using the ordinary 
Unix format freedb updates - no need to download the full database anymore. 

It was written for freedb by Florian Maul and Marco Hellmann using
tar-code by Stefan Heymann [1] and a bzip2 interface by Alex Buloichik [2].

Use this software at your own risk. We're not responsible for any damage
it may cause. You may send bug reports or questions to info@freedb.org or 
florian@freedb.org

The Windows database updater was successfully compiled with Borland Delphi 5.
For the release the exe was compressed with UPX [3] and Spoon Installer [4] 
is used to provide an easy installation of the freedb updater.

[1] http://www.destructor.de
[2] http://alex73.da.ru/
[3] http://upx.sourceforge.net
[4] http://sourceforge.net/projects/spoon-installer/


License:
--------
This is free software under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2 of the
License, or (at your option) any later version.

The freedb Windows database updater is distributed in the hope that it will 
be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

The GPL does not apply to the following parts of the package:
- the libbz2.dll, which is needed by this program. 
  The libbz2.dll is released under the terms of the BSD license and is
  Copyright (C) 1996-2000 Julian R Seward
  The sources can be found at http://sources.redhat.com/bzip2/
- the bzip2 interface library, which is open source freeware.
  The bzip2 interface library is Copyright (C) Alex Buloichik
- the LibTar library, which is released under the terms of the DSL 
  (see http://www.destructor.de for details on the DSL)
  The LibTar is Copyright (C) Stefan Heymann
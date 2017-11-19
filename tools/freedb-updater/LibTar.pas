(**
===============================================================================================
Name    : LibTar
===============================================================================================
Subject : Handling of "tar" files
===============================================================================================
Author  : Stefan Heymann
          Eschenweg 3
          72076 Tübingen
          GERMANY

          Please send notes, bug reports, fixes and questions to
                 stefan@destructor.de
===============================================================================================
Usage
-----
- Choose a constructor
- Make an instance of TTarArchive                  TA := TTarArchive.Create (Filename);
- Scan through the archive                         TA.Reset;
                                                   WHILE TA.FindNext (DirRec) DO BEGIN
- Evaluate the DirRec for each file                  ListBox.Items.Add (DirRec.Name);
- Read out the current file                          TA.ReadFile (DestFilename);
  (You can ommit this if you want to
  read in the directory only)                        END;
- You're done                                      TA.Free


Source, Legals ("Licence")
--------------------------
The official site to get this code is http://www.destructor.de

Usage and Distribution of this Source Code is ruled by the
"Destructor.de Source code Licence" (DSL) which comes with this file or
can be downloaded at http://www.destructor.de

IN SHORT: Usage and distribution of this source code is free.
          You use it completely on your own risk.

Postcardware
------------
If you like this code, please send a postcard of your city to my above address.
===============================================================================================
!!!  All parts of this code which are not finished or known to be buggy
     are marked with three exclamation marks
===============================================================================================
Date        Author Changes
-----------------------------------------------------------------------------------------------
2001-04-26  HeySt  0.0.1 Start
2001-04-28  HeySt  1.0.0 First Release

Note: This is not the original release of the LibTar. A small bugfix regarding links was 
included by Florian Maul and Marco Hellmann. 
You can get the original release from http://www.destructor.de

$Id: LibTar.pas,v 1.3 2002/07/15 20:47:12 joerg78 Exp $
*)

UNIT LibTar;

INTERFACE

USES
  SysUtils, Classes;

TYPE
  // --- File Access Permissions
  TTarPermission  = (tpReadByOwner, tpWriteByOwner, tpExecuteByOwner,
                     tpReadByGroup, tpWriteByGroup, tpExecuteByGroup,
                     tpReadByOther, tpWriteByOther, tpExecuteByOther);
  TTarPermissions = SET OF TTarPermission;

  // --- Type of File
  TFileType = (ftNormal,          // Regular file
               ftLink,            // Link to another, previously archived, file (LinkName)
               ftSymbolicLink,    // Symbolic link to another file              (LinkName)
               ftCharacter,       // Character special files
               ftBlock,           // Block special files
               ftDirectory,       // Directory entry. Size is zero (unlimited) or max. number of bytes
               ftFifo,            // FIFO special file. No data stored in the archive.
               ftContiguous,      // Contiguous file, if supported by OS
               ftDumpDir,         // List of files
               ftMultiVolume,     // Multi-volume file part
               ftVolumeHeader);   // Volume header. Can appear only as first record in the archive

  // --- Mode
  TTarMode  = (tmSetUid, tmSetGid, tmSaveText);
  TTarModes = SET OF TTarMode;

  // --- Record for a Directory Entry
  TTarDirRec  = RECORD //packed RECORD
                  Name        : STRING;            // File path and name
                  Size        : INT64;             // File size in Bytes
                  DateTime    : TDateTime;         // Last modification date and time
                  Permissions : TTarPermissions;   // Access permissions
                  FileType    : TFileType;         // Type of file
                  LinkName    : STRING;            // Name of linked file (for ftLink, ftSymbolicLink)
                  UID         : INTEGER;           // User ID
                  GID         : INTEGER;           // Group ID
                  UserName    : STRING;            // User name
                  GroupName   : STRING;            // Group name
                  ChecksumOK  : BOOLEAN;           // Checksum was OK
                  Mode        : TTarModes;         // Mode
                  Magic       : STRING;            // Contents of the "Magic" field
                  MajorDevNo  : INTEGER;           // Major Device No. for ftCharacter and ftBlock
                  MinorDevNo  : INTEGER;           // Minor Device No. for ftCharacter and ftBlock
                  FilePos     : INT64;             // Position in TAR file
                END;

  // --- The TAR Archive CLASS
  TTarArchive = CLASS
                PROTECTED
                  FStream     : TStream;   // Internal Stream
                  FOwnsStream : BOOLEAN;   // True if FStream is owned by the TTarArchive instance
                  FBytesToGo  : INTEGER;   // Bytes until the next Header Record
                PUBLIC
                  CONSTRUCTOR Create (Stream   : TStream);                                OVERLOAD;
                  CONSTRUCTOR Create (Filename : STRING;
                                      FileMode : WORD = fmOpenRead OR fmShareDenyWrite);  OVERLOAD;
                  DESTRUCTOR Destroy;                                       OVERRIDE;
                  PROCEDURE Reset;                                         // Reset File Pointer
                  FUNCTION  FindNext (VAR DirRec : TTarDirRec) : BOOLEAN;  // Reads next Directory Info Record. FALSE if EOF reached
                  PROCEDURE ReadFile (Buffer   : POINTER); OVERLOAD;       // Reads file data for last Directory Record
                  PROCEDURE ReadFile (Stream   : TStream); OVERLOAD;       // -;-
                  PROCEDURE ReadFile (Filename : STRING);  OVERLOAD;       // -;-
                  FUNCTION  ReadFile : STRING;           OVERLOAD;         // -;-

                  PROCEDURE GetFilePos (VAR Current, Size : INT64);        // Current File Position
                  PROCEDURE SetFilePos (NewPos : INT64);                   // Set new Current File Position
                END;

CONST
  FILETYPE_NAME : ARRAY [TFileType] OF STRING =
                  ('Regular', 'Link', 'Symbolic Link', 'Char File', 'Block File',
                   'Directory', 'FIFO File', 'Contiguous', 'Dir Dump', 'Multivol', 'Volume Header');


FUNCTION PermissionString (Permissions : TTarPermissions) : STRING;

(*
===============================================================================================
IMPLEMENTATION
===============================================================================================
*)

IMPLEMENTATION

FUNCTION PermissionString (Permissions : TTarPermissions) : STRING;
BEGIN
  Result := '';
  IF tpReadByOwner    IN Permissions THEN Result := Result + 'r' ELSE Result := Result + '-';
  IF tpWriteByOwner   IN Permissions THEN Result := Result + 'w' ELSE Result := Result + '-';
  IF tpExecuteByOwner IN Permissions THEN Result := Result + 'x' ELSE Result := Result + '-';
  IF tpReadByGroup    IN Permissions THEN Result := Result + 'r' ELSE Result := Result + '-';
  IF tpWriteByGroup   IN Permissions THEN Result := Result + 'w' ELSE Result := Result + '-';
  IF tpExecuteByGroup IN Permissions THEN Result := Result + 'x' ELSE Result := Result + '-';
  IF tpReadByOther    IN Permissions THEN Result := Result + 'r' ELSE Result := Result + '-';
  IF tpWriteByOther   IN Permissions THEN Result := Result + 'w' ELSE Result := Result + '-';
  IF tpExecuteByOther IN Permissions THEN Result := Result + 'x' ELSE Result := Result + '-';
END;


(*
===============================================================================================
TAR format
===============================================================================================
*)

CONST
  RECORDSIZE = 512;
  NAMSIZ     = 100;
  TUNMLEN    =  32;
  TGNMLEN    =  32;
  CHKBLANKS  = #32#32#32#32#32#32#32#32;

TYPE
  TTarHeader = RECORD //packed RECORD
                 Name     : ARRAY [0..NAMSIZ-1] OF CHAR;
                 Mode     : ARRAY [0..7] OF CHAR;
                 UID      : ARRAY [0..7] OF CHAR;
                 GID      : ARRAY [0..7] OF CHAR;
                 Size     : ARRAY [0..11] OF CHAR;
                 MTime    : ARRAY [0..11] OF CHAR;
                 ChkSum   : ARRAY [0..7] OF CHAR;
                 LinkFlag : CHAR;
                 LinkName : ARRAY [0..NAMSIZ-1] OF CHAR;
                 Magic    : ARRAY [0..7] OF CHAR;
                 UName    : ARRAY [0..TUNMLEN-1] OF CHAR;
                 GName    : ARRAY [0..TGNMLEN-1] OF CHAR;
                 DevMajor : ARRAY [0..7] OF CHAR;
                 DevMinor : ARRAY [0..7] OF CHAR;
               END;

FUNCTION ExtractText (P : PChar) : STRING;
BEGIN
  Result := STRING (P);
END;


FUNCTION ExtractNumber (P : PChar) : INTEGER; OVERLOAD;
BEGIN
  Result := 0;
  WHILE (P^ <> #32) AND (P^ <> #0) DO BEGIN
    Result := (ORD (P^) - ORD ('0')) OR (Result SHL 3);
    INC (P);
    END;
END;


FUNCTION ExtractNumber (P : PChar; MaxLen : INTEGER) : INT64; OVERLOAD;
VAR
  Last : PChar;
BEGIN
  Result := 0;
  Last   := P + MaxLen - 1;
  WHILE (P <= Last) AND (P^ <> #0) AND (P^ <> #32) DO BEGIN
    Result := (ORD (P^) - ORD ('0')) OR (Result SHL 3);
    INC (P);
    END;
END;


FUNCTION Records (Bytes : INT64) : INT64;
BEGIN
  Result := Bytes DIV RECORDSIZE;
  IF Bytes MOD RECORDSIZE > 0 THEN
    INC (Result);
END;


(*
===============================================================================================
TTarArchive
===============================================================================================
*)

CONSTRUCTOR TTarArchive.Create (Stream : TStream);
BEGIN
  INHERITED Create;
  FStream     := Stream;
  FOwnsStream := FALSE;
  Reset;
END;


CONSTRUCTOR TTarArchive.Create (Filename : STRING; FileMode : WORD);
BEGIN
  INHERITED Create;
  FStream     := TFileStream.Create (Filename, FileMode);
  FOwnsStream := TRUE;
  Reset;
END;


DESTRUCTOR TTarArchive.Destroy;
BEGIN
  IF FOwnsStream THEN
    FStream.Free;
  INHERITED Destroy;
END;


PROCEDURE TTarArchive.Reset;
          // Reset File Pointer
BEGIN
  FStream.Position := 0;
  FBytesToGo       := 0;
END;


FUNCTION  TTarArchive.FindNext (VAR DirRec : TTarDirRec) : BOOLEAN;
          // Reads next Directory Info Record
          // The Stream pointer must point to the first byte of the tar header
VAR
  Rec          : ARRAY [0..RECORDSIZE-1] OF CHAR;
  CurFilePos   : INTEGER;
  Header       : TTarHeader ABSOLUTE Rec;
  I            : INTEGER;
  HeaderChkSum : WORD;
  Checksum     : CARDINAL;
BEGIN
  // --- Scan until next pointer
  IF FBytesToGo > 0 THEN
    FStream.Seek (Records (FBytesToGo) * RECORDSIZE, soFromCurrent);

  // --- EOF reached?
  Result := FALSE;
  CurFilePos := FStream.Position;
  IF (CurFilePos + RECORDSIZE > FStream.Size) THEN EXIT;
  FStream.ReadBuffer (Rec, RECORDSIZE);
  IF Rec [0] = #0 THEN EXIT;
  Result := TRUE;

  FillChar (DirRec, SizeOf (DirRec), 0);

  DirRec.FilePos := CurFilePos;
  DirRec.Name := ExtractText (Header.Name);
  DirRec.Size := ExtractNumber (@Header.Size, 12);
  DirRec.DateTime := EncodeDate (1970, 1, 1) + (ExtractNumber (@Header.MTime, 12) / 86400.0);
  I := ExtractNumber (@Header.Mode);
  // DirRec.Permissions := [];
  // DirRec.Mode        := [];
  IF I AND $0100 <> 0 THEN Include (DirRec.Permissions, tpReadByOwner);
  IF I AND $0080 <> 0 THEN Include (DirRec.Permissions, tpWriteByOwner);
  IF I AND $0040 <> 0 THEN Include (DirRec.Permissions, tpExecuteByOwner);
  IF I AND $0020 <> 0 THEN Include (DirRec.Permissions, tpReadByGroup);
  IF I AND $0010 <> 0 THEN Include (DirRec.Permissions, tpWriteByGroup);
  IF I AND $0008 <> 0 THEN Include (DirRec.Permissions, tpExecuteByGroup);
  IF I AND $0004 <> 0 THEN Include (DirRec.Permissions, tpReadByOther);
  IF I AND $0002 <> 0 THEN Include (DirRec.Permissions, tpWriteByOther);
  IF I AND $0001 <> 0 THEN Include (DirRec.Permissions, tpExecuteByOther);
  IF I AND $0200 <> 0 THEN Include (DirRec.Mode, tmSaveText);
  IF I AND $0400 <> 0 THEN Include (DirRec.Mode, tmSetGid);
  IF I AND $0800 <> 0 THEN Include (DirRec.Mode, tmSetUid);
  CASE Header.LinkFlag OF
    #0, '0' : DirRec.FileType := ftNormal;
    '1'     : DirRec.FileType := ftLink;
    '2'     : DirRec.FileType := ftSymbolicLink;
    '3'     : DirRec.FileType := ftCharacter;
    '4'     : DirRec.FileType := ftBlock;
    '5'     : DirRec.FileType := ftDirectory;
    '6'     : DirRec.FileType := ftFifo;
    '7'     : DirRec.FileType := ftContiguous;
    'D'     : DirRec.FileType := ftDumpDir;
    'M'     : DirRec.FileType := ftMultiVolume;
    'V'     : DirRec.FileType := ftVolumeHeader;
    END;
  DirRec.LinkName   := ExtractText (Header.LinkName);
  DirRec.UID        := ExtractNumber (@Header.UID);
  DirRec.GID        := ExtractNumber (@Header.GID);
  DirRec.UserName   := ExtractText (Header.UName);
  DirRec.GroupName  := ExtractText (Header.GName);
  DirRec.Magic      := Trim (ExtractText (Header.Magic));
  DirRec.MajorDevNo := ExtractNumber (@Header.DevMajor);
  DirRec.MinorDevNo := ExtractNumber (@Header.DevMinor);

  HeaderChkSum := ExtractNumber (@Header.ChkSum);   // Calc Checksum
  CheckSum := 0;
  StrMove (Header.ChkSum, CHKBLANKS, 8);
  FOR I := 0 TO SizeOf (TTarHeader)-1 DO
    INC (CheckSum, INTEGER (ORD (Rec [I])));
  DirRec.CheckSumOK := WORD (CheckSum) = WORD (HeaderChkSum);

  if (DirRec.FileType = ftLink) OR (DirRec.FileType = ftSymbolicLink)
  then FBytesToGo := 0
  else FBytesToGo := DirRec.Size;
END;


PROCEDURE TTarArchive.ReadFile (Buffer : POINTER);
          // Reads file data for the last Directory Record. The entire file is read into the buffer.
          // The buffer must be large enough to take up the whole file.
VAR
  RestBytes : INTEGER;
BEGIN
  IF FBytesToGo = 0 THEN EXIT;
  RestBytes := Records (FBytesToGo) * RECORDSIZE - FBytesToGo;
  FStream.ReadBuffer (Buffer, FBytesToGo);
  FStream.Seek (RestBytes, soFromCurrent);
  FBytesToGo := 0;
END;


PROCEDURE TTarArchive.ReadFile (Stream : TStream);
          // Reads file data for the last Directory Record.
          // The entire file is written out to the stream.
          // The stream is left at its current position prior to writing
VAR
  RestBytes : INTEGER;
BEGIN
  IF FBytesToGo = 0 THEN EXIT;
  RestBytes := Records (FBytesToGo) * RECORDSIZE - FBytesToGo;
  Stream.CopyFrom (FStream, FBytesToGo);
  FStream.Seek (RestBytes, soFromCurrent);
  FBytesToGo := 0;
END;


PROCEDURE TTarArchive.ReadFile (Filename : STRING);
          // Reads file data for the last Directory Record.
          // The entire file is saved in the given Filename
VAR
  FS : TFileStream;
BEGIN
  FS := TFileStream.Create (Filename, fmCreate);
  TRY
    ReadFile (FS);
  FINALLY
    FS.Free;
    END;
END;


FUNCTION  TTarArchive.ReadFile : STRING;
          // Reads file data for the last Directory Record. The entire file is returned
          // as a large ANSI string.
VAR
  RestBytes : INTEGER;
BEGIN
  IF FBytesToGo = 0 THEN EXIT;
  RestBytes := Records (FBytesToGo) * RECORDSIZE - FBytesToGo;
  SetLength (Result, FBytesToGo);
  FStream.ReadBuffer (PChar (Result)^, FBytesToGo);
  FStream.Seek (RestBytes, soFromCurrent);
  FBytesToGo := 0;
END;


PROCEDURE TTarArchive.GetFilePos (VAR Current, Size : INT64);
          // Returns the Current Position in the TAR stream
BEGIN
  Current := FStream.Position;
  Size    := FStream.Size;
END;


PROCEDURE TTarArchive.SetFilePos (NewPos : INT64);                   // Set new Current File Position
BEGIN
  IF NewPos < FStream.Size THEN
    FStream.Seek (NewPos, soFromBeginning);
END;


END.

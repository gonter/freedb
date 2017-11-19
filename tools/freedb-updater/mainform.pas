(**
freedb Windows Database Updater
$Id: mainform.pas,v 1.8 2003/10/31 21:52:47 joerg78 Exp $
Copyright (C) 2001-2003  Florian Maul, Marco Hellmann
Optimization by Fidel 2002

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*)

unit mainform;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, ShlObj, bzip2, libTAR, ComCtrls, ExtCtrls, ShellAPI, ShellCtrls,
  Menus, StrUtils;

type

  TFileInfo = record
    name : String;
    path : String;
    pos  : INT64;
    size : INT64;
  end;
  PFileInfo = ^TFileInfo;

  TBlock = record
    discid : String[8];
    lines  : TStringList;
  end;
  PBlock = ^TBlock;

  TForm1 = class(TForm)
    BUpdate: TButton;
    OpenDialog1: TOpenDialog;
    BDatabase: TButton;
    EUpdate: TEdit;
    dbpath: TEdit;
    LDatabase: TLabel;
    Label1: TLabel;
    BQuit: TButton;
    BStart: TButton;
    log: TMemo;
    Progress: TProgressBar;
    Image1: TImage;
    LabelProgress: TLabel;
    LabelEntries: TLabel;
    Label2File: TLabel;
    Percent: TLabel;

    procedure BUpdateClick(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure BQuitClick(Sender: TObject);
    procedure BStartClick(Sender: TObject);
    procedure Label2Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);

  private
    FileList : TList;
    updates : array [0 .. 255] of array of integer;
    dbfiles : array [0 .. 255] of string;
    TA : TTarArchive;
    tarfile : TFileStream;
    c_db, c_new, c_dup : integer;

    procedure updategenre(genre : String);
    procedure read_update_file(pfile: PFileInfo);
    procedure create_a_new_block(pfile: PFileInfo);
    procedure updated_and_write;
    procedure freeall;
    procedure bz2_file_unpack;
    procedure update_label(file_u:string);
    { Private declarations }
  public
    procedure setitemstate(state: boolean);

    { Public declarations }
  end;

var
  Form1: TForm1;

    function is_header(s : String) : boolean;
    procedure init_storage_structures;
    procedure split_each_dbfile;

// -------------------------------------------------------------------- //

implementation

{$R *.DFM}
{$R windowsxp.res}

procedure TForm1.BUpdateClick(Sender: TObject);
begin
     OpenDialog1.InitialDir:= GetCurrentDir;
  if OpenDialog1.execute then
    EUpdate.Text := OpenDialog1.FileName;

end;

// -------------------------------------------------------------------- //

procedure TForm1.Button2Click(Sender: TObject);
var
  TitleName : string;
  lpItemID : PItemIDList;
  BrowseInfo : TBrowseInfo;
  DisplayName : array[0..MAX_PATH] of char;
  TempPath : array[0..MAX_PATH] of char;
begin
  FillChar(BrowseInfo, sizeof(TBrowseInfo), #0);
  BrowseInfo.hwndOwner := Form1.Handle;
  BrowseInfo.pszDisplayName := @DisplayName;
  TitleName := 'Please specify a directory';
  BrowseInfo.lpszTitle := PChar(TitleName);
  BrowseInfo.ulFlags := BIF_RETURNONLYFSDIRS;
  lpItemID := SHBrowseForFolder(BrowseInfo);
  if lpItemId <> nil then begin
    SHGetPathFromIDList(lpItemID, TempPath);
    dbpath.Text := TempPath;
    GlobalFreePtr(lpItemID);
  end;
end;

// -------------------------------------------------------------------- //

procedure TForm1.BQuitClick(Sender: TObject);
begin
  Form1.close;
end;

// -------------------------------------------------------------------- //

function CompareDirRec(Item1, Item2: Pointer): Integer;
var
  pd1, pd2 : PFileInfo;
  si: Shortint;
begin
  pd1 := Item1;
  pd2 := Item2;
  si:=0;
  case CompareText(pd1.path+pd1.name,pd2.path+pd2.name) of
  1..2147483647: si := 1;
  0: si := 0;
  -2147483647..-1: si := -1;
  end;
Result:=si;
end;

// -------------------------------------------------------------------- //

// sort-compare-function which compares two database items
function CompareBlock(Item1, Item2: Pointer): Integer;
var
  pb1, pb2 : PBlock;
  si: Shortint;
begin
  pb1 := Item1;
  pb2 := Item2;
  si:=0;
  case CompareText(pb1.discid,pb2.discid) of
  1..2147483647: si := 1;
  0: si := 0;
  -2147483647..-1: si := -1;
  end;
Result:=si;
end;

// -------------------------------------------------------------------- //

var
    dbentry: TStringList;
    blocks : TList;
    line  : integer;
    pbl : PBlock;
    pfile : PFileInfo;
    tmpbuf : TStringStream;
    genre : String;

function is_header(s : String) : boolean;
  begin
    Result := copy(s, 1, 10) = '#FILENAME=';
end;

    // init storage structures
procedure init_storage_structures;
 begin
      blocks := TList.Create;
      dbentry := TStringList.Create;
 end;

 // split each db-file into blocks for each discid
procedure split_each_dbfile;
begin
        line := 0;
        while (line < dbentry.count) do begin
          new(pbl);
          pbl.discid := copy(dbentry[line], 11, 8);
          pbl.lines := TStringList.Create;
          blocks.Add(pbl);
          repeat
            pbl.lines.Add(dbentry[line]);
            inc(line);
          until (line >= dbentry.count) or is_header(dbentry[line]);
        end;
        dbentry.Free;
end;

// update information label
procedure TForm1.update_label(file_u:string);
begin
Percent.Caption:=FloatToStr(Int(((Progress.Position+1)/Progress.Max)*100))+' %';
Application.Title:=Percent.Caption+' '+Genre+' - '+ExtractFileName(file_u);
Label2File.Caption:=file_u;
LabelEntries.Caption:='Actual: '+FormatFloat('# ###',(c_db+c_new-c_dup));
LabelProgress.Caption:='Previous : '+FormatFloat('# ###',(c_db))+' New: '+FormatFloat('# ###',(c_new))+' Update: '+FormatFloat('# ###',(c_dup));
Application.ProcessMessages();
end;

// read update file from tar archive to tmpbuf
procedure TForm1.read_update_file(pfile: PFileInfo);
begin
          tarfile.Seek(pfile.pos, soFromBeginning);
          tmpbuf.CopyFrom(tarfile, pfile.size);
          tmpbuf.Seek(0, soFromBeginning);
end;

// create a new block entry from the update file
procedure TForm1.create_a_new_block(pfile : PFileInfo);
begin
          new(pbl);
          pbl.discid := pfile.name;
          pbl.lines := TStringList.Create;
          pbl.lines.LoadFromStream(tmpbuf);
          pbl.lines.Insert(0, '#FILENAME='+pfile.name);
end;

// a procedure which processes one genre
procedure TForm1.updategenre(genre : String);
var i,u,x, dupl : integer;
    outfile : TFileStream;
    MemoryFile : TMemoryStream;
    buf : String;
    pfile : PFileInfo;
begin
  log.lines.add('processing ' + genre);
  Progress.Max := 255;

  try
    // process all entries in updates[]
    for i := 0 to 255 do begin
      Progress.Position := i;
      Application.ProcessMessages();

      // has the file i to be updated
      if updates[i,0] > 0 then begin

      // init storage structures
        init_storage_structures; //now separate procedure

        // read the database file dbfiles[i]
        dbentry.LoadFromFile(dbfiles[i]);

       // split each db-file into blocks for each discid
        split_each_dbfile; //now separate procedure

        // blocks now contains all entries of 'dbfiles[i]'
        // as a list of records with (discid, lines)

        // sort the blocks by discid
        blocks.Sort(CompareBlock);

        // count db-entries and updates for the statistcs
        inc(c_db, blocks.count);
        inc(c_new, updates[i,0]);

        // process each update
        for u := 1 to updates[i,0] do begin
          // init tmpbuf and update-info
          tmpbuf := TStringStream.Create('');
          pfile := filelist[updates[i,u]];

          // read update file from tar archive to tmpbuf
          read_update_file(pfile); //now separate procedure

          // create a new block entry from the update file
          create_a_new_block(pfile); //now separate procedure

          // search for the discid in case we have a replacing update
          dupl := -1;
          x := 0;
          while (x < blocks.Count) AND (dupl < 0) do begin
            if PBlock(blocks[x]).discid = pbl.discid
            then dupl := x;
            inc(x);
          end;

          // a dulicate was found
          if dupl >= 0 then begin
            // delete the old/outdated database entry
            inc(c_dup);
            PBlock(blocks[dupl]).lines.Free;
            Dispose(PBlock(blocks[dupl]));
            blocks.Delete(dupl);
          end;

          // in any case append the new/updated block
          blocks.Add(pbl);

          // free our temporary buffer
          tmpbuf.Free();
        end; // for each update

        // sort the blocks again
        blocks.Sort(CompareBlock);

//      log.lines.add(dbfiles[i]+'.tmp -> c_db:'+IntToStr(c_db)+'  c_new:'+IntToStr(c_new)+'  c_dup:'+IntToStr(c_dup));
        update_label(dbfiles[i]);

        // write all blocks to a discid.tmp file
        outfile := nil;
        MemoryFile:= nil;
        try
          outfile := TFileStream.Create(dbfiles[i]+'.tmp', fmCreate);
          MemoryFile:= TMemoryStream.Create;
          // save all lines of all blocks with unix linebreak
          for u := 0 to blocks.Count-1 do
            for x := 0 to PBlock(blocks[u]).lines.count-1 do begin
              // write lines ending with unix-linebreak 0Ah
              buf := PBlock(blocks[u]).lines.Strings[x] + #10; {chr(10)}
              MemoryFile.Write(buf[1], length(buf));
            end;
          MemoryFile.Position:=0;
          outfile.CopyFrom(MemoryFile,MemoryFile.Size);
          FreeAndNil(MemoryFile);
          FreeAndNil(outfile);
        except
          on EFCreateError do
            log.lines.add('Error: '+dbfiles[i]+'.tmp could not be opened for write.');
          else begin
            log.lines.add('Error: while writing to '+dbfiles[i]+'.tmp.');
            if outfile<>nil then FreeAndNil(outfile);
          end;
        end;

        // delete all blocks from memory
        for u := 0 to blocks.Count-1 do begin
          PBlock(blocks[u]).lines.Free;
          Dispose(PBlock(blocks[u]));
        end;
        blocks.Free;

        // finally replace the original db-file with the new one
        if dbfiles[i]<>'' then begin
          if DeleteFile(dbfiles[i]) then begin
              if NOT RenameFile(dbfiles[i]+'.tmp', dbfiles[i])
              then log.lines.add('Warning: '+dbfiles[i]+'.tmp could not be renamed.')
          end
          else log.lines.add('Warning: '+dbfiles[i]+' could not be deleted.');
        end;
    end; // for all entries in updates[]
  end; // try
  except
    else begin
      MessageBeep(MB_ICONASTERISK);
      ShowMessage('Something went wrong. Update aborted.');
      exit;
    end;
  end;
end;

// -------------------------------------------------------------------- //

// for each update entry determine the database file
// which has to be updated and write it to updates[]
var fileid : integer;
    tsr : TSearchRec;
    tempfile  : String;
    TempDir   : array[0..MAX_PATH] of Char;
    outfile : TFileStream;
    bz2 : Tbzip2;
    tarfilename, filename : String;
    infile : TFileStream;

// hides and shows all controls of the form
procedure TForm1.setitemstate(state: boolean);
  begin
    dbpath.enabled := state;
    BDatabase.enabled := state;
    BUpdate.enabled := state;
    EUpdate.enabled := state;
    BStart.enabled := state;
    BQuit.enabled := state;

    if state then begin
      EnableMenuItem(GetSystemMenu( Form1.Handle, LongBool(False)),
                   SC_CLOSE, MF_BYCOMMAND);
    end
    else begin
      EnableMenuItem(GetSystemMenu( Form1.Handle, LongBool(False)),
                   SC_CLOSE, MF_BYCOMMAND or MF_GRAYED);
    end;
  end;

// this proc frees all objects, memory and tempfiles
procedure TForm1.freeall;
  var i : integer;
  begin
    // free tar filelist
    for i := 0 to (FileList.Count - 1) do begin
      pfile := FileList.Items[i];
      Dispose(pfile);
    end;
    FileList.Free;

    // free all tar-stuff
    TA.Free;
    tarfile.Free;

    // delete the temp-file if necessary
    if tempfile <> '' then begin
      if DeleteFile(tempfile)
      then log.lines.add('tempfile '+tempfile+' deleted.')
      else log.lines.add('Warning: tempfile '+tempfile+' could not be deleted.');
    end;

    setitemstate(true);
  end;

procedure TForm1.updated_and_write;
var i,x: Integer;
begin
    genre := '';
    for i := 0 to (FileList.Count - 1) do begin
      pfile := FileList.Items[i];
      Application.ProcessMessages();

      // if it IS a database file / not README or . or genre/
      if (pfile.name <> '') AND (pfile.path <> '') then begin

        // new genre detected
        if genre <> pfile.path then begin

          // process all files for genre
          if genre <> '' then begin
            updategenre(genre);
          end;

          // init/clear the updates-array and dbfiles
          for x := 0 to 255 do begin
           dbfiles[x] := '';
           setlength(updates[x], 1);
           updates[x,0] := 0;
          end;

          // set the new genre
          genre := pfile.path;
        end;

        // corresponding db-file begins with first 2 discid-chars
        fileid := StrToInt('$'+copy(pfile.name,1,2));

        // find the databasefile
        while FindFirst(dbpath.text+'\'+pfile.path+'\'+IntToHex(fileid,2) +'to*', faAnyFile, tsr) <> 0 do begin
        FindClose(tsr);
          dec(fileid);
          if (fileid < 0) then begin
            MessageBeep(MB_ICONASTERISK);
            ShowMessage('No valid win-db-file found for '+pfile.name+'. Check the db-path.');
            exit;
          end;
        end;
        // remember the filename
        dbfiles[fileid] := dbpath.text+'\'+pfile.path+'\'+tsr.Name;
        FindClose(tsr);

        // and remember the update-file-discid
        inc(updates[fileid,0]);
        setlength(updates[fileid], updates[fileid,0]+1);
        updates[fileid, updates[fileid,0]] := i;
      end; // if name == '' or path = ''
   end; // for all tar file entries

   // update last genre
   if genre <> '' then begin
      updategenre(genre);
   end;
end;
  // in case the user selected a bz2-file unpack it to tempfile
procedure TForm1.bz2_file_unpack;
begin
  if ExtractFileExt(EUpdate.Text)='.bz2' then begin
    try
      GetTempPath(MAX_PATH, @TempDir);
      tempfile := TempDir+ExtractFilename(ChangeFileExt(EUpdate.Text,''));
      log.lines.add('extracting bzip-file to ' + tempfile);
      outfile := TFileStream.Create(tempfile, fmCreate);
      infile := TFileStream.Create(EUpdate.Text, fmOpenRead);
      bz2 := TBZip2.Create(Form1);
      bz2.DecompressStream(infile, outfile);
      bz2.Free;
      tarfilename := tempfile;
      FreeAndNil(outfile);
      FreeAndNil(infile);
    except
      else begin
        if outfile <> nil then FreeAndNil(outfile);
        if infile <> nil then FreeAndNil(infile);
        MessageBeep(MB_ICONASTERISK	);
        ShowMessage('Error unpacking the bzip2-Archive. You need to unpack it manually.');
        setitemstate(true);
        exit;
      end;
    end;
  end
  else tarfilename := EUpdate.Text;
end;
//************************************************************************

procedure TForm1.BStartClick(Sender: TObject);

var
    DirRec : TTarDirRec;
    pfile, pf2: PFileInfo;
    i: integer;
    size, posi : INT64;

  // ------------------------------------------------------------------ //

  // determines if a directory exists
  function DirExists(dir: string): Boolean;
  var cv: Integer;
  begin
    cv:=FileGetAttr(dir);
    result:=((cv<>-1) and ((cv and faDirectory)<>0));
  end;

  // ------------------------------------------------------------------ //

{  // hides and shows all controls of the form
  procedure setitemstate(state: boolean);
}
  // ------------------------------------------------------------------ //

{  // this proc frees all objects, memory and tempfiles
  procedure freeall;
}
  // ------------------------------------------------------------------ //

begin
   setitemstate(false);

  // check if db-path exists
  if not DirExists(dbpath.text) then begin
    MessageBeep(MB_ICONASTERISK);
    ShowMessage('The database path '''+dbpath.text+''' does not exist.');
    setitemstate(true);
    exit;
  end;

  // init a bunch of vars
  outfile := nil;
  infile := nil;
  tempfile := '';
  c_db := 0; c_dup := 0; c_new := 0;
  while log.lines.count > 0 do log.Lines.Delete(0);
  Progress.Position := 0;
  Update;

  // in case the user selected a bz2-file unpack it to tempfile
  bz2_file_unpack;   //now separate procedure

  log.lines.add('reading tar file '''+tarfilename+'''...');

  // open the (unpacked) tar file
  try
    tarfile := TFileStream.Create(tarfilename, fmOpenRead);
  except
    else begin
      MessageBeep(MB_ICONASTERISK);
      ShowMessage('The update-file could not be read. Did you select one?');
      setitemstate(true);
      exit;
    end;
  end;

  // process the tarfile
  try
    TA := TTarArchive.Create(tarfile);
    TA.Reset;
    FileList := TList.Create;
    Progress.Max := tarfile.size;

    // process each file in the tar
    WHILE TA.FindNext (DirRec) DO BEGIN
      Application.ProcessMessages();
      // normal files are considered to be freedb database files
      if DirRec.FileType = ftNormal then begin
          TA.GetFilePos(posi, size);
          new(pfile);
          filename := DirRec.Name;
          if (pos('./', filename)=1) then filename := copy(filename, 3, length(filename));
          pfile.name := copy(filename, pos('/', filename)+1, length(filename));
          pfile.path := copy(filename, 1, pos('/', filename)-1);
          pfile.pos  := posi;
          pfile.size := DirRec.Size;
          FileList.Add(pfile);
          Progress.Position := posi;
          update_label(tarfilename);
      end
      // searching for the corresponding file of each link
      else if DirRec.FileType = ftLink then begin
        for i := 0 to FileList.Count-1 do begin
          pf2 := PFileInfo(FileList[i]);
          if DirRec.LinkName = pf2.path+'/'+pf2.name then begin
            new(pfile);
            filename := DirRec.Name;
            if (pos('./', filename)=1) then filename := copy(filename, 3, length(filename));
            pfile.name := copy(filename, pos('/', filename)+1, length(filename));
            pfile.path := copy(filename, 1, pos('/', filename)-1);
            pfile.pos  := pf2.pos;
            pfile.size := pf2.size;
            FileList.Add(pfile);
          end;
        end;
      end; // else

    END; // while
  except
    else begin
      freeall;
      MessageBeep(MB_ICONASTERISK);
      ShowMessage('Error reading TAR-file.');
      exit;
    end;
  end;

  log.lines.add('finished reading, found '+IntToStr(FileList.count)+' entries.');

  try
    // sort tar filelist by genre and filename
    FileList.Sort(CompareDirRec);

    // for each update entry determine the database file
    // which has to be updated and write it to updates[]
    updated_and_write;  //now separate procedure

    // free objects, memory and temp-file
    freeall;

    // print status report
    log.lines.Add('done. The database has been updated.');
    log.lines.Add('The freedb database contained '+IntToStr(c_db)+' entries. During this update ');
    log.lines.Add(IntToStr(c_dup)+' entries were replaced and '+IntToStr(c_new-c_dup)+' new entries were added. This');
    log.lines.Add('makes a total of '+IntToStr(c_db+c_new-c_dup)+' entries in the freedb database now.');

  except
    else begin
      freeall;
      MessageBeep(MB_ICONASTERISK);
      ShowMessage('Error processing the update-TAR-file.');
    end;
  end;
  MessageBeep(MB_ICONASTERISK);
  Progress.Position := 0;
  update_label('');
end;

// -------------------------------------------------------------------- //

procedure TForm1.Label2Click(Sender: TObject);
begin
  ShellExecute( Application.Handle, 'open', 'http://www.freedb.org/', nil, nil, SW_NORMAL );
end;

// -------------------------------------------------------------------- //

procedure TForm1.FormCreate(Sender: TObject);
begin
  // setting the hints here 'by hand' to insert line-breaks
  dbpath.Hint := 'This is the root path of your windows-format freedb database.'+ chr(13)+
      'It should contain all 11 genres as subdirectories.';
  EUpdate.Hint := 'Enter the filename of the freedb database update'+chr(13)+'archive you want to use.';
  LabelEntries.Hint := 'written entries';
  LabelProgress.Hint := 'old entries read / added entries / replaced entries';
end;

// -------------------------------------------------------------------- //

end.

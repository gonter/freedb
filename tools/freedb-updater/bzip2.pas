unit bzip2;

{
 Component for compression with bzip2 algorithm.
 Use libbz2.dll
}


interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs;

{$ALIGN OFF}
const
 BZ_RUN              = 0;
 BZ_FLUSH            = 1;
 BZ_FINISH           = 2;

 BZ_OK               = 0;
 BZ_RUN_OK           = 1;
 BZ_FLUSH_OK         = 2;
 BZ_FINISH_OK        = 3;
 BZ_STREAM_END       = 4;
 BZ_SEQUENCE_ERROR   = (-1);
 BZ_PARAM_ERROR      = (-2);
 BZ_MEM_ERROR        = (-3);
 BZ_DATA_ERROR       = (-4);
 BZ_DATA_ERROR_MAGIC = (-5);
 BZ_IO_ERROR         = (-6);
 BZ_UNEXPECTED_EOF   = (-7);
 BZ_OUTBUFF_FULL     = (-8);


type
   bz_stream=record
      next_in:pchar;
      avail_in:longword;
      total_in:longword;

      next_out:pchar;
      avail_out:longword;
      total_out:longword;

      state:pointer;

      bzalloc:pointer;
      bzfree:pointer;
      opaque:pointer;
   end;

TbzCompressInit=function (var strm:bz_stream;
                          blockSize100k:integer;
                          verbosity:integer;
                          workFactor:integer):integer;stdcall;
TbzCompress=function (var strm:bz_stream;
                      action:integer):integer;stdcall;
TbzCompressEnd=function (var strm:bz_stream):integer;stdcall;

TbzDecompressInit=function (var strm:bz_stream;
                          verbosity:integer;
                          small:integer):integer;stdcall;
TbzDecompress=function (var strm:bz_stream):integer;stdcall;
TbzDecompressEnd=function (var strm:bz_stream):integer;stdcall;

  Tbzip2 = class(TComponent)
  private
   hDll:THandle;
   stre:bz_stream;
   FBlockSize:integer;
   FBufferSize: integer;

   bzCompressInit:TbzCompressInit;
   bzCompress:TbzCompress;
   bzCompressEnd:TbzCompressEnd;
   bzDecompressInit:TbzDecompressInit;
   bzDecompress:TbzDecompress;
   bzDecompressEnd:TbzDecompressEnd;

   procedure SetBlockSize(Value:integer);
   procedure SetBufferSize(Value:integer);
  protected
   function CompressInit:integer;
   function Compress(Action:integer):integer;
   function CompressEnd:integer;
   function DecompressInit:integer;
   function Decompress:integer;
   function DecompressEnd:integer;
   function TestError(err:integer):integer;
  public
   constructor Create(AOwner:TComponent);override;
   destructor  Destroy;override;

   procedure CompressStream(SIn,SOut:TStream);
   procedure DecompressStream(SIn,SOut:TStream);
  published
   property BlockSize:integer read FBlockSize write SetBlockSize; // in 100k units
   property BufferSize:integer read FBufferSize write SetBufferSize; // in 1k units
  end;

procedure Register;

implementation

procedure Register;
begin
 RegisterComponents('Design', [Tbzip2]);
end;

{ Tbzip2 }

function Tbzip2.Compress(Action:integer):integer;
begin
 Result:=TestError(bzCompress(stre,Action));
end;

function Tbzip2.CompressEnd:integer;
begin
 Result:=TestError(bzCompressEnd(stre));
end;

function Tbzip2.CompressInit:integer;
begin
 Result:=TestError(bzCompressInit(stre,BlockSize,0,0));
end;

procedure Tbzip2.CompressStream(SIn, SOut: TStream);
var bin,bout:pointer;
    bs,rs:integer;
begin
 bs:=BufferSize*1024;
 bin:=AllocMem(bs);
 bout:=AllocMem(bs);
 SIn.Seek(0,soFromBeginning);
 try
  stre.state:=nil;
  stre.next_in:=nil;
  stre.avail_in:=0;
  stre.total_in:=0;
  stre.next_out:=nil;
  stre.avail_out:=0;
  stre.total_out:=0;
  CompressInit;


  while SIn.Position<SIn.Size do begin
   rs:=SIn.Read(bin^,bs);
   stre.next_in:=bin;
   stre.avail_in:=rs;
   while stre.avail_in>0 do begin
    stre.next_out:=bout;
    stre.avail_out:=bs;
    stre.total_out:=0;
    Compress(BZ_RUN);
    SOut.Write(bout^,stre.total_out);
   end;
  end;
  stre.next_out:=bout;
  stre.avail_out:=bs;
  stre.total_out:=0;
  Compress(BZ_FINISH);
  SOut.Write(bout^,stre.total_out);
 finally
  CompressEnd;
  FreeMem(bin);
  FreeMem(bout);
 end;
end;

constructor Tbzip2.Create(AOwner: TComponent);

begin
 inherited Create(AOwner);
 FBlockSize:=1;
 FBufferSize:=32;
 hDll:=LoadLibrary('libbz2.dll');
 if hDll=0 then raise Exception.Create('Error load LIBBZ2.dll !!!');
 @bzCompressInit:=GetProcAddress(hDll,'bzCompressInit');
 @bzCompress:=GetProcAddress(hDll,'bzCompress');
 @bzCompressEnd:=GetProcAddress(hDll,'bzCompressEnd');
 @bzDecompressInit:=GetProcAddress(hDll,'bzDecompressInit');
 @bzDecompress:=GetProcAddress(hDll,'bzDecompress');
 @bzDecompressEnd:=GetProcAddress(hDll,'bzDecompressEnd');

 stre.bzalloc:=nil;
 stre.bzfree:=nil;
 stre.opaque:=nil;
end;

function Tbzip2.Decompress:integer;
begin
 Result:=TestError(bzDecompress(stre));
end;

function Tbzip2.DecompressEnd:integer;
begin
 Result:=TestError(bzDecompressEnd(stre));
end;

function Tbzip2.DecompressInit:integer;
begin
 Result:=TestError(bzDecompressInit(stre,0,0));
end;

procedure Tbzip2.DecompressStream(SIn, SOut: TStream);
var bin,bout:pointer;
    bs,rs:integer;
begin
 bs:=BufferSize*1024;
 bin:=AllocMem(bs);
 bout:=AllocMem(bs);
 SIn.Seek(0,soFromBeginning);
 try
  stre.state:=nil;
  stre.next_in:=nil;
  stre.avail_in:=0;
  stre.total_in:=0;
  stre.next_out:=nil;
  stre.avail_out:=0;
  stre.total_out:=0;
  DecompressInit;


  while SIn.Position<SIn.Size do begin
   rs:=SIn.Read(bin^,bs);
   stre.next_in:=bin;
   stre.avail_in:=rs;
   while stre.avail_in>0 do begin
    stre.next_out:=bout;
    stre.avail_out:=bs;
    stre.total_out:=0;
    Decompress;
    SOut.Write(bout^,stre.total_out);
   end;
  end;
 finally
  DecompressEnd;
  FreeMem(bin);
  FreeMem(bout);
 end;
end;

destructor Tbzip2.Destroy;
begin
 FreeLibrary(hDll);
 inherited Destroy;
end;

procedure Tbzip2.SetBlockSize(Value: integer);
begin
 if (Value<1) or (Value>9) then exit;
 FBlockSize:=Value;
end;

procedure Tbzip2.SetBufferSize(Value: integer);
begin
 if (Value<1) or (Value>4096) then exit;
 FBufferSize:=Value;
end;

function Tbzip2.TestError(err: integer):integer;
begin
 case err of
  BZ_OK: Result:=err;
  BZ_RUN_OK: Result:=err;
  BZ_FLUSH_OK: Result:=err;
  BZ_FINISH_OK: Result:=err;
  BZ_STREAM_END: Result:=err;
  BZ_SEQUENCE_ERROR:raise Exception.Create('BZ_SEQUENCE_ERROR');
  BZ_PARAM_ERROR:raise Exception.Create('BZ_PARAM_ERROR');
  BZ_MEM_ERROR:raise Exception.Create('BZ_MEM_ERROR');
  BZ_DATA_ERROR:raise Exception.Create('BZ_DATA_ERROR');
  BZ_DATA_ERROR_MAGIC:raise Exception.Create('BZ_DATA_ERROR_MAGIC');
  BZ_IO_ERROR:raise Exception.Create('BZ_IO_ERROR');
  BZ_UNEXPECTED_EOF:raise Exception.Create('BZ_UNEXPECTED_EOF');
  BZ_OUTBUFF_FULL:raise Exception.Create('BZ_OUTBUFF_FULL');
 else
  raise Exception.Create('BZ_UNKNOWN_ERROR');
 end;
end;

end.


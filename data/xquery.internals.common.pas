unit xquery.internals.common;

{
Copyright (C) 2008 - 2019 Benito van der Zander (BeniBela)
                          benito@benibela.de
                          www.benibela.de

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

}

{$I ../internettoolsconfig.inc}

interface

uses
  classes, contnrs, SysUtils, bbutils;

type
  TXQDefaultTypeInfo = record
    class function hash(data: pchar; datalen: SizeUInt): uint32; static;
    class procedure keyToData(const key: string; out data: pchar; out datalen: SizeUInt); static; inline;
    class function equalKeys(const key: string; data: pchar; datalen: SizeUInt): boolean; static; inline;
    class procedure createDeletionKey(out key: string); static;
  end;
  TXQVoid = record end;
  //Hashmap based on Bero's FLRECacheHashMap
  generic TXQBaseHashmap<TKey, TBaseValue, TInfo> = object
    type THashMapEntity=record
      Key: TKey;
      Value: TBaseValue;
    end;
    PHashMapEntity = ^THashMapEntity;
    PValue = ^TBaseValue;
  private
    //if a cell with key = Key exists, return that cell; otherwise return empty cell at expected position
    function findCell(keydata: pchar; keylen: SizeUInt): UInt32;
    function findCell(const Key: TKey): UInt32;
    procedure resize;
  protected
    DELETED_KEY: TKey;
    RealSize: int32;
    LogSize: int32;
    Size: int32;
    Entities:array of THashMapEntity;
    CellToEntityIndex: array of int32;
    function getBaseValueOrDefault(const Key:TKey):TBaseValue;
    procedure setBaseValue(const Key:TKey;const Value:TBaseValue);
    class function hash(const key: TKey): uint32; static;
    function include(const Key:TKey; const Value:TBaseValue; allowOverride: boolean=true):PHashMapEntity;
  public
    constructor init;
    destructor done;
    procedure Clear;
    function findEntity(const Key:TKey; CreateIfNotExist:boolean=false): PHashMapEntity;
    function findEntity(data: pchar; keylen: SizeUInt): PHashMapEntity;
    function exclude(const Key:TKey):boolean;
    function contains(const key: TKey): boolean;
    property values[const Key:TKey]: TBaseValue read getBaseValueOrDefault write SetBaseValue; default;
  end;

  generic TXQHashset<TKey, TInfo> = object(specialize TXQBaseHashmap<string,TXQVoid,TInfo>)
    procedure include(const Key:TKey; allowOverride: boolean=true);
  end;
  TXQHashsetStr = specialize TXQHashset<string,TXQDefaultTypeInfo>;
  PXQHashsetStr = ^TXQHashsetStr;

  TXQBaseHashmapStrPointer = specialize TXQBaseHashmap<string,pointer,TXQDefaultTypeInfo>;
  generic TXQBaseHashmapStrPointerButNotPointer<TValue> = object(TXQBaseHashmapStrPointer)
  protected
    function get(const Key: string; const def: TValue): TValue; inline;
    function getOrDefault(const Key: string): TValue; inline;
    function GetValue(const Key: string): TValue; inline;
  end;

  generic TXQHashmapStr<TValue> = object(specialize TXQBaseHashmapStrPointerButNotPointer<TValue>)
  protected
    procedure SetValue(const Key: string; const AValue: TValue); inline;
  public
    procedure include(const Key: string; const Value: TValue; allowOverride: boolean=true);
    property Values[const Key:string]: TValue read GetValue write SetValue; default;
  end;
  generic TXQHashmapStrOwning<TValue, TOwnershipTracker> = object(specialize TXQBaseHashmapStrPointerButNotPointer<TValue>)
  type PXQHashmapStrOwning = ^TXQHashmapStrOwning;
  protected
    procedure SetValue(const Key: string; const AValue: TValue); inline;
  public
    procedure clear;
    destructor done;
    class procedure disposeAndNil(var map: PXQHashmapStrOwning);
    procedure include(const Key: string; const aValue: TValue; allowOverride: boolean=true);
    //procedure Add(const Key:TXQHashKeyString; const Value:TValue); //inline;
    property Values[const Key:string]: TValue read GetValue write SetValue; default;
  end;
  TXQDefaultOwnershipTracker = record
    class procedure addRef(o: TObject); static; inline;
    class procedure release(o: TObject); static; inline;
    class procedure addRef(const str: string); static; inline;
    class procedure release(var str: string); static; inline;
  end;
  generic TXQHashmapStrOwningGenericObject<TValue> = object(specialize TXQHashmapStrOwning<TValue, TXQDefaultOwnershipTracker>)
  end;
  TXQHashmapStrOwningObject = specialize TXQHashmapStrOwningGenericObject<TObject>;
  TXQHashmapStrStr = object(specialize TXQHashmapStrOwning<string, TXQDefaultOwnershipTracker>)
  end;

//** A simple refcounted object like TInterfacedObject, but faster, because it assumes you never convert it to an interface in constructor or destructor
type TFastInterfacedObject = class(TObject, IUnknown)
protected
  frefcount : longint;
  function QueryInterface({$IFDEF FPC_HAS_CONSTREF}constref{$ELSE}const{$ENDIF} iid : tguid;out obj) : longint;{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
public
  function _AddRef : longint;{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
  function _Release : longint;{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
  procedure _AddRefIfNonNil; inline;
  procedure _ReleaseIfNonNil; inline;
  property RefCount : longint read frefcount;
end;

//**a list to store interfaces, similar to TInterfaceList, but faster, because
//**  (1) it assumes all added interfaces are non nil
//**  (2) it is not thread safe
//**  (3) it is generic, so you need no casting
generic TFastInterfaceList<IT> = class
  type PIT = ^IT;
protected
  fcount, fcapacity: integer; // count
  fbuffer: PIT; // Backend storage
  procedure raiseInvalidIndexError(i: integer);  //**< Raise an exception
  procedure checkIndex(i: integer); inline; //**< Range check
  procedure reserve(cap: integer); //**< Allocates new memory if necessary
  procedure compress; //**< Deallocates memory by shorting list if necessary
  procedure setCount(c: integer); //**< Forces a count (elements are initialized with )
  procedure setCapacity(AValue: integer);
  procedure setBufferSize(c: integer);
  procedure insert(i: integer; child: IT);
  procedure put(i: integer; const AValue: IT); inline; //**< Replace the IT at position i
public
  constructor create(capacity: integer = 0);
  destructor Destroy; override;
  procedure delete(i: integer); //**< Deletes a value (since it is an interface, the value is freed iff there are no other references to it remaining)
  procedure remove(const value: IT);
  procedure add(const value: IT);
  procedure addAll(other: TFastInterfaceList);
  function get(i: integer): IT; inline; //**< Gets an interface from the list.
  function last: IT; //**< Last interface in the list.
  function first: IT; //**< First interface in the list.
  procedure clear;
  property items[i: integer]: IT read get write put; default;
  property Count: integer read fcount write setCount;
  property Capacity: integer read fcapacity write setCapacity;
end;

TXMLDeclarationStandalone = (xdsOmit, xdsYes, xdsNo);
TXHTMLStrBuilder = object(TStrBuilder)
  procedure appendHexEntity(codepoint: integer);

  procedure appendHTMLText(inbuffer: pchar; len: SizeInt);
  procedure appendHTMLAttrib(inbuffer: pchar; len: SizeInt);
  procedure appendHTMLText(const s: string);
  procedure appendHTMLAttrib(const s: string);
  procedure appendHTMLElementAttribute(const name, value: string);

  procedure appendXMLHeader(const version, anencoding: string; standalone: TXMLDeclarationStandalone);
  procedure appendXMLElementStartOpen(const name: string);
  procedure appendXMLElementAttribute(const name, value: string);
  procedure appendXMLElementStartClose(); inline;
  procedure appendXMLElementStartTag(const name: string); //open and close
  procedure appendXMLElementEndTag(const name: string);
  procedure appendXMLProcessingInstruction(const name, content: string);
  procedure appendXMLEmptyElement(const name: string);
  procedure appendXMLText(const s: string);
  procedure appendXMLAttrib(const s: string);
  procedure appendXMLCDATAStart();
  procedure appendXMLCDATAText(p: pchar; len: sizeint);
  procedure appendXMLCDATAText(const s: string); inline;
  procedure appendXMLCDATAEnd();
end;

type TJSONXHTMLStrBuilder = object(TXHTMLStrBuilder)
  standard: boolean;
  procedure init(abuffer:pstring; basecapacity: SizeInt = 64; aencoding: TSystemCodePage = {$ifdef HAS_CPSTRING}CP_ACP{$else}CP_UTF8{$endif});

  procedure appendJSONEmptyObject; inline;
  procedure appendJSONObjectStart; inline;
  procedure appendJSONObjectKeyColon(const key: string); inline;
  procedure appendJSONObjectComma; inline;
  procedure appendJSONObjectEnd; inline;

  procedure appendJSONEmptyArray; inline;
  procedure appendJSONArrayStart; inline;
  procedure appendJSONArrayComma; inline;
  procedure appendJSONArrayEnd; inline;

  procedure appendJSONStringUnicodeEscape(codepoint: integer);
  procedure appendJSONStringWithoutQuotes(const s: string);
  procedure appendJSONString(const s: string);
end;

function xmlStrEscape(s: string; attrib: boolean = false):string;
function xmlStrWhitespaceCollapse(const s: string):string;
function htmlStrEscape(s: string; attrib: boolean = false):string;
//**Returns a "..." string for use in json (internally used)
function jsonStrEscape(s: string):string;
function strSplitOnAsciiWS(s: string): TStringArray;
function urlHexDecode(s: string): string;


function nodeNameHash(const s: RawByteString): cardinal;
function nodeNameHashCheckASCII(const s: RawByteString): cardinal;



type  TRaiseXQEvaluationExceptionCallback = procedure (const code, message: string);

var raiseXQEvaluationExceptionCallback: TRaiseXQEvaluationExceptionCallback = nil;

procedure raiseXQEvaluationException(const code, message: string); overload; noreturn;

type xqfloat = double;
function xqround(const f: xqfloat): Int64;

const
  ENT_EMPTY=-1;
  ENT_DELETED=-2;

{$ifdef FPC} //hide this from pasdoc, since it cannot parse external
  //need this in interface, otherwise calls to it are not inlined
  Procedure fpc_AnsiStr_Incr_Ref (S : Pointer); [external name 'FPC_ANSISTR_INCR_REF'];
  Procedure fpc_ansistr_decr_ref (Var S : Pointer); [external name 'FPC_ANSISTR_DECR_REF'];
{$endif}

implementation
uses math;


class procedure TXQDefaultTypeInfo.keyToData(const key: string; out data: pchar; out datalen: SizeUInt);
begin
  data := pointer(key);
  datalen := length(key);
end;

class function TXQDefaultTypeInfo.equalKeys(const key: string; data: pchar; datalen: SizeUInt): boolean;
begin
  result := (length(key)  = datalen) and CompareMem(data, pointer(key), datalen);
end;

constructor TXQBaseHashmap.init;
begin
 Tinfo.createDeletionKey(DELETED_KEY);
 RealSize:=0;
 LogSize:=0;
 Size:=0;
 Entities:=nil;
 CellToEntityIndex:=nil;
 Resize;
end;

destructor TXQBaseHashmap.done;
begin
 clear;
 inherited;
end;

procedure TXQBaseHashmap.Clear;
begin
 RealSize:=0;
 LogSize:=0;
 Size:=0;
 SetLength(Entities,0);
 SetLength(CellToEntityIndex,0);
 Resize;
end;

function TXQBaseHashmap.findCell(keydata: pchar; keylen: SizeUInt): UInt32;
var HashCode,Mask,Step:uint32;
    Entity:int32;
begin
 HashCode:=TInfo.hash(keydata, keylen);
 Mask:=(2 shl LogSize)-1;
 Step:=((HashCode shl 1)+1) and Mask;
 if LogSize<>0 then begin
  result:=HashCode shr (32-LogSize);
 end else begin
  result:=0;
 end;
 repeat
  Entity:=CellToEntityIndex[result];
  if (Entity=ENT_EMPTY) or ((Entity<>ENT_DELETED) and (tinfo.equalKeys(Entities[Entity].Key, keydata, keylen))) then begin
   exit;
  end;
  result:=(result+Step) and Mask;
 until false;
end;

function TXQBaseHashmap.findCell(const Key: TKey): UInt32;
var data: pchar;
    datalen: SizeUInt;
begin
  TInfo.keyToData(key, data, datalen);
  result := findCell(data, datalen);
end;

procedure TXQBaseHashmap.resize;
var NewLogSize,NewSize,OldSize,Counter:int32;
    OldEntities:array of THashMapEntity;
begin
 OldSize := Size;
 NewLogSize:=0;
 NewSize:=RealSize;
 while NewSize<>0 do begin
  NewSize:=NewSize shr 1;
  inc(NewLogSize);
 end;
 if NewLogSize<1 then begin
  NewLogSize:=1;
 end;
 Size:=0;
 RealSize:=0;
 LogSize:=NewLogSize;
 OldEntities:=Entities;
 Entities:=nil;
 SetLength(Entities,2 shl LogSize);
 SetLength(CellToEntityIndex,2 shl LogSize);
 for Counter:=0 to length(CellToEntityIndex)-1 do begin
  CellToEntityIndex[Counter]:=ENT_EMPTY;
 end;
 for Counter:=0 to OldSize-1 do
  if pointer(OldEntities[Counter].Key) <> pointer(DELETED_KEY) then
    include(OldEntities[Counter].Key, OldEntities[Counter].Value);
 //remove old data (not really needed)
 for Counter:=Size to min(OldSize - 1, high(Entities)) do begin
   Entities[Counter].Key:=default(TKey);
   Entities[Counter].Value:=default(TBaseValue);
 end;
end;

function TXQBaseHashmap.include(const Key: TKey; const Value: TBaseValue; allowOverride: boolean): PHashMapEntity;
var Entity:int32;
    Cell:uint32;
begin
 result:=nil;
 while RealSize>=(1 shl LogSize) do begin
  Resize;
 end;
 Cell:=FindCell(Key);
 Entity:=CellToEntityIndex[Cell];;
 if Entity>=0 then begin
  result:=@Entities[Entity];
  if not allowOverride then exit;
  result^.Key:=Key;
  result^.Value:=Value;
  exit;
 end;
 Entity:=Size;
 inc(Size);
 if Entity<(2 shl LogSize) then begin
  CellToEntityIndex[Cell]:=Entity;
  inc(RealSize);
  result:=@Entities[Entity];
  result^.Key:=Key;
  result^.Value:=Value;
 end;
end;

function TXQBaseHashmap.findEntity(const Key:TKey;CreateIfNotExist:boolean=false):PHashMapEntity;
var Entity:int32;
    Cell:uint32;
begin
 result:=nil;
 Cell:=FindCell(Key);
 Entity:=CellToEntityIndex[Cell];
 if Entity>=0 then begin
  result:=@Entities[Entity];
 end else if CreateIfNotExist then begin
  result:=include(Key,default(TBaseValue));
 end;
end;

function TXQBaseHashmap.findEntity(data: pchar; keylen: SizeUInt): PHashMapEntity;
var Entity:int32;
    Cell:uint32;
begin
 result:=nil;
 Cell:=FindCell(data, keylen);
 Entity:=CellToEntityIndex[Cell];
 if Entity>=0 then
  result:=@Entities[Entity];
end;

function TXQBaseHashmap.exclude(const Key:TKey):boolean;
var Entity:int32;
    Cell:uint32;
begin
 result:=false;
 Cell:=FindCell(Key);
 Entity:=CellToEntityIndex[Cell];
 if Entity>=0 then begin
  Entities[Entity].Key:=DELETED_KEY;
  Entities[Entity].Value:=default(TBaseValue);
  CellToEntityIndex[Cell]:=ENT_DELETED;
  result:=true;
 end;
end;

function TXQBaseHashmap.contains(const key: TKey): boolean;
begin
  result := findEntity(key) <> nil;
end;

function TXQBaseHashmap.getBaseValueOrDefault(const Key: TKey): TBaseValue;
var Entity:int32;
    Cell:uint32;
begin
 Cell:=FindCell(Key);
 Entity:=CellToEntityIndex[Cell];
 if Entity>=0 then begin
  result:=Entities[Entity].Value;
 end else begin
  result:=default(TBaseValue);
 end;
end;

procedure TXQBaseHashmap.setBaseValue(const Key: TKey; const Value: TBaseValue);
begin
  include(Key,Value);
end;





function xqround(const f: xqfloat): Int64;
var tempf: xqfloat;
begin
  tempf := f + 0.5;
  result := trunc(tempf);
  if frac(tempf) < 0 then result -= 1;
end;

procedure TJSONXHTMLStrBuilder.init(abuffer: pstring; basecapacity: SizeInt; aencoding: TSystemCodePage);
begin
  inherited init(abuffer, basecapacity, aencoding);
  standard := false;
end;

procedure TJSONXHTMLStrBuilder.appendJSONEmptyObject;
begin
  append('{}')
end;

procedure TJSONXHTMLStrBuilder.appendJSONObjectStart;
begin
  append('{');
end;

procedure TJSONXHTMLStrBuilder.appendJSONObjectKeyColon(const key: string);
begin
  appendJSONString(key);
  append(': ');
end;

procedure TJSONXHTMLStrBuilder.appendJSONObjectComma;
begin
  append(', ');
end;

procedure TJSONXHTMLStrBuilder.appendJSONObjectEnd;
begin
  append('}');
end;

procedure TJSONXHTMLStrBuilder.appendJSONEmptyArray;
begin
  append('[]')
end;

procedure TJSONXHTMLStrBuilder.appendJSONArrayStart;
begin
  append('[');
end;

procedure TJSONXHTMLStrBuilder.appendJSONArrayComma;
begin
  append(', ');
end;

procedure TJSONXHTMLStrBuilder.appendJSONArrayEnd;
begin
  append(']');
end;

procedure TJSONXHTMLStrBuilder.appendJSONStringUnicodeEscape(codepoint: integer);
var
  s1, s2: word;
begin
  append('\u');
  if codepoint > $FFFF then begin
    utf16EncodeSurrogatePair(codepoint, s1, s2);
    appendHexNumber(s1, 4);
    append('\u');
    codepoint := s2;
  end;
  appendHexNumber(codepoint, 4)
end;

procedure TJSONXHTMLStrBuilder.appendJSONStringWithoutQuotes(const s: string);
var
  i: SizeInt;
begin
  for i:=1 to length(s) do begin
    case s[i] of
      #0..#8,#11,#12,#14..#31: begin
        append('\u00');
        appendHexNumber(ord(s[i]), 2);
      end;
      #9: append('\t');
      #10: append('\n');
      #13: append('\r');
      '"': append('\"');
      '\': append('\\');
      '/': if standard then append('\/') else append('/'); //mandatory in xquery standard
      else append(s[i]);
    end;
  end;
end;

procedure TJSONXHTMLStrBuilder.appendJSONString(const s: string);
begin
  append('"');
  appendJSONStringWithoutQuotes(s);
  append('"');
end;

class procedure TXQDefaultOwnershipTracker.addRef(o: TObject);
begin
 ignore(o);
  //empty
end;

class procedure TXQDefaultOwnershipTracker.release(o: TObject);
begin
  o.free;
end;

class procedure TXQDefaultOwnershipTracker.addRef(const str: string);
begin
  fpc_ansistr_incr_ref(pointer(str));
end;

class procedure TXQDefaultOwnershipTracker.release(var str: string);
begin
 fpc_ansistr_decr_ref(pointer(str));
end;


function TFastInterfacedObject.QueryInterface({$IFDEF FPC_HAS_CONSTREF}constref{$ELSE}const{$ENDIF} iid : tguid;out obj) : longint;{$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  if getinterface(iid,obj) then
    result:=S_OK
  else
    result:=longint(E_NOINTERFACE);
end;

function TFastInterfacedObject._AddRef: longint; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  result := InterlockedIncrement(frefcount);
end;

function TFastInterfacedObject._Release: longint; {$IFNDEF WINDOWS}cdecl{$ELSE}stdcall{$ENDIF};
begin
  result := InterlockedDecrement(frefcount);
  if result = 0 then destroy;
end;

procedure TFastInterfacedObject._AddRefIfNonNil;
begin
  if self <> nil then _AddRef;
end;

procedure TFastInterfacedObject._ReleaseIfNonNil;
begin
  if self <> nil then _Release;
end;

procedure TXQHashset.include(const Key: TKey; allowOverride: boolean);
begin
  inherited include(key, default(TXQVoid), allowOverride);
end;

function TXQBaseHashmapStrPointerButNotPointer.get(const Key: string; const def: TValue): TValue;
var
  entity: PHashMapEntity;
begin
  entity := findEntity(key);
  if entity = nil then result := def
  else result := tvalue(entity^.Value);
end;

function TXQBaseHashmapStrPointerButNotPointer.getOrDefault(const Key: string): TValue;
begin
  result := get(key, default(tvalue));
end;

function TXQBaseHashmapStrPointerButNotPointer.GetValue(const Key: string): TValue;
begin
  result := TValue(getBaseValueOrDefault(key));
end;

procedure TXQHashmapStr.SetValue(const Key: string; const AValue: TValue);
begin
  SetBaseValue(key, pointer(avalue));
end;

procedure TXQHashmapStr.include(const Key: string; const Value: TValue; allowOverride: boolean);
begin
  inherited include(key, pointer(value), allowOverride);
end;


procedure TXQHashmapStrOwning.include(const Key: string; const aValue: TValue; allowOverride: boolean=true);
var
  ent: PHashMapEntity;
begin
  ent := findEntity(key, true);
  if ent^.Value = pointer(AValue) then exit;
  if ent^.Value <> nil then begin
    if not allowOverride then exit;
    TOwnershipTracker.release(TValue(ent^.Value));
  end;
  TOwnershipTracker.addRef(avalue);
  ent^.Value:=pointer(avalue);
end;

procedure TXQHashmapStrOwning.SetValue(const Key: string; const AValue: TValue);
begin
  include(key, avalue, true);
end;

procedure TXQHashmapStrOwning.clear;
var
  i: SizeInt;
begin
 for i := 0 to high(Entities) do
   if (pointer(Entities[i].Key) <> pointer(DELETED_KEY)) and ( (Entities[i].Key <> '') or (Entities[i].Value <> nil) ) then
     TOwnershipTracker.Release(TValue(Entities[i].Value));
  inherited;
end;

destructor TXQHashmapStrOwning.done;
begin
  clear;
end;

class procedure TXQHashmapStrOwning.disposeAndNil(var map: PXQHashmapStrOwning);
begin
   if map <> nil then begin
     dispose(map,done);
     map := nil;
   end;
end;





function xmlStrEscape(s: string; attrib: boolean = false):string;
var
  builder: TXHTMLStrBuilder;

begin
  builder.init(@result, length(s));
  if not attrib then builder.appendXMLText(s)
  else builder.appendXMLAttrib(s);
  builder.final;
end;

function xmlStrWhitespaceCollapse(const s: string): string;
begin
  result := strTrimAndNormalize(s, [#9,#$A,#$D,' ']);
end;

procedure TXHTMLStrBuilder.appendHexEntity(codepoint: integer);
begin
  append('&#x');
  if codepoint <= $FF then begin
    if codepoint > $F then append(charEncodeHexDigitUp( codepoint shr 4 ));
    append(charEncodeHexDigitUp(  codepoint and $F ))
  end else appendHexNumber(codepoint);
  append(';');
end;

procedure TXHTMLStrBuilder.appendHTMLText(inbuffer: pchar; len: SizeInt);
var
  inbufferend: pchar;
begin
  inbufferend := inbuffer + len;
  reserveadd(len);
  while inbuffer < inbufferend do begin
    case inbuffer^ of
      '&': append('&amp;');
      '<': append('&lt;');
      '>': append('&gt;');
      else append(inbuffer^);
    end;
    inc(inbuffer);
  end;
end;


procedure TXHTMLStrBuilder.appendHTMLAttrib(inbuffer: pchar; len: SizeInt);
var
  inbufferend: pchar;
begin
  inbufferend := inbuffer + len;
  reserveadd(len);
  while inbuffer < inbufferend do begin
    case inbuffer^ of
      '&': append('&amp;');
      '"': append('&quot;');
      '''': append('&apos;');
      else append(inbuffer^);
    end;
    inc(inbuffer);
  end;
end;

procedure TXHTMLStrBuilder.appendHTMLText(const s: string);
begin
  appendHTMLText(pchar(pointer(s)), length(s));
end;
procedure TXHTMLStrBuilder.appendHTMLAttrib(const s: string);
begin
  appendHTMLAttrib(pchar(pointer(s)), length(s));
end;

procedure TXHTMLStrBuilder.appendHTMLElementAttribute(const name, value: string);
begin
  append(' ');
  append(name);
  append('="');
  appendHTMLAttrib(value);
  append('"');
end;

procedure TXHTMLStrBuilder.appendXMLHeader(const version, anencoding: string; standalone: TXMLDeclarationStandalone);
begin
  append('<?xml version="'+version+'" encoding="'+anencoding+'"');
  case standalone of
    xdsOmit:;
    xdsYes: append(' standalone="yes"');
    xdsNo: append(' standalone="no"');
  end;
  append('?>');
end;

procedure TXHTMLStrBuilder.appendXMLElementStartOpen(const name: string);
begin
  append('<');
  append(name);
end;

procedure TXHTMLStrBuilder.appendXMLElementAttribute(const name, value: string);
begin
  append(' ');
  append(name);
  append('="');
  appendXMLAttrib(value);
  append('"');
end;

procedure TXHTMLStrBuilder.appendXMLElementStartClose();
begin
  append('>');
end;

procedure TXHTMLStrBuilder.appendXMLElementStartTag(const name: string);
begin
  appendXMLElementStartOpen(name);
  append('>');
end;

procedure TXHTMLStrBuilder.appendXMLElementEndTag(const name: string);
begin
  append('</');
  append(name);
  append('>');
end;

procedure TXHTMLStrBuilder.appendXMLProcessingInstruction(const name, content: string);
begin
  append('<?');
  append(name);
  if content <> '' then begin
    append(' ');
    append(content);
  end;
  append('?>');
end;

procedure TXHTMLStrBuilder.appendXMLEmptyElement(const name: string);
begin
  appendXMLElementStartOpen(name);
  append('/>');
end;

procedure TXHTMLStrBuilder.appendXMLText(const s: string);
var
  i: SizeInt;
begin
  reserveadd(length(s));
  i := 1;
  while i <= length(s) do begin
    case s[i] of
      '<': append('&lt;');
      '>': append('&gt;');
      '&': append('&amp;');
      '''': append('&apos;');
      '"': append('&quot;');
      #13: append('&#xD;');
      #0..#8,#11,#12,#14..#$1F,#$7F: appendhexentity(ord(s[i]));
      #$C2: if (i = length(s)) or not (s[i+1] in [#$80..#$9F]) then append(#$C2) else begin
        i+=1;
        appendhexentity(ord(s[i]));
      end;
      #$E2: if (i + 2 > length(s)) or (s[i+1] <> #$80) or (s[i+2] <> #$A8) then append(#$E2) else begin
        append('&#x2028;');
        i+=2;
      end;
      else append(s[i]);
    end;
    i+=1;
  end;
end;

procedure TXHTMLStrBuilder.appendXMLAttrib(const s: string);
var
  i: SizeInt;
begin
  reserveadd(length(s));
  i := 1;
  while i <= length(s) do begin
    case s[i] of
      '<': append('&lt;');
      '>': append('&gt;');
      '&': append('&amp;');
      '''': append('&apos;');
      '"': append('&quot;');
      #13: append('&#xD;');
      #10: append('&#xA;');
      #9: append('&#x9;');
      #0..#8,#11,#12,#14..#$1F,#$7F: appendhexentity(ord(s[i]));
      #$C2: if (i = length(s)) or not (s[i+1] in [#$80..#$9F]) then append(#$C2) else begin
        i+=1;
        appendhexentity(ord(s[i]));
      end;
      #$E2: if (i + 2 > length(s)) or (s[i+1] <> #$80) or (s[i+2] <> #$A8) then append(#$E2) else begin
        append('&#x2028;');
        i+=2;
      end;
      else append(s[i]);
    end;
    i+=1;
  end;
end;

procedure TXHTMLStrBuilder.appendXMLCDATAStart();
begin
  append('<![CDATA[');
end;

procedure TXHTMLStrBuilder.appendXMLCDATAText(p: pchar; len: sizeint);
var pendMinus2, marker: pchar;
  procedure appendMarkedBlock;
  begin
    if p = marker then exit;
    appendXMLCDATAStart();
    append(marker, p - marker);
    appendXMLCDATAEnd();
  end;

begin
  if len = 0 then exit;
  pendMinus2 := p + len - 2;
  marker := p;
  while p < pendMinus2 do begin
    if {p+2 < pend and } (p^ = ']') and ((p + 1)^ = ']') and ((p + 2)^ = '>') then begin
      inc(p, 2);
      appendMarkedBlock;
      marker := p;
    end else inc(p);
  end;
  p := pendMinus2 + 2;
  appendMarkedBlock;
end;

procedure TXHTMLStrBuilder.appendXMLCDATAText(const s: string);
begin
  appendXMLCDATAText(pointer(s), length(s));
end;

procedure TXHTMLStrBuilder.appendXMLCDATAEnd();
begin
  append(']]>');
end;

function htmlStrEscape(s: string; attrib: boolean): string;
var
  builder: TXHTMLStrBuilder;
begin
  builder.init(@result, length(s));
  if attrib then builder.appendHTMLAttrib(s)
  else builder.appendHTMLText(s);
  builder.final;
end;

function jsonStrEscape(s: string): string;
var
  builder: TJSONXHTMLStrBuilder;
begin
  builder.init(@result, length(s) + 2);
  builder.appendJSONString(s);
  builder.final;
end;

function strSplitOnAsciiWS(s: string): TStringArray;
begin
  result := strSplit(strTrimAndNormalize(s, [#9,#$A,#$C,#$D,' ']), ' ');
end;

function urlHexDecode(s: string): string;
var
  p: Integer;
  i: Integer;
begin
  result := '';
  SetLength(result, length(s));
  p := 1;
  i := 1;
  while i <= length(s) do begin
    case s[i] of
      '+': result[p] := ' ';
      '%': if (i + 2 <= length(s)) and (s[i+1] in ['a'..'f','A'..'F','0'..'9']) and (s[i+2] in ['a'..'f','A'..'F','0'..'9']) then begin
        result[p] := chr(StrToInt('$'+s[i+1]+s[i+2])); //todo: optimize
        i+=2;
      end else raiseXQEvaluationException('pxp:uri', 'Invalid input string at: '+copy(s,i,10))
      else result[p] := s[i];
    end;
    i+=1;
    p+=1;
  end;
  setlength(result, p-1);
end;








{$PUSH}{$RangeChecks off}{$OverflowChecks off}
class function TXQDefaultTypeInfo.hash(data: pchar; datalen: SizeUInt): uint32;
var
  p, last: PByte;
begin
  if datalen = 0 then exit(1);
  p := pbyte(data);
  last := p + datalen;
  result := 0;
  while p < last do begin
    result := result + p^;
    result := result + (result shl 10);
    result := result xor (result shr 6);
    inc(p);
  end;

  result := result + (result shl 3);
  result := result xor (result shr 11);
  result := result + (result shl 15);
end;

class procedure TXQDefaultTypeInfo.createDeletionKey(out key: string);
begin
  key := #0'DELETED';
end;

class function TXQBaseHashmap.hash(const key: TKey): uint32;
begin
  result := TInfo.hash(pointer(key), length(key));
end;

function nodeNameHash(const s: RawByteString): cardinal;
var
  p, last: PByte;
begin
  if s = '' then exit(1);
  p := pbyte(pointer(s));
  last := p + length(s);
  result := 0;
  while p < last do begin
    if p^ < 128  then begin //give the same hash independent of latin1/utf8 encoding and collation
      result := result + p^;
      if (p^ >= ord('a')) and (p^ <= ord('z')) then result := result - ord('a') + ord('A');
      result := result + (result shl 10);
      result := result xor (result shr 6);
    end;
    inc(p);
  end;

  result := result + (result shl 3);
  result := result xor (result shr 11);
  result := result + (result shl 15);
  //remember to update HTMLNodeNameHashs when changing anything here;
end;
function nodeNameHashCheckASCII(const s: RawByteString): cardinal;
var
  i: Integer;
begin
  for i := 1 to length(s) do if s[i] >= #128 then exit(0);
  result := nodeNameHash(s);
end;

{$POP}


procedure raiseXQEvaluationException(const code, message: string); noreturn;
begin
  if Assigned(raiseXQEvaluationExceptionCallback) then raiseXQEvaluationExceptionCallback(code, message)
  else raise exception.Create(code + ': ' + message);
end;





procedure TFastInterfaceList.setCapacity(AValue: integer);
begin
  if avalue > fcapacity then setBufferSize(AValue)
  else if avalue < fcount then setCount(AValue)
  else if avalue < fcapacity then setBufferSize(AValue);
end;

procedure TFastInterfaceList.raiseInvalidIndexError(i: integer);
begin
  raiseXQEvaluationException('pxp:INTERNAL', 'Invalid index: '+IntToStr(i));
end;

procedure TFastInterfaceList.checkIndex(i: integer);
begin
  if (i < 0) or (i >= fcount) then raiseInvalidIndexError(i);
end;


procedure TFastInterfaceList.put(i: integer; const AValue: IT); inline;
begin
  assert(AValue <> nil);
  checkIndex(i);
  fbuffer[i] := AValue;
end;

procedure TFastInterfaceList.delete(i: integer);
begin
  checkIndex(i);
  fbuffer[i] := nil;
  if i <> fcount - 1 then begin
    move(fbuffer[i+1], fbuffer[i], (fcount - i - 1) * sizeof(IT));
    FillChar(fbuffer[fcount-1], sizeof(fbuffer[fcount-1]), 0);
  end;
  fcount -= 1;
  compress;
end;

procedure TFastInterfaceList.remove(const value: IT);
var
  i: Integer;
begin
  for i := fcount - 1 downto 0 do
    if fbuffer[i] = value then
      delete(i);
end;

procedure TFastInterfaceList.add(const value: IT);
begin
  assert(value <> nil);
  if fcount = fcapacity then
    reserve(fcount + 1);
  PPointer(fbuffer)[fcount] := value;
  value._AddRef;
  fcount += 1;
end;

procedure TFastInterfaceList.addAll(other: TFastInterfaceList);
var
  i: Integer;
begin
  reserve(fcount + other.Count);
  for i := 0 to other.Count - 1 do
    add(other.fbuffer[i]);
end;

function TFastInterfaceList.get(i: integer): IT;
begin
  checkIndex(i);
  result := fbuffer[i];
end;

function TFastInterfaceList.last: IT;
begin
  checkIndex(0);
  result := fbuffer[fcount-1];
end;

function TFastInterfaceList.first: IT;
begin
  checkIndex(0);
  result := fbuffer[0];
end;




{$ImplicitExceptions off}

procedure TFastInterfaceList.setBufferSize(c: integer);
var
  oldcap: Integer;
begin
  oldcap := fcapacity;
  ReAllocMem(fbuffer, c * sizeof(IT));
  fcapacity := c;
  if fcapacity > oldcap then
    FillChar(fbuffer[oldcap], sizeof(IT) * (fcapacity - oldcap), 0);
end;

procedure TFastInterfaceList.reserve(cap: integer);
var
  newcap: Integer;
begin
  if cap <= fcapacity then exit;

  if cap < 4 then newcap := 4
  else if (cap < 1024) and (cap <= fcapacity * 2) then newcap := fcapacity * 2
  else if (cap < 1024) then newcap := cap
  else if cap <= fcapacity + 1024 then newcap := fcapacity + 1024
  else newcap := cap;

  setBufferSize(newcap);
end;

procedure TFastInterfaceList.compress;
begin
  if fcount <= fcapacity div 2 then setBufferSize(fcapacity div 2)
  else if fcount <= fcapacity - 1024 then setBufferSize(fcapacity - 1024);
end;

procedure TFastInterfaceList.setCount(c: integer);
var
  i: Integer;
begin
  reserve(c);
  if c < fcount then begin
    for i := c to fcount - 1 do
      fbuffer[i]._Release;
    FillChar(fbuffer[c], (fcount - c) * sizeof(IT), 0);
  end;
  fcount:=c;
end;




{$ImplicitExceptions on}

procedure TFastInterfaceList.clear;
var
  i: Integer;
begin
  for i := 0 to fcount - 1 do begin
    assert(fbuffer[i] <> nil);
    fbuffer[i]._Release;
  end;
  fcount:=0;
  setBufferSize(0);
end;

destructor TFastInterfaceList.Destroy;
begin
  clear;
  inherited Destroy;
end;

procedure TFastInterfaceList.insert(i: integer; child: IT);
begin
  assert(child <> nil);
  reserve(fcount + 1);
  if i <> fcount then begin
    checkIndex(i);
    move(fbuffer[i], fbuffer[i+1], (fcount - i) * sizeof(fbuffer[i]));
    fillchar(fbuffer[i],sizeof(fbuffer[i]),0);
  end;
  fbuffer[i] := child;
  fcount+=1;
end;

constructor TFastInterfaceList.create(capacity: integer);
begin
  reserve(capacity);
  fcount := 0;
end;



end.


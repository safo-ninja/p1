unit zsJSON;

interface

uses
  SysUtils, Classes, Windows;

type
  TzsTokenType = (ttNone, ttStartObject, ttEndObject, ttStartArray, ttEndArray,
    ttPropertyName,
    // ttComment,
    ttString, ttNumber, ttTrue, ttFalse, ttNull);

  TzsJSONReader = class
  private
    function GetIsEmpty : Boolean;
    procedure SetIsEmpty(const Value : Boolean);
  private
    FBuff : packed array[0..63] of Char;
    FStream : TStream;
    FTokenType : TzsTokenType;
    FValueReady : Boolean;
    FValue : string;
    FStack : array of Byte;

    FTop : Integer;

    function PeekStack() : TzsTokenType;
    function PopStack() : TzsTokenType;
    procedure PushStack();

    procedure _PrefetchValue();

    function _Read(const cnt : Integer; bRaise : Boolean = False) : Boolean;
    function _SkipWhiteSpaces(bRaise : Boolean = False) : Boolean;

    property IsEmpty : Boolean read GetIsEmpty write SetIsEmpty;
  public
    constructor Create(AStream : TStream);
    destructor Destroy(); override;
    function Read() : Boolean;
    function GetString() : string;
    function GetValue() : string;

    property TokenType : TzsTokenType read FTokenType;
  end;

  TzsJSONWriter = class
  private
    FTop : Integer;
    FStack : array of Byte;
    FStream : TStream;
    FIdent : Integer;

    procedure Write(const s : string);
    procedure WritePreStr();
    procedure WriteIdent();
    procedure PushStack(const tt : TzsTokenType);
    function PopStack() : TzsTokenType;
    function PeekStack() : TzsTokenType;

    procedure CheckValueNeeded(const b : Boolean);
    procedure CheckAllowProperty();
    procedure WriteRawValue(const AValue : string);
    procedure WriteRawNamedValue(const AName, AValue : string);

    function GetHasItems() : Boolean;
    function GetValueNeeded() : Boolean;
    procedure SetHasItems(const Value : Boolean);
    procedure SetValueNeeded(const Value : Boolean);

    property ValueNeeded : Boolean read GetValueNeeded write SetValueNeeded;
    property HasItems : Boolean read GetHasItems write SetHasItems;

  public
    constructor Create(AStream : TStream; AIdent : Integer = 0);
    destructor Destroy(); override;
    procedure WriteStartObject();
    procedure WriteEndObject();
    procedure WriteStartArray();
    procedure WriteEndArray();
    procedure WritePropertyName(const AName : string);
    procedure WriteStringValue(const AName : string; const AValue : string);
    procedure WriteString(const AValue : string);
    procedure WriteNumericValue(const AName : string; const AValue : Integer); overload;
    procedure WriteNumericValue(const AName : string; const AValue : Double); overload;
    procedure WriteNumericValue(const AName : string; const AValue : Double; ADecimalCnt : Integer); overload;
    procedure WriteNumeric(const AValue : Integer); overload;
    procedure WriteNumeric(const AValue : Double); overload;
    procedure WriteNumeric(const AValue : Double; ADecimalCnt : Integer); overload;
    procedure WriteBooleanValue(const AName : string; const AValue : Boolean);
    procedure WriteBoolean(const AValue : Boolean);
    procedure WriteNullValue(const AName : string);
    procedure WriteNull();
  end;

  TzsItemType = (zsString, zsNumber, zsObject, zsArray, zsNull, zsBoolean);

  TzsJSONItem = class
  private
    FOwner : TzsJSONItem;
    FName : string;
    FItemType : TzsItemType;
    FItems : TList;
    FValue : string;

    procedure Export2Writer(const AWriter : TzsJSONWriter);

    function Vperde(AItemType : TzsItemType) : TzsJSONItem;

    procedure LoadFromReader(r : TzsJSONReader);
    function GetItemsByIndex(i : Integer) : TzsJSONItem;
    function GetCount() : Integer;
    function GetItemsByName(itemName : string) : TzsJSONItem;
    function GetValue : string;
  public
    constructor Create();
    destructor Destroy(); override;
    procedure Clear();
    property Count : Integer read GetCount;
    property Items[i : Integer] : TzsJSONItem read GetItemsByIndex;
    property ItemByName[itemName : string] : TzsJSONItem read GetItemsByName; default;
    property Name : string read FName write FName;
    property ItemType : TzsItemType read FItemType;
    property Value : string read GetValue;
    function GetAsBoolean(): Boolean;
    procedure SetAsBoolean(const b: Boolean);
    function GetAsDateTime(): TDateTime;
    procedure SetAsDateTime(const dt: TDateTime);
    function GetAsFloat(): Extended;
    procedure SetAsFloat(const f: Extended; const digits : Integer); overload;
    procedure SetAsFloat(const f: Extended); overload;
    function GetAsInt(): Integer;
    procedure SetAsInt(const n: Integer);
    function GetAsInt64(): Int64;
    procedure SetAsInt64(const n: Int64);
  end;

  TzsJSON = class(TzsJSONItem)
  public
    procedure Load(AStream : TStream);
    class function EncodeDateTime(dt : TDateTime) : string;
    class function DecodeDateTime(s : string) : TDateTime;
    class function EncodeString(const s : string) : string;

    function ToString(AIdent : Integer = 0) : string;
  end;

implementation

{ TzsJSONReader }

type
  PSmallCharArray = ^TSmallCharArray;
  TSmallCharArray = packed array[0..1024] of Char;

var
  zbsettings : TFormatSettings;

function _isDigit(c : Char) : Boolean;
begin
  Result := (c >= '0') and (c <= '9');
end;

function _H2B(p : PChar) : Byte;

  function __4(p : PChar) : Byte;
  begin
    if (p^ >= '0') and (p^ <= '9') then
      Result := Ord(p^) - Ord('0')
    else if (p^ >= 'a') and (p^ <= 'f') then
      Result := 10 + Ord(p^) - Ord('a')
    else if (p^ >= 'A') and (p^ <= 'F') then
      Result := 10 + Ord(p^) - Ord('A')
    else
      raise Exception.Create('Непонятная шестнадцатиричная цифра ' + p^);
  end;

begin
  Result := __4(p);
  Inc(p);
  Result := (Result shl 4) or __4(p);
end;

function TzsJSONReader._SkipWhiteSpaces(bRaise : Boolean = False) : Boolean;
begin
  while _Read(1, bRaise) do
  begin
    if FBuff[0] > #32 then
    begin
      Result := True;
      Exit;
    end;
  end;

  Result := False;
end;

constructor TzsJSONReader.Create(AStream : TStream);
begin
  FTop := -1;
  SetLength(FStack, 100);
  FStack[1] := 0;

  FStream := AStream;
  FTokenType := ttNone;
  PushStack();
end;

destructor TzsJSONReader.Destroy();
begin
  inherited;
end;

procedure _RaiseChar(c : Char; iWantThisChar : string = '');
begin
  if iWantThisChar = '' then
    raise Exception.CreateFmt('Неожиданный символ #%d', [Ord(c)])
  else
    raise Exception.CreateFmt('Неожиданный символ #%d вместо "%s"', [Ord(c), iWantThisChar]);
end;

function TzsJSONReader.Read() : Boolean;
var
  p : PChar;

begin
  p := @FBuff[0];

  if (FTop = 0) and (FStack[1] <> 0) then
  begin
    Result := False;
    Exit;
  end;

  Result := _SkipWhiteSpaces(FTokenType <> ttNone);

  if FValue = '6' then
    if Self = nil then
      Exit;

  if not Result then
    Exit;

  try

    if FTokenType = ttPropertyName then
    begin
      // Ситаем в никуда название свойства, если не читали
      if not FValueReady then
      begin
        GetString();
        FValueReady := False;
      end;

      if p^ <> ':' then
        _RaiseChar(p^, ':');

      _SkipWhiteSpaces(True);

      FValueReady := False;

      if p^ = '{' then
      begin
        FTokenType := ttStartObject;
        PushStack();
        Exit;
      end;

      if p^ = '[' then
      begin
        FTokenType := ttStartArray;
        PushStack();
        Exit;
      end;

      _PrefetchValue();

      Exit;
    end;

    if Self.FTokenType = ttNone then // Допустимы только объект и массив
    begin
      FValueReady := False;
      if p^ = '{' then
        Self.FTokenType := ttStartObject

      else if p^ = '[' then
        Self.FTokenType := ttStartArray
      else
        _RaiseChar(p^);

      PushStack();
      Exit;
    end;

    if p^ = '}' then
    begin
      if PeekStack() = ttStartObject then
      begin
        Self.FTokenType := ttEndObject;
        PopStack();
        Exit;
      end
      else
        _RaiseChar(p^);
    end;

    if p^ = ']' then
    begin
      if PeekStack() = ttStartArray then
      begin
        Self.FTokenType := ttEndArray;
        PopStack();
        Exit;
      end
      else
        _RaiseChar(p^);
    end;

    if FTokenType = ttStartObject then
    begin
      if (p^ = ',') then
      begin
        if IsEmpty then
          _RaiseChar(p^);

        _SkipWhiteSpaces(True);
      end;

      if p^ <> '"' then
        _RaiseChar(p^);

      Self.FTokenType := ttPropertyName;
      FValue := GetString();
      FValueReady := True;
      IsEmpty := False;
      Exit;
    end;

    // Код, котрый ниже, начерх переносимть не нужно, это хреновая идея
    FTokenType := PeekStack();

    if FTokenType = ttStartArray then
    begin
      if p^ = ',' then
      begin
        if IsEmpty then
          _RaiseChar(p^);

        _SkipWhiteSpaces(True);
      end;

      if p^ = ']' then
      begin
        PopStack();
        FTokenType := ttEndArray;
        Exit;
      end;

      _PrefetchValue();

      Exit;
    end;

    if FTokenType = ttStartObject then
    begin
      if p^ = ',' then
      begin
        if IsEmpty then
          _RaiseChar(p^);

        _SkipWhiteSpaces(True);
      end;

      if p^ = '}' then
      begin
        PopStack();
        FTokenType := ttEndObject;
        Exit;
      end;

      _PrefetchValue();
      FTokenType := ttPropertyName;

      Exit;
    end;

  except
    FStream.Seek(0, soEnd);
    raise;
  end;
end;

function TzsJSONReader._Read(const cnt : Integer; bRaise : Boolean = False) : Boolean;
var
  n : Integer;
begin
  n := FStream.Read(Self.FBuff, SizeOf(Char) * cnt);
  Result := n = SizeOf(Char) * cnt;

  if not Result and bRaise then
    raise Exception.Create('Неожиданно закончился JSON');
end;

function TzsJSONReader.GetString() : string;
var
  b : packed array[0..1] of Byte;
  p : PChar;
begin
  if FValueReady then
  begin
    Result := FValue;
    Exit;
  end;

  FValueReady := True;
  Result := '';
  p := @FBuff[0];

  while True do
  begin
    _Read(1, True);

    if p^ = '"' then
      break;

    if p^ = '\' then
    begin
      _Read(1, True);

      case p^ of
        'f' : Result := Result + #12;
        'r' : Result := Result + #13;
        'n' : Result := Result + #10;
        't' : Result := Result + #9;
        'b' : Result := Result + #8;
        '\', '"', '/' : Result := Result + p^;
        'u' :
          begin
            _Read(4, True);
            FBuff[4] := #0;
            b[1] := _H2B(@FBuff[0]);
            b[0] := _H2B(@FBuff[2]);
            WideCharToMultiByte(1251, 0, PWidechar(@b[0]), 1, p, 1, nil, nil);
            Result := Result + p^;
          end
        else
          raise Exception.Create('Неведомая escape-последовательность ' + p^);

      end; // case
    end
    else
      Result := Result + p^;

  end;
end;

function TzsJSONReader.GetValue() : string;
begin
  if FValueReady then
  begin
    Result := FValue;
    Exit;
  end;
end;

function TzsJSONReader.PeekStack() : TzsTokenType;
var
  w : Word;
begin
  w := FStack[FTop] and $0F;
  Result := ttNone;

  if w = 2 then
    Result := ttStartArray
  else if w = 1 then
    Result := ttStartObject;

end;

function TzsJSONReader.PopStack() : TzsTokenType;
begin
  Dec(FTop);
  FValue := '';
  FValueReady := False;
  Result := PeekStack();
end;

procedure TzsJSONReader.PushStack();
var
  b : Byte;
begin
  IsEmpty := False;
  Inc(FTop);
  FValueReady := False;

  if FTop >= Length(FStack) then
    SetLength(FStack, FTop + 30);

  if FTokenType = ttStartObject then
    b := 1
  else if FTokenType = ttStartArray then
    b := 2
  else if FTokenType = ttNone then
    b := 0
  else
    raise Exception.Create('Ошибка в TzsJSONReader.PushStack');

  FStack[FTop] := b;
end;

procedure TzsJSONReader._PrefetchValue();

  function _CorrectNumValue() : Boolean;
  var
    b : Boolean;
    i, n : Integer;
  begin
    b := False;
    Result := False;
    i := 0;
    n := Length(FValue);
    while i < n do
    begin
      Inc(i);
      if FValue[i] = '.' then
      begin
        b := not b;
        if not b then
          Exit;
      end
      else if not _isDigit(FValue[i]) then
        Exit;
    end;

    Result := True;
  end;

var
  p : PChar;
begin
  p := @FBuff[0];
  FValue := '';
  FValueReady := True;

  if p^ = '{' then
  begin
    FTokenType := ttStartObject;
    PushStack();
    Exit;
  end;

  if p^ = '[' then
  begin
    FTokenType := ttStartArray;
    PushStack();
    Exit;
  end;

  if p^ = ',' then
  begin
    if IsEmpty then
      _RaiseChar(p^);
    _SkipWhiteSpaces(True);
  end;

  if PeekStack() = ttStartArray then
    IsEmpty := False;

  if p^ = '"' then
  begin
    FTokenType := ttString;
    FValueReady := False;
    FValue := GetString();
  end
  else
  begin
    FStream.Seek(-1, soCurrent);
    _SkipWhiteSpaces(True);
    repeat
      if (p^ = ',') or (p^ <= #32) then
      begin
        FStream.Seek(-1, soCurrent);
        Break;
      end;

      if p^ = ']' then
      begin
        if PeekStack() = ttStartArray then
        begin
          if FValue = '' then
          begin
            PopStack();
            FTokenType := ttEndArray;
            Exit;
          end;

          FStream.Seek(-1, soCurrent);
          Break;
        end
        else
          _RaiseChar(p^);
      end
      else if p^ = '}' then
      begin
        if PeekStack() = ttStartObject then
        begin
          if FValue = '' then
          begin
            PopStack();
            FTokenType := ttEndObject;
            Exit;
          end;
          FStream.Seek(-1, soCurrent);
          Break;
        end
        else
          _RaiseChar(p^);
      end;

      FValue := FValue + p^;

      _Read(1, True);

    until False;

    if FValue = '' then
      _RaiseChar(p^);

    if LowerCase(FValue) = 'null' then
    begin
      FValue := 'null';
      FTokenType := ttNull;
    end
    else if LowerCase(FValue) = 'false' then
    begin
      FValue := 'false';
      FTokenType := ttFalse;
    end
    else if LowerCase(FValue) = 'true' then
    begin
      FValue := 'true';
      FTokenType := ttTrue;
    end
    else
    begin
      if not _CorrectNumValue() then
        raise Exception.Create('Некорректное значение ' + FValue);
      FTokenType := ttNumber;
    end;

  end;

end;

function TzsJSONReader.GetIsEmpty() : Boolean;
begin
  Result := (FStack[FTop] and $10) = 0;
end;

procedure TzsJSONReader.SetIsEmpty(const Value : Boolean);
begin
  if Value then
    FStack[FTop] := FStack[FTop] and (not $10)
  else
    FStack[FTop] := FStack[FTop] or $10;
end;

{ TzsJSON }

procedure TzsJSONItem.Clear();
var
  i : Integer;
begin
  for i := 0 to Count - 1 do
  begin
    Items[i].Clear();
    Items[i].Free();
  end;

  FItems.Clear();
end;

constructor TzsJSONItem.Create();
begin
  FItems := TList.Create();
end;

destructor TzsJSONItem.Destroy();
begin
  Clear();
  FItems.Free();
  inherited;
end;

procedure TzsJSONItem.Export2Writer(const AWriter : TzsJSONWriter);
var
  i : Integer;
  tmp : TzsJSONItem;
begin
  try
    case Self.FItemType of
      zsObject :
        begin
          AWriter.WriteStartObject();
          for i := 0 to Self.Count - 1 do
          begin
            tmp := Self.Items[i];
            if tmp.FOwner <> nil then
              AWriter.WritePropertyName(tmp.Name);
            tmp.Export2Writer(AWriter);
          end;
          AWriter.WriteEndObject();
        end;
      zsArray :
        begin
          AWriter.WriteStartArray();
          for i := 0 to Self.Count - 1 do
            Self.Items[i].Export2Writer(AWriter);

          AWriter.WriteEndArray();
        end;
      zsString : AWriter.WriteString(Self.Value);
      zsNumber : AWriter.WriteRawValue(Self.Value);
      zsBoolean : AWriter.WriteBoolean(Self.Value = 'true');
      zsNull : AWriter.WriteNull();
      else
        raise Exception.Create('Неведомые данные!');
    end;
    AWriter.ValueNeeded := False;
  except
    on E : Exception do
      raise Exception.Create(Self.Name + #13#10'' + E.Message);
  end;
end;

function TzsJSONItem.GetCount() : Integer;
begin
  Result := FItems.Count;
end;

function TzsJSONItem.GetItemsByIndex(i : Integer) : TzsJSONItem;
begin
  Result := TzsJSONItem(FItems[i]);
end;

function TzsJSONItem.GetItemsByName(itemName : string) : TzsJSONItem;
var
  i : Integer;
begin
  for i := 0 to Count - 1 do
  begin
    if Items[i].Name = itemName then
    begin
      Result := Items[i];
      Exit;
    end;
  end;

  raise Exception.CreateFmt('Нет ничего с именем "%s"', [itemName]);
end;

{ TzsJSON }

class function TzsJSON.DecodeDateTime(s : string) : TDateTime;
var
  L : Integer;

  procedure _SayAzaza();
  begin
    raise Exception.Create('Неведомый формат даты ' + s);
  end;

  function _Chk(const s, t : string; const bExt : Boolean = False) : Boolean;
  var
    i : Integer;
  begin
    Result := False;

    if bExt then
      if L > Length(t) then
        L := Length(t);

    if L <> Length(t) then
      Exit;

    for i := 1 to L do
    begin
      case t[i] of
        ' ' : if not (s[i] in [' ', 'T']) then Exit;
        'T', '-', ':' : if s[i] <> t[i] then Exit;
        '0' : if (Ord(s[i]) < $30) or (Ord(s[i]) > $39) then Exit;
        else
          raise Exception.Create('Неведомый шаблон даты');
      end;
    end;

    Result := True;
  end;

  function _ReadWord(const s : string; const startIndex, count : Integer) : Word;
  var
    i : Integer;
  begin
    Result := 0;
    i := 0;
    while i < count do
    begin
      Result := (Result * 10) + Ord(s[startIndex + i]) - $30;
      Inc(i);
    end;
  end;

var
  Y, M, D, HH, NN, SS : Word;
begin
  L := Length(s);
  Result := 0;
  try
    if _Chk(s, 'T00:00:00') then
    begin
     // Thh:mm:ss
     // 123456789
      HH := _ReadWord(s, 2, 2);
      NN := _ReadWord(s, 5, 2);
      SS := _ReadWord(s, 8, 2);

      Result := EncodeTime(HH, NN, SS, 0);
    end
    else if _Chk(s, '0000-00-00') then
    begin
      // YYYY-MM-DD
      // 1234567890
      Y := _ReadWord(s, 1, 4);
      M := _ReadWord(s, 6, 2);
      D := _ReadWord(s, 9, 2);

      Result := EncodeDate(Y, M, D);
    end
    else if _Chk(s, '0000-00-00 00:00:00', True) then
    begin
      // YYYY-MM-DDTHH:NN:SS
      // YYYY-MM-DD HH:NN:SS
      // 1234567890123456789
      Y := _ReadWord(s, 1, 4);
      M := _ReadWord(s, 6, 2);
      D := _ReadWord(s, 9, 2);
      HH := _ReadWord(s, 12, 2);
      NN := _ReadWord(s, 15, 2);
      SS := _ReadWord(s, 18, 2);

      Result := EncodeDate(Y, M, D) + EncodeTime(HH, NN, SS, 0);
    end
    else if _Chk(s, '00000000') then
    begin
      // YYYYMMDD
      // 12345678
      Y := _ReadWord(s, 1, 4);
      M := _ReadWord(s, 5, 2);
      D := _ReadWord(s, 6, 2);

      Result := EncodeDate(Y, M, D);
    end
    else
      _SayAzaza();
  except
    raise;
  end;
end;

class function TzsJSON.EncodeDateTime(dt : TDateTime) : string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd"T"hh":"nn":"ss', dt);
end;

class function TzsJSON.EncodeString(const s : string) : string;

  procedure _C2H(c : Char; p : PChar);
    function __5OH(const b : Byte) : Char;
    begin
      if b <= $09 then
        Result := Char(Ord('0') + b)
      else
        Result := Char(Ord('A') + b - 10);
    end;

  var
    pp : PSmallCharArray absolute p;
  begin
    pp[0] := __5OH((Ord(c) and $F0) shr 4);
    pp[1] := __5OH(Ord(c) and $0F);
  end;

var
  L, i, n : Integer;
  p : PChar;
begin
  L := Length(s);
  if L = 0 then
  begin
    Result := '""';
    Exit;
  end;

  SetLength(Result, L + 100);
  Result[1] := '"';

  i := 0;
  n := 2;

  p := @s[1];

  while i < L do
  begin
    if Length(Result) > (n - 10) then
      SetLength(Result, n + 100);

    case p^ of
      #8 :
        begin
          Result[n] := '\';
          Inc(n);
          Result[n] := 'b';
        end;
      #9 :
        begin
          Result[n] := '\';
          Inc(n);
          Result[n] := 't';
        end;
      #10 :
        begin
          Result[n] := '\';
          Inc(n);
          Result[n] := 'n';
        end;
      #12 :
        begin
          Result[n] := '\';
          Inc(n);
          Result[n] := 'f';
        end;
      #13 :
        begin
          Result[n] := '\';
          Inc(n);
          Result[n] := 'r';
        end;
      '"', '\' :
        begin
          Result[n] := '\';
          Inc(n);
          Result[n] := p^;
        end;
      else
        begin
          if p^ < #32 then
          begin
            Result[n + 0] := '\';
            Result[n + 1] := 'u';
            Result[n + 2] := '0';
            Result[n + 3] := '0';
            _C2H(p^, @Result[n + 4]);

            Inc(n, 5);
          end
          else
            Result[n] := p^;
        end

    end;
    Inc(i);
    Inc(p);
    Inc(n);
  end;

  Result[n] := '"';
  SetLength(Result, n);
end;

procedure TzsJSON.Load(AStream : TStream);
var
  r : TzsJSONReader;
begin
  Self.Clear();
  r := TzsJSONReader.Create(AStream);
  try
    if not r.Read() then
      raise Exception.Create('Не получается прочитать JSON');

    case r.TokenType of
      ttStartObject : Self.FItemType := zsObject;
      ttStartArray : Self.FItemType := zsArray;
      else
        raise Exception.Create('Неведомый JSON');
    end;

    LoadFromReader(r);
    if r.Read() then
      raise Exception.Create('Кааим-то образос получилось прочитить не весь JSON');
  finally
    r.Free();
  end;
end;

function TzsJSONItem.GetValue() : string;
begin
  Result := FValue;
end;

procedure TzsJSONItem.LoadFromReader(r : TzsJSONReader);
  function _tt2it(tt : TzsTokenType) : TzsItemType;
  begin
    case tt of
      ttNull : Result := zsNull;
      ttTrue, ttFalse : Result := zsBoolean;
      ttNumber : Result := zsNumber;
      ttString : Result := zsString;
      ttStartObject : Result := zsObject;
      ttStartArray : Result := zsArray;
      else
        raise Exception.Create('Фигня какая-то');
    end;
  end;
var
  itemName : string;
  newItem : TzsJSONItem;
begin
  while r.Read() do
  begin
    if (Self.ItemType = zsObject) and (r.TokenType = ttEndObject) then
      Break;
    if (Self.ItemType = zsArray) and (r.TokenType = ttEndArray) then
      break;

    if r.TokenType = ttPropertyName then
    begin
      itemName := r.GetString();
      continue;
    end;

    newItem := Vperde(_tt2it(r.TokenType));

    if Self.ItemType = zsObject then
      newItem.FName := itemName;

    if newItem.ItemType in [zsObject, zsArray] then
      newItem.LoadFromReader(r)
    else
      newItem.FValue := r.GetValue();
  end;
end;

function TzsJSONItem.GetAsBoolean(): Boolean;
begin
  Result := FValue = 'true';
end;


procedure TzsJSONItem.SetAsBoolean(const b: Boolean);
begin
  if b then
    Self.FValue := 'true'
  else
    Self.FValue := 'false';
end;

function TzsJSONItem.Vperde(AItemType : TzsItemType) : TzsJSONItem;
begin
  Result := TzsJSONItem.Create();
  Result.FItemType := AItemType;
  Self.FItems.Add(Result);
  Result.FOwner := Self;
end;

function TzsJSON.ToString(AIdent : Integer = 0) : string;
var
  w : TzsJSONWriter;
  ss : TStringStream;
begin
  w := nil;
  ss := TStringStream.Create('');
  try
    w := TzsJSONWriter.Create(ss, AIdent);
    Self.Export2Writer(w);
    Result := ss.DataString;
  finally
    w.Free();
    ss.Free();
  end;
end;

{ TzsJSONWriter }

constructor TzsJSONWriter.Create(AStream : TStream; AIdent : Integer = 0);
begin
  FStream := AStream;
  FIdent := AIdent;

  SetLength(FStack, 200);
  FTop := -1;
  PushStack(ttNone);
end;

destructor TzsJSONWriter.Destroy();
begin
  SetLength(FStack, 0);
  inherited;
end;

function TzsJSONWriter.PeekStack() : TzsTokenType;
begin
  case FStack[FTop] and $0F of
    0 : Result := ttNone;
    1 : Result := ttStartObject;
    2 : Result := ttStartArray;
    else
      raise Exception.Create('Неведомая штука в стеке');
  end;

end;

function TzsJSONWriter.PopStack() : TzsTokenType;
begin
  if FTop <= 0 then
    raise Exception.Create('Отрицательные уровни вложенности не поддерживаются в бесплатной версии');

  CheckValueNeeded(False);

  if FIdent > 0 then
    Write(#13#10);

  Dec(FTop);
  WriteIdent();
  Result := PeekStack();
end;

procedure TzsJSONWriter.PushStack(const tt : TzsTokenType);
var
  ttCurrent : TzsTokenType;
begin
  if (FTop = 0) and HasItems then
    raise Exception.Create('Многокорневые объекты не поддерживаются в бесплатной версии');

  ttCurrent := PeekStack();

  CheckValueNeeded((FTop > 0) and (ttCurrent = ttStartObject));

  if (ttCurrent = ttStartArray) then
  begin
    if HasItems then
      Write(',');
    if FIdent > 0 then
      Write(''#13#10);
    WriteIdent();
  end;

  HasItems := True;

  Inc(FTop);

  if FTop >= Length(FStack) then
    SetLength(FStack, FTop + 30);


  ValueNeeded := False;

  case tt of
    ttNone : FStack[FTop] := 0;
    ttStartObject : FStack[FTop] := 1;
    ttStartArray : FStack[FTop] := 2;
    else
      raise Exception.Create('Попытка впихнуть невпихуемое в стек');
  end;
end;

procedure TzsJSONWriter.WriteStartObject();
begin
  PushStack(ttStartObject);
  Write('{');
end;

procedure TzsJSONWriter.WriteEndObject();
begin
  PopStack();
  Write('}');
end;

procedure TzsJSONWriter.WriteStartArray();
begin
  Write('[');
  PushStack(ttStartArray);
end;

procedure TzsJSONWriter.WriteEndArray();
begin
  PopStack();
  Write(']');
end;

procedure TzsJSONWriter.Write(const s : string);
begin
  if s <> '' then
    FStream.Write(PChar(@s[1])^, Length(s));
end;

procedure TzsJSONWriter.WriteStringValue(const AName, AValue : string);
begin
  WriteRawNamedValue(AName, TzsJSON.EncodeString(AValue));
end;

procedure TzsJSONWriter.WriteString(const AValue : string);
begin
  WriteRawValue(TzsJSON.EncodeString(AValue));
end;

procedure TzsJSONWriter.WriteNumericValue(const AName : string; const AValue : Double; ADecimalCnt : Integer);
begin
  WritePropertyName(AName);
  WriteNumeric(AValue, ADecimalCnt);
end;

procedure TzsJSONWriter.WriteNumericValue(const AName : string; const AValue : Double);
begin
  WritePropertyName(AName);
  WriteNumeric(AValue);
end;

procedure TzsJSONWriter.WriteNumericValue(const AName : string; const AValue : Integer);
begin
  WritePropertyName(AName);
  WriteNumeric(AValue);
end;

procedure TzsJSONWriter.WriteNumeric(const AValue : Double);
begin
  WriteRawValue(Format('%f', [AValue], zbsettings))
end;

procedure TzsJSONWriter.WriteNumeric(const AValue : Integer);
begin
  WriteRawValue(IntToStr(AValue));
end;

procedure TzsJSONWriter.WriteNumeric(const AValue : Double; ADecimalCnt : Integer);
begin
  if ADecimalCnt >= 0 then
    WriteRawValue(Format('%.' + IntToStr(ADecimalCnt) + 'f', [AValue], zbsettings))
  else
    raise Exception.Create('Отрицательное количество десятичных знаков запрещено в бесплатной версии');
end;

procedure TzsJSONWriter.WriteNullValue(const AName : string);
begin
  WritePropertyName(AName);
  Write('null');
end;

procedure TzsJSONWriter.WriteNull();
begin
  WriteRawValue('null');
end;

procedure TzsJSONWriter.WriteBooleanValue(const AName : string; const AValue : Boolean);
begin
  WritePropertyName(AName);
  WriteBoolean(AValue);
end;

procedure TzsJSONWriter.WriteBoolean(const AValue : Boolean);
begin
  if AValue then
    WriteRawValue('true')
  else
    WriteRawValue('false');
end;

procedure TzsJSONWriter.WritePropertyName(const AName : string);
begin
  CheckAllowProperty();

  CheckValueNeeded(False);
  WritePreStr();

  if FIdent > 0 then
    Self.Write('"' + AName + '": ')
  else
    Self.Write('"' + AName + '":');

  ValueNeeded := True;
end;

procedure TzsJSONWriter.WritePreStr();
begin
  if HasItems and (not ValueNeeded) then
    Write(',');

  if not ValueNeeded then
  begin
    if FIdent > 0 then
      Write(''#13#10);
    WriteIdent();
  end;
end;

procedure TzsJSONWriter.WriteIdent();
var
  i : Integer;
  c : Char;
begin
  c := ' ';
  if Self.FIdent > 0 then
    for i := 1 to (FIdent * FTop) do
      FStream.Write(c, 1);
end;

procedure TzsJSONWriter.CheckValueNeeded(const b : Boolean);
begin
  if b = Self.ValueNeeded then
    Exit;

  if Self.ValueNeeded then
    raise Exception.Create('У текущего свойства не установлено значение')
  else
    raise Exception.Create('Не установлено название свойства');
end;

procedure TzsJSONWriter.CheckAllowProperty();
begin
  if PeekStack() <> ttStartObject then
    raise Exception.Create('Название свойства применимо только для объекта');
end;

procedure TzsJSONWriter.WriteRawNamedValue(const AName, AValue : string);
begin
  WritePropertyName(AName);
  WriteRawValue(AValue);
end;

procedure TzsJSONWriter.WriteRawValue(const AValue : string);
begin
  case PeekStack() of
    ttStartObject :
      begin
        CheckValueNeeded(True);
        WritePreStr();
        Write(AValue);
        ValueNeeded := False;
      end;
    ttStartArray :
      begin
        WritePreStr();
        Write(AValue);

      end;
    else
      raise Exception.Create('Нелья записать значение в никуда');
  end;
  HasItems := True;
end;

function TzsJSONWriter.GetHasItems() : Boolean;
begin
  Result := (FStack[FTop] and $10) <> 0;
end;

procedure TzsJSONWriter.SetHasItems(const Value : Boolean);
begin
  if Value then
    FStack[FTop] := FStack[FTop] or $10
  else
    FStack[FTop] := FStack[FTop] and $EF;
end;

function TzsJSONWriter.GetValueNeeded() : Boolean;
begin
  Result := (FStack[FTop] and $20) <> 0;
end;

procedure TzsJSONWriter.SetValueNeeded(const Value : Boolean);
begin
  if Value then
    FStack[FTop] := FStack[FTop] or $20
  else
    FStack[FTop] := FStack[FTop] and $DF;
end;

function TzsJSONItem.GetAsDateTime(): TDateTime;
begin
  Result := TzsJSON.DecodeDateTime(Self.FValue);
end;

procedure TzsJSONItem.SetAsDateTime(const dt: TDateTime);
begin
  Self.FValue := TzsJSON.EncodeDateTime(dt);
end;

function TzsJSONItem.GetAsFloat(): Extended;
begin
  Result := StrToFloat(FValue, zbsettings);
end;

procedure TzsJSONItem.SetAsFloat(const f: Extended);
begin
  FValue := FloatToStr(f, zbsettings);
end;

procedure TzsJSONItem.SetAsFloat(const f: Extended; const digits: Integer);
begin
  FValue := FloatToStrF(f, ffFixed, 18, digits, zbsettings);
end;

function TzsJSONItem.GetAsInt(): Integer;
begin
  Result := StrToInt(FValue);
end;

procedure TzsJSONItem.SetAsInt(const n: Integer);
begin
  FValue := IntToStr(n);
end;

function TzsJSONItem.GetAsInt64(): Int64;
begin
  Result := StrToInt64(FValue);
end;

procedure TzsJSONItem.SetAsInt64(const n: Int64);
begin
  FValue := IntToStr(n);
end;

initialization
  GetLocaleFormatSettings($0409, zbsettings);
  zbsettings.DecimalSeparator := '.';

end.


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

  TzsItemType = (zsString, zsNumber, zsObject, zsArray, zsNull, zsTrue, zsFalse);

  TzsJSONItem = class
  private
    FOwner : TzsJSONItem;
    FName : string;
    FItemType : TzsItemType;
    FItems : TList;
    FValue : string;

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
  end;

  TzsJSON = class(TzsJSONItem)
  public
    procedure Load(AStream : TStream);
  end;

implementation

{ TzsJSONReader }

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
      ttTrue : Result := zsTrue;
      ttFalse : Result := zsFalse;
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

function TzsJSONItem.Vperde(AItemType : TzsItemType) : TzsJSONItem;
begin
  Result := TzsJSONItem.Create();
  Result.FItemType := AItemType;
  Self.FItems.Add(Result);
  Result.FOwner := Self;
end;

end.


unit fMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TfmMain = class(TForm)
    Button1 : TButton;
    Button2 : TButton;
    Memo1 : TMemo;
    Button3: TButton;
    procedure Button1Click(Sender : TObject);
    procedure Button2Click(Sender : TObject);
    procedure FormCreate(Sender: TObject);
    procedure Button3Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  fmMain : TfmMain;

implementation

uses
  Unit1,
  uLkJSON,
  zsJSON,
  DateUtils;

{$R *.dfm}

procedure TfmMain.Button1Click(Sender : TObject);
begin
  with TForm1.Create(nil) do
  try
    ShowModal();
  finally
    Free();
  end;
end;

procedure TfmMain.Button2Click(Sender : TObject);
var
  ident : Integer;

  function _SS() : string;
  var
    i : Integer;
  begin
    Result := '';
    for i := 1 to ident do
      Result := Result + '  ';
  end;

  procedure _Log(s : string);
  begin
    if Self <> nil then
      Exit;
    Memo1.Lines.Add(_SS() + s);
  end;

var
  fs : TFileStream;
  zs : TzsJSONReader;
  ss : TStringStream;
  s : string;
  dt : TDateTime;
begin
  ident := 0;
  ss := nil;
  fs := TFileStream.Create('d:\_SSD\piupiu.json', fmOpenRead);
  try
    ss := TStringStream.Create('');
    ss.CopyFrom(fs, fs.Size);
    s := ss.DataString;
  finally
    fs.Free();
    ss.Free();
  end;

  Memo1.Clear();
  dt := Now();
  zs := TzsJSONReader.Create(s);
  try
    while zs.Read() do
    begin
      if zs.TokenType = ttStartObject then
      begin
        _Log('{');
        Inc(ident);
      end
      else if zs.TokenType = ttEndObject then
      begin
        Dec(ident);
        _Log(']');
      end
      else if zs.TokenType = ttPropertyName then
        _Log('"' + zs.GetString() + '" : ')
      else if zs.TokenType = ttStartArray then
      begin
        _Log('[');
        Inc(ident);
      end
      else if zs.TokenType = ttEndArray then
      begin
        Dec(ident);
        _Log(']')
      end
      else if zs.TokenType <> ttNone then
      begin
        _Log(zs.GetValue());
      end

    end;

  finally
    zs.Free();
  end;
  Memo1.Lines.Add('Готово!');
  Memo1.Lines.Add(IntToStr(MilliSecondsBetween(dt, Now()) ));
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
  Left := -1300;
end;

procedure TfmMain.Button3Click(Sender: TObject);
var
  js : TlkJSONobject;
  fs : TFileStream;
  ss : TStringStream;
  s : string;
  dt : TDateTime;
begin
  ss := nil;
  fs := TFileStream.Create('d:\_SSD\piupiu.json', fmOpenRead);
  try
    ss := TStringStream.Create('');
    ss.CopyFrom(fs, fs.Size);
    s := ss.DataString;
  finally
    fs.Free();
    ss.Free();
  end;
  Memo1.Clear();
  dt := Now();
  js := TlkJSON.ParseText(s) as TlkJSONobject;
  js.Free();

  Memo1.Lines.Add('Фсё');
  Memo1.Lines.Add(IntToStr(MilliSecondsBetween(dt, Now()) ));
end;

end.


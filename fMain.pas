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
    Button3 : TButton;
    Button4 : TButton;
    procedure Button1Click(Sender : TObject);
    procedure Button2Click(Sender : TObject);
    procedure FormCreate(Sender : TObject);
    procedure Button4Click(Sender : TObject);
    procedure Button3Click(Sender : TObject);
  private
  public
  end;

var
  fmMain : TfmMain;

implementation

uses
  Unit1,
  //uLkJSON,
  zsJSON,
  SynCrossPlatformJSON,
  DateUtils;

{$R *.dfm}

procedure TfmMain.Button1Click(Sender : TObject);
begin
  ShowMessage(FloatToStrF(123.345, ffFixed, 18, 4));
end;

procedure TfmMain.Button2Click(Sender : TObject);
var
  zs : TzsJSON;
  fs : TFileStream;
  //dt, dt2 : TDateTime;
  fn : string;
  ss : TStringStream;
  w : TzsJSONWriter;
begin
  fn := 'd:\_SSD\piupiu10.json';
  //fn := 'D:\_WORK\aa.json';
  Memo1.Clear();
  //dt := Now();
  zs := nil;
  fs := TFileStream.Create(fn, fmOpenRead);

  ss := nil;
  w := nil;
  try
    zs := TzsJSON.Create();
    zs.Load(fs);
    //dt := Now() - dt;
    //dt2 := Now();
    if zs.ToString(2) = 'qew' then
      Caption := 'qwe';
    // dt2 := Now() - dt2;
    Memo1.Lines.Text := zs.ToString(2);
    if Self = nil then
    begin
      ss := TStringStream.Create('');

      w := TzsJSONWriter.Create(ss, 2);
      w.WriteStartObject();
      w.WriteStringValue('PersonId', '100500');
      w.WriteStringValue('HuersonId', 'asdaswd$2342');
      w.WriteEndObject();
      Memo1.Lines.Text := ss.DataString;
    end;
  finally
    w.Free();
    ss.Free();
    fs.Free();
    zs.Free();
  end;

  (*
  Memo1.Lines.Add('Фсё');
  Memo1.Lines.Add(IntToStr(MilliSecondsBetween(0, dt)));
  Memo1.Lines.Add(IntToStr(MilliSecondsBetween(0, dt2)));
  (**)
end;

procedure TfmMain.FormCreate(Sender : TObject);
begin
//  Left := -1300;
end;

procedure TfmMain.Button4Click(Sender : TObject);
var
  s : string;
  dt : TDateTime;
begin
  s := '2021-05-31 11:22:45';
  dt := TzsJSON.DecodeDateTime(s); //Iso8601ToDateTime(s);
  s := TzsJSON.EncodeDateTime(dt); // FormatDateTime('dd"."mm"."yyyy hh":"nn":"ss', dt);
  ShowMessage(s);
end;

procedure TfmMain.Button3Click(Sender : TObject);
var
  s : string;
begin
  s := 'Превед'#13#10'"кросафчег'#3'!"';
  s := TzsJSON.EncodeString(s);
  ShowMessage(s);
end;

end.


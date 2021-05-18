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
  //uLkJSON,
  zsJSON,
  SynCrossPlatformJSON,
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
  zs : TzsJSON;
  fs : TFileStream;
  dt : TDateTime;
begin
  Memo1.Clear();
  dt := Now();
  zs := nil;
  fs := TFileStream.Create('d:\_SSD\piupiu10000.json', fmOpenRead);
  try
    zs := TzsJSON.Create();
    zs.Load(fs);
    dt := Now() - dt;
    if zs.ItemType = zsArray then
    begin
      Memo1.Lines.Add(Format('Массив на %d штук', [zs.Count]));
      Memo1.Lines.Add(zs.Items[0]['Comunication'].Items[0]['Value'].Value);
    end;
  finally
    fs.Free();
    zs.Free();
  end;

  Memo1.Lines.Add('Фсё');
  Memo1.Lines.Add(IntToStr(MilliSecondsBetween(0, dt)));
end;

procedure TfmMain.FormCreate(Sender : TObject);
begin
  Left := -1300;
end;

end.


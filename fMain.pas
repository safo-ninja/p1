unit fMain;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TfmMain = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  fmMain: TfmMain;

implementation

uses Unit1;

{$R *.dfm}

procedure TfmMain.Button1Click(Sender: TObject);
begin
  with TForm1.Create(nil) do
  try
    ShowModal();
  finally
    Free();
  end;
end;

end.

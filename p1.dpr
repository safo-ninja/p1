program p1;

uses
  Forms,
  fMain in 'fMain.pas' {fmMain},
  Unit1 in 'Unit1.pas' {Form1},
  zsJSON in 'zsJSON.pas',
  SynCrossPlatformJSON in '..\..\!\mORMot\CrossPlatform\SynCrossPlatformJSON.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfmMain, fmMain);
  Application.Run;
end.

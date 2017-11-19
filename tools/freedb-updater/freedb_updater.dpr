program freedb_updater;

uses
  Forms,
  mainform in 'mainform.pas' {Form1};

{$R *.RES}

begin
  Application.Initialize;
  Application.Title := 'freedb-updater';
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.

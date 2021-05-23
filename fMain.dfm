object fmMain: TfmMain
  Left = 342
  Top = 135
  Width = 1305
  Height = 675
  Caption = #1047#1072#1075#1086#1083#1086#1074#1086#1082'2'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 13
  object Button1: TButton
    Left = 20
    Top = 50
    Width = 75
    Height = 25
    Caption = 'Button1'
    TabOrder = 1
    OnClick = Button1Click
  end
  object Button2: TButton
    Left = 20
    Top = 24
    Width = 75
    Height = 25
    Caption = 'Button2'
    TabOrder = 0
    OnClick = Button2Click
  end
  object Memo1: TMemo
    Left = 120
    Top = 0
    Width = 1169
    Height = 636
    Align = alRight
    Lines.Strings = (
      'Memo1')
    TabOrder = 2
  end
  object Button3: TButton
    Left = 38
    Top = 168
    Width = 75
    Height = 25
    Caption = 'Button3'
    TabOrder = 3
    OnClick = Button3Click
  end
  object Button4: TButton
    Left = 26
    Top = 236
    Width = 75
    Height = 25
    Caption = 'Button4'
    TabOrder = 4
    OnClick = Button4Click
  end
end

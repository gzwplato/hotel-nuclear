{
  Copyright 2014-2014 Michalis Kamburelis.

  This file is part of "Hotel Nuclear".

  "Hotel Nuclear" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Hotel Nuclear" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Playing the game. }
unit GamePlay;

interface

uses CastleVectors, CastleSceneManager, CastlePlayer, CastleLevels, CastleColors,
  CastleKeysMouse,
  GamePossessed;

var
  SceneManager: TGameSceneManager;
  DebugSpeed: boolean = false;
  Player: TPlayer;
  DesktopCamera: boolean =
    {$ifdef ANDROID} false {$else}
    {$ifdef iOS}     false {$else}
                     true {$endif} {$endif};

procedure GameBegin;
procedure GameUpdate(const SecondsPassed: Single);

function GetPossessed: TPossessed;
procedure SetPossessed(const Value: TPossessed);
property Possessed: TPossessed read GetPossessed write SetPossessed;

implementation

uses SysUtils,
  CastleUIControls, CastleRectangles, CastleGLUtils, X3DNodes, CastleLog,
  CastleUtils, CastleRenderer, CastleWindowTouch, CastleControls,
  CastleSoundEngine, CastleCreatures, CastleResources, CastleGameNotifications,
  GameWindow, GameScene, GameMap, GameDoorsRooms, GameSound;

var
  FPossessed: TPossessed;

function GetPossessed: TPossessed;
begin
  Result := FPossessed;
end;

procedure SetPossessed(const Value: TPossessed);
{var
  NavInfo: TKambiNavigationInfoNode;
  HeadlightNode: TPointLightNode;}
begin
  if FPossessed <> Value then
  begin
    FPossessed := Value;
    if SceneManager <> nil then
    begin
      { Better not, confuses color of doors:
      NavInfo := SceneManager.MainScene.NavigationInfoStack.Top as TKambiNavigationInfoNode;
      HeadlightNode :=  NavInfo.FdHeadLightNode.Value as TPointLightNode;
      HeadlightNode.FdColor.Send(Vector3SingleCut(PossessedColor[Value]));
      }
      Notifications.Color := PossessedColor[Value];
      SoundEngine.Sound(stSquish);
    end;
  end;
end;

{ TGame2DControls ------------------------------------------------------------ }

const
  UIMargin = 10;

type
  TGame2DControls = class(TUIControl)
  public
    procedure Render; override;
  end;

procedure TGame2DControls.Render;
const
  InventoryImageSize = 128;
const
  PossessedName: array [TPossessed] of string =
  ( 'immaterial ghost (not possessing anyone now)',
    'martian',
    'earthling' );
  PossessedNameShort: array [TPossessed] of string =
  ( 'ghost',
    'martian',
    'earthling' );
var
  R: TRectangle;
  LineNum, I, X, Y: Integer;
  Color: TCastleColor;
  S: string;
begin
  if Player.Dead then
    GLFadeRectangle(ContainerRect, Red, 1.0) else
    GLFadeRectangle(ContainerRect, Player.FadeOutColor, Player.FadeOutIntensity);

  Color := PossessedColor[Possessed];
  Color[3] := 0.9;
  R := Rectangle(UIMargin, ContainerHeight - UIMargin - 100, 40, 100);
  DrawRectangle(R.Grow(2), Vector4Single(1.0, 0.5, 0.5, 0.2));
  if not Player.Dead then
  begin
    R.Height := Clamped(Round(
      MapRange(Player.Life, 0, Player.MaxLife, 0, R.Height)), 0, R.Height);
    DrawRectangle(R, Color);
  end;

  LineNum := 1;

  UIFont.Print(R.Right + UIMargin, ContainerHeight - LineNum * (UIMargin + UIFont.RowHeight), Gray,
    Format('FPS: %f (real : %f)', [Window.Fps.FrameTime, Window.Fps.RealTime]));
  Inc(LineNum);

  UIFont.Print(R.Right + UIMargin, ContainerHeight - LineNum * (UIMargin + UIFont.RowHeight),
    Color, PossessedName[Possessed]);
  Inc(LineNum);

  { note: show this even when Player.Dead, since that's where you usually have time to read this... }
  if (CurrentRoom <> nil) and
     (CurrentRoom.Ownership <> Possessed) then
  begin
    UIFont.Print(R.Right + UIMargin, ContainerHeight - LineNum * (UIMargin + UIFont.RowHeight),
      Color, Format('You entered room owned by "%s" as "%s", the air is not breathable! You''re dying!',
      [PossessedNameShort[CurrentRoom.Ownership], PossessedNameShort[Possessed] ]));
    Inc(LineNum);
  end;

  Notifications.PositionX := R.Right + UIMargin;
  Notifications.PositionY := - (LineNum - 1) * (UIMargin + UIFont.RowHeight) - UIMargin;
  Inc(LineNum);

  Y := ContainerHeight - (LineNum - 1) * (UIMargin + UIFont.RowHeight) - InventoryImageSize;
  for I := 0 to Player.Inventory.Count - 1 do
  begin
    X := UIMargin + I * (InventoryImageSize + UIMargin);
    Player.Inventory[I].Resource.GLImage.Draw(X, Y);
    S := Player.Inventory[I].Resource.Caption;
    UIFontSmall.Print(X, Y - UIFontSmall.RowHeight, Color, S);
  end;
end;

var
  Game2DControls: TGame2DControls;

{ routines ------------------------------------------------------------------- }

var
  ResourceAlien, ResourceHuman: TWalkAttackCreatureResource;

procedure GameBegin;

  { Make sure to free and clear all stuff started during the game. }
  procedure GameEnd;
  begin
    { free 3D stuff (inside SceneManager) }
    FreeAndNil(Player);

    { free 2D stuff (including SceneManager and viewports) }
    FreeAndNil(SceneManager);

    Notifications.Exists := false;
  end;

begin
  GameEnd;

  SceneManager := Window.SceneManager;

  Player := TPlayer.Create(SceneManager);
  SceneManager.Items.Add(Player);
  SceneManager.Player := Player;

  Game2DControls := TGame2DControls.Create(SceneManager);
  Window.Controls.InsertFront(Game2DControls);

  { OpenGL context required from now on }

  SceneManager.LoadLevel('hotel');
  SetAttributes(SceneManager.MainScene.Attributes);

  SceneManager.Items.Add(CreateMap(SceneManager.Items, SceneManager));

  if DebugSpeed then
    Player.Camera.MoveSpeed := 10;

  if DesktopCamera then
  begin
    Player.Camera.MouseLook := true;
    Player.Camera.MouseDraggingHorizontalRotationSpeed := 0.5 / (Window.Dpi / DefaultDPI);
    Player.Camera.MouseDraggingVerticalRotationSpeed := 0;
    Window.TouchInterface := etciNone;
  end else
  begin
    Window.AutomaticWalkTouchCtl := etciCtlWalkCtlRotate;
    Window.AutomaticTouchInterface := true;
  end;

  ResourceAlien := Resources.FindName('Alien') as TWalkAttackCreatureResource;
  ResourceHuman := Resources.FindName('Human') as TWalkAttackCreatureResource;

  CurrentOpenDoor := nil;
  CurrentRoom := nil;
  Possessed := posGhost;

  Notifications.Color := PossessedColor[Possessed];
  Notifications.Clear;
  Notifications.CollectHistory := true;
  Notifications.Exists := true;
end;

procedure GameUpdate(const SecondsPassed: Single);
const
  LifeLossSpeed = 50.0; // very fast, since player should not be here
  LifeRegenerateSpeed = 10.0;
var
  Creature: TCreature;
  ClosestCreature: TCreature;
  I: Integer;
const
  DistanceToPossess = 3;
begin
  if not Player.Dead then
  begin
    ClosestCreature := nil;
    for I := 0 to SceneManager.Items.Count - 1 do
      if SceneManager.Items[I] is TCreature then
      begin
        Creature := SceneManager.Items[I] as TCreature;
        if (not Creature.Dead) and (
             (ClosestCreature = nil) or
             (PointsDistanceSqr(Creature.Position, Player.Position) <
              PointsDistanceSqr(ClosestCreature.Position, Player.Position)) ) then
          ClosestCreature := Creature;
     end;

    if (ClosestCreature <> nil) and
       (PointsDistanceSqr(ClosestCreature.Position, Player.Position) < Sqr(DistanceToPossess)) then
    begin
      if (ClosestCreature.Resource = ResourceAlien) and (Possessed <> posAlien) then
      begin
        ClosestCreature.Life := 0;
        Possessed := posAlien;
      end else
      if (ClosestCreature.Resource = ResourceHuman) and (Possessed <> posHuman) then
      begin
        ClosestCreature.Life := 0;
        Possessed := posHuman;
      end;
    end;

    if (CurrentRoom <> nil) and
       (CurrentRoom.Ownership <> Possessed) then
      Player.Life := Player.Life - SecondsPassed * LifeLossSpeed else
      Player.Life := Min(Player.MaxLife, Player.Life + SecondsPassed * LifeRegenerateSpeed);
  end;
end;

end.

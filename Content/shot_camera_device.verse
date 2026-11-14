using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/SpatialMath }
using { /Verse.org/SceneGraph }

# LANE A OWNS THIS FILE.
#
# One camera rig. Place one of these wherever a camera films, and point the
# device's forward axis (the red arrow) along the shot. The Director turns it on and off.
# All distances are in centimetres. 100 = one metre; a floor tile is 512.
shot_camera_device := class(creative_device):

    # Name of the set this camera belongs to, shown on the call sheet.
    @editable
    SetName:string = "Backlot"

    @editable
    CameraType:shot_camera_type = shot_camera_type.Static

    # Score multiplier for being in this shot: 1.0, 2.0 or 3.0.
    @editable
    ShotValue:float = 1.0

    # Full width of the view, in degrees.
    @editable
    HorizontalFOV:float = 60.0

    # Full height of the view, in degrees.
    @editable
    VerticalFOV:float = 40.0

    # Actors closer to the lens than this are not in frame.
    @editable
    NearRange:float = 150.0

    # Actors farther from the lens than this are not in frame.
    @editable
    FarRange:float = 2000.0

    # Optional. If set, the frame follows this prop instead of the device, so
    # moving the prop (pan, dolly) moves the frame.
    @editable
    LensProp:?creative_prop = false

    # If on, actors hidden behind something solid do not score.
    @editable
    CheckWalls:logic = true

    # The wall check stops this far short of the actor, so it does not hit the actor.
    @editable
    WallCheckMargin:float = 80.0

    # The wall check ignores anything this close to the lens (the camera prop itself).
    @editable
    LensClearance:float = 60.0

    var Rolling:logic = false

    # Set by the Director. Do not edit from other lanes.
    # True from the call sheet until "Cut!".
    var Reserved:logic = false
    # Extra multiplier from the act, take two or the hero shot.
    var ValueBoost:float = 1.0
    # The shot this camera is announced for or filming, if any.
    var CurrentShot:?shot_info = false

    StartRolling():void =
        set Rolling = true

    StopRolling():void =
        set Rolling = false

    # Succeeds while the camera is rolling.
    IsRolling()<transacts><decides>:void =
        Rolling?

    # Where the lens is and which way it faces right now.
    GetLensTransform()<transacts>:transform =
        if (Prop := LensProp?, Prop.IsValid[]):
            Prop.GetTransform()
        else:
            GetTransform()

    # Succeeds if Position is inside the frame, and returns how far in front of
    # the lens it is. Fails if Position is outside the frame.
    # This does not check for walls; see visibility.
    GetFrameDepth(Position:vector3)<transacts><decides>:float =
        Lens := GetLensTransform()
        Delta := Position - Lens.Translation
        Depth := DotProduct(Delta, Lens.Rotation.GetLocalForward())
        Depth >= NearRange
        Depth <= FarRange
        Side := Abs(DotProduct(Delta, Lens.Rotation.GetLocalRight()))
        Side <= Depth * Tan(DegreesToRadians(HorizontalFOV * 0.5))
        Height := Abs(DotProduct(Delta, Lens.Rotation.GetLocalUp()))
        Height <= Depth * Tan(DegreesToRadians(VerticalFOV * 0.5))
        Depth

    # 2.0 in the nearest third of the frame, 1.0 in the farthest third, sliding between.
    GetForegroundMultiplier(Depth:float)<transacts>:float =
        Span := FarRange - NearRange
        if (Span <= 0.0):
            1.0
        else:
            T := (Depth - NearRange) / Span
            if (T <= 0.3333):
                2.0
            else if (T >= 0.6667):
                1.0
            else:
                2.0 - (T - 0.3333) / 0.3334

    # Counts solid things between the lens and Target. 0 means a clear view.
    # Ignore lists entities that never block the view (the actors themselves).
    # Always 0 when CheckWalls is off.
    CountBlockers(Target:vector3, Ignore:[]entity)<transacts>:int =
        Lens := GetLensTransform().Translation
        Delta := Target - Lens
        Range := Delta.Length()
        if (CheckWalls?, Range > WallCheckMargin, SimEntity := GetSimulationEntity[]):
            Displacement := (Delta / Range) * (Range - WallCheckMargin)
            Start := transform:
                Translation := Lens
                Rotation := IdentityRotation()
                Scale := vector3{X := 1.0, Y := 1.0, Z := 1.0}
            Ray := collision_point{CollisionProfile := CollisionProfiles.VisibilityOverlapAll}
            var Count:int = 0
            for (Hit : SimEntity.FindSweepHits(FromVector3(Displacement), FromTransform(Start), Ray)):
                if (Hit.SourceHitDistance > LensClearance, not IsIgnoredEntity[Hit.TargetComponent.Entity, Ignore]):
                    set Count += 1
            Count
        else:
            0

    # Succeeds if HitEntity, or anything it is attached under, is in Ignore.
    IsIgnoredEntity(HitEntity:entity, Ignore:[]entity)<transacts><decides>:void =
        var Current:?entity = option{HitEntity}
        var Found:logic = false
        for (Step := 0..4, Candidate := Current?):
            if (Ignore.Find[Candidate]):
                set Found = true
            set Current = option{Candidate.GetParent[]}
        Found?

    # Describes this camera as a shot, for the shared events.
    MakeShotInfo(Duration:float, CallSheetSeconds:float, IsTakeTwo:logic, IsHeroShot:logic):shot_info =
        shot_info:
            Camera := Self
            SetName := SetName
            Value := GetCurrentValue()
            Duration := Duration
            CallSheetSeconds := CallSheetSeconds
            IsTakeTwo := IsTakeTwo
            IsHeroShot := IsHeroShot

    # The shot's score multiplier right now: the camera's own value times the Director's boost.
    GetCurrentValue()<transacts>:float =
        ShotValue * ValueBoost

using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }
using { /Verse.org/Random }
using { /UnrealEngine.com/Temporary/Diagnostics }

# LANE A OWNS THIS FILE.
#
# The Director. Exactly one of these is placed in the level. It runs the match:
# casting call, three acts of shots, the cuts between acts, the final hero shot
# and the billing. It publishes the shared events every other lane listens to.
#
# All times are in seconds.
director_device := class(creative_device):

    # The shared events. Other lanes: Director.Events.<Event>.Subscribe(...)
    Events:show_events = show_events{}

    # Every camera rig in the level.
    @editable
    Cameras:[]shot_camera_device = array{}

    # Optional. Activated for the winner after the final billing.
    @editable
    EndGameDevice:?end_game_device = false

    # ---- Match timing ----

    # Time in the hub before Act 1.
    @editable
    CastingCallSeconds:float = 20.0

    # Length of Act 1, Act 2 and Act 3. Act 3 is followed by the hero shot.
    @editable
    ActSeconds:[]float = array{90.0, 90.0, 40.0}

    # Pause after Act 1 and Act 2, while the Director makes cuts.
    @editable
    IntermissionSeconds:float = 10.0

    # How long the final billing shows before the game ends.
    @editable
    BillingSeconds:float = 15.0

    # ---- Shots ----

    # Warning time between naming a shot and the camera rolling.
    @editable
    CallSheetSeconds:float = 6.0

    # Each shot rolls for a random time between these two.
    @editable
    ShotSecondsMin:float = 15.0
    @editable
    ShotSecondsMax:float = 20.0

    # How many cameras can be live at once in Act 1, 2 and 3. At most 3.
    @editable
    ActLiveCameras:[]int = array{1, 2, 2}

    # Every shot's value is multiplied by this in Act 1, 2 and 3.
    @editable
    ActValueBoost:[]float = array{1.0, 1.5, 2.0}

    # ---- Take two ----

    @editable
    TakeTwoEnabled:logic = true

    # Chance, after each shot, that the Director re-runs it. At most once per act.
    @editable
    TakeTwoChance:float = 0.35

    # A take two is announced faster and is worth this much more.
    @editable
    TakeTwoCallSheetSeconds:float = 3.0
    @editable
    TakeTwoBoost:float = 2.0

    # ---- Hero shot ----

    # The single last shot of the match.
    @editable
    HeroShotSeconds:float = 20.0
    @editable
    HeroShotBoost:float = 3.0

    # ---- Cuts ----

    @editable
    CutsEnabled:logic = true

    # With fewer actors than this still in the film, nobody is cut.
    @editable
    MinActorsForCuts:int = 6

    # Share of the remaining actors cut after Act 1 and after Act 2.
    @editable
    CutFractions:[]float = array{0.25, 0.5}

    # ---- Testing aids ----

    # Skip the match and roll every camera for the whole session.
    @editable
    DebugRollAllCameras:logic = false

    # Print the Director's calls on screen until Lane B's HUD shows them.
    @editable
    DebugPrintCalls:logic = true

    var CutActors:[agent]logic = map{}
    var LatestBilling:[]billing_entry = array{}
    var TakeTwoUsed:logic = false

    # Succeeds if the Director has cut this actor from the film.
    IsCut(Agent:agent)<transacts><decides>:void =
        CutActors[Agent]?

    OnBegin<override>()<suspends>:void =
        Events.BillingChangedEvent.Subscribe(OnBillingChanged)
        if (DebugRollAllCameras?):
            for (Camera : Cameras):
                Camera.StartRolling()
                Events.ShotStartedEvent.Signal(Camera.MakeShotInfo(0.0, 0.0, false, false))
            Say("Director: debug mode, {Cameras.Length} camera(s) rolling")
        else:
            RunMatch()

    OnBillingChanged(Billing:[]billing_entry):void =
        set LatestBilling = Billing

    Say(Text:string):void =
        if (DebugPrintCalls?):
            Print(Text)

    RunMatch()<suspends>:void =
        Say("Director: casting call. Places in {CastingCallSeconds} seconds")
        Sleep(CastingCallSeconds)
        for (Act := 1..3):
            RunAct(Act)
            if (Act < 3):
                MakeCuts(Act)
                Sleep(IntermissionSeconds)
        Events.MatchEndedEvent.Signal(LatestBilling)
        Say("Director: that's a wrap!")
        Sleep(BillingSeconds)
        if (Device := EndGameDevice?, Winner := LatestBilling[0]):
            Device.Activate(Winner.Actor)

    RunAct(Act:int)<suspends>:void =
        set TakeTwoUsed = false
        Events.ActStartedEvent.Signal(Act)
        Say("Director: Act {Act}")
        Length := if (Seconds := ActSeconds[Act - 1]) then Seconds else 60.0
        Wanted := if (Count := ActLiveCameras[Act - 1]) then Count else 1
        Lanes := Min(Wanted, Cameras.Length)
        Boost := GetActBoost(Act)
        race:
            Sleep(Length)
            sync:
                RunLane(0, Lanes, Boost)
                RunLane(1, Lanes, Boost)
                RunLane(2, Lanes, Boost)
        # The act timer may have interrupted shots mid-way.
        EndAllShots()
        if (Act = 3):
            RunHeroShot(Boost)
        Events.ActEndedEvent.Signal(Act)

    GetActBoost(Act:int)<transacts>:float =
        if (Boost := ActValueBoost[Act - 1]):
            Boost
        else:
            1.0

    # One lane runs shots back to back. Several lanes means several live cameras.
    RunLane(Index:int, Lanes:int, Boost:float)<suspends>:void =
        if (Index >= Lanes):
            Sleep(Inf)
        # Stagger the lanes so shots do not all start and stop together.
        Sleep(Index * (CallSheetSeconds + ShotSecondsMin) * 0.5)
        loop:
            if (Camera := PickCamera[]):
                RunShot(Camera, Boost, CallSheetSeconds, false, false)
                if (TakeTwoEnabled?, not TakeTwoUsed?, GetRandomFloat(0.0, 1.0) < TakeTwoChance):
                    set TakeTwoUsed = true
                    RunShot(Camera, Boost * TakeTwoBoost, TakeTwoCallSheetSeconds, true, false)
            else:
                Sleep(1.0)

    # A random camera that is not already announced or rolling.
    PickCamera()<transacts><decides>:shot_camera_device =
        Free := for (Camera : Cameras, not Camera.Reserved?):
            Camera
        Free.Length > 0
        Free[GetRandomInt(0, Free.Length - 1)]

    RunShot(Camera:shot_camera_device, Boost:float, CallSheet:float, IsTakeTwo:logic, IsHeroShot:logic)<suspends>:void =
        set Camera.Reserved = true
        set Camera.ValueBoost = Boost
        Duration := if (IsHeroShot?) then HeroShotSeconds else GetRandomFloat(ShotSecondsMin, ShotSecondsMax)
        Shot := Camera.MakeShotInfo(Duration, CallSheet, IsTakeTwo, IsHeroShot)
        set Camera.CurrentShot = option{Shot}
        Events.ShotAnnouncedEvent.Signal(Shot)
        if (IsHeroShot?):
            Say("Director: FINAL SHOT on the {Shot.SetName} set, x{Shot.Value}")
        else if (IsTakeTwo?):
            Say("Director: Take two! {Shot.SetName} set, x{Shot.Value}")
        else:
            Say("Director: rolling on the {Shot.SetName} set in {CallSheet} seconds, x{Shot.Value}")
        Sleep(CallSheet)
        Camera.StartRolling()
        Events.ShotStartedEvent.Signal(Shot)
        Say("Director: Action! ({Shot.SetName})")
        Sleep(Duration)
        EndShot(Camera)

    # "Cut!" Safe to call on a camera that is only announced, or idle.
    EndShot(Camera:shot_camera_device):void =
        if (Camera.Reserved?):
            Camera.StopRolling()
            if (Shot := Camera.CurrentShot?):
                Events.ShotEndedEvent.Signal(Shot)
                Say("Director: Cut! ({Shot.SetName})")
            set Camera.CurrentShot = false
            set Camera.ValueBoost = 1.0
            set Camera.Reserved = false

    EndAllShots():void =
        for (Camera : Cameras):
            EndShot(Camera)

    RunHeroShot(ActBoost:float)<suspends>:void =
        if (Camera := PickCamera[]):
            RunShot(Camera, ActBoost * HeroShotBoost, CallSheetSeconds, false, true)

    # Cuts the lowest-billed share of the actors still in the film.
    MakeCuts(Act:int):void =
        StillIn := for (Entry : LatestBilling, not IsCut[Entry.Actor]):
            Entry
        if:
            CutsEnabled?
            StillIn.Length >= MinActorsForCuts
            Fraction := CutFractions[Act - 1]
            Count := Floor[StillIn.Length * Fraction]
            Count > 0
        then:
            for (Index := (StillIn.Length - Count)..(StillIn.Length - 1), Entry := StillIn[Index]):
                if (set CutActors[Entry.Actor] = true) {}
                Events.ActorCutEvent.Signal(Entry.Actor)
            Say("Director: {Count} actor(s) cut from the film")
        else:
            Say("Director: nobody is cut")

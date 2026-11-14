using { /Fortnite.com/Devices }
using { /Fortnite.com/Characters }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# LANE A OWNS THIS FILE.
#
# Keeps every actor's score. Several times a second it checks each actor against
# each rolling camera and awards screen time:
#     points per second = Base x shot value x foreground x performance
# Exactly one of these is placed in the level.
# (Named screen_time_device because Fortnite already has a score_manager_device.)
screen_time_device := class(creative_device):

    @editable
    Director:director_device = director_device{}

    # Mutator zones covering the sets. They report who is emoting.
    @editable
    EmoteZones:[]mutator_zone_device = array{}

    @editable
    BasePointsPerSecond:float = 10.0

    # Seconds between scoring checks.
    @editable
    TickSeconds:float = 0.2

    # Score multiplier while emoting in frame.
    @editable
    EmoteMultiplier:float = 2.0

    # Testing aid: print scores on screen once a second while anyone is scoring.
    @editable
    DebugPrintScores:logic = true

    var Scores:[agent]float = map{}
    var Emoting:[agent]logic = map{}
    var BillingDirty:logic = false
    # Testing aid: blockers seen on the most recent hidden actor since the last print.
    var HiddenBlockers:int = 0

    OnBegin<override>()<suspends>:void =
        for (Zone : EmoteZones):
            Zone.AgentBeginsEmotingEvent.Subscribe(OnEmoteBegin)
            Zone.AgentEndsEmotingEvent.Subscribe(OnEmoteEnd)
        Director.Events.ActorCutEvent.Subscribe(OnActorCut)
        var SincePublish:float = 0.0
        loop:
            Sleep(TickSeconds)
            ScoreTick()
            set SincePublish += TickSeconds
            if (SincePublish >= 1.0):
                set SincePublish = 0.0
                PublishBilling()

    GetScore(Agent:agent)<transacts>:float =
        if (Score := Scores[Agent]):
            Score
        else:
            0.0

    IsEmoting(Agent:agent)<transacts><decides>:void =
        Emoting[Agent]?

    # Every actor, highest score first.
    GetBilling()<transacts>:[]billing_entry =
        var Result:[]billing_entry = array{}
        for (Agent : GetPlayspace().GetParticipants()):
            Score := GetScore(Agent)
            var InsertAt:int = Result.Length
            for (Index -> Existing : Result, Index < InsertAt, Score > Existing.Score):
                set InsertAt = Index
            Cut:logic = if (Director.IsCut[Agent]) then true else false
            if (Inserted := Result.Insert[InsertAt, array{billing_entry{Actor := Agent, Score := Score, IsCut := Cut}}]):
                set Result = Inserted
        Result

    # A cut changes the billing even if no score moved.
    OnActorCut(Agent:agent):void =
        set BillingDirty = true

    OnEmoteBegin(Agent:agent):void =
        if (set Emoting[Agent] = true) {}

    OnEmoteEnd(Agent:agent):void =
        if (set Emoting[Agent] = false) {}

    ScoreTick():void =
        # Actors never block each other's view, so the wall check ignores all of them.
        ActorEntities := for (Agent : GetPlayspace().GetParticipants(), Character := Agent.GetFortCharacter[], ActorEntity := Character.GetEntity[]):
            ActorEntity
        for:
            Agent : GetPlayspace().GetParticipants()
            Character := Agent.GetFortCharacter[]
            Character.IsActive[]
            # Cut actors are crew: they no longer score.
            not Director.IsCut[Agent]
        do:
            Position := Character.GetTransform().Translation
            # If an actor is in several frames at once, the best one counts.
            var BestRate:float = 0.0
            for:
                Camera : Director.Cameras
                Camera.IsRolling[]
                Depth := Camera.GetFrameDepth[Position]
            do:
                Blockers := Camera.CountBlockers(Position, ActorEntities)
                if (Blockers = 0):
                    Rate := Camera.GetCurrentValue() * Camera.GetForegroundMultiplier(Depth)
                    if (Rate > BestRate):
                        set BestRate = Rate
                else:
                    set HiddenBlockers = Blockers
            if (BestRate > 0.0):
                Performance := if (IsEmoting[Agent]) then EmoteMultiplier else 1.0
                Gained := BasePointsPerSecond * BestRate * Performance * TickSeconds
                if (set Scores[Agent] = GetScore(Agent) + Gained):
                    set BillingDirty = true

    PublishBilling():void =
        if (DebugPrintScores?, HiddenBlockers > 0):
            Print("In frame but hidden: {HiddenBlockers} thing(s) in the way")
        set HiddenBlockers = 0
        if (BillingDirty?):
            set BillingDirty = false
            Billing := GetBilling()
            Director.Events.BillingChangedEvent.Signal(Billing)
            if (DebugPrintScores?):
                for (Index -> Entry : Billing, Whole := Floor[Entry.Score]):
                    Print("Billing #{Index + 1}: {Whole} pts")

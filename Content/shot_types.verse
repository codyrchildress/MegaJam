using { /Fortnite.com/Devices }
using { /Verse.org/Simulation }

# ============================================================================
# LANE A OWNS THIS FILE. Other lanes: read it, build against it, do not edit it.
# Need a change? Ask Lane A.
#
# How to listen from another lane's device:
#     @editable Director:director_device = director_device{}
#     ...
#     Director.Events.ShotStartedEvent.Subscribe(OnShotStarted)
#     OnShotStarted(Shot:shot_info):void = ...
# ============================================================================

# The kinds of camera a shot can use.
shot_camera_type := enum:
    Static
    Pan
    Dolly
    CloseUp

# Everything a listener needs to know about one shot.
shot_info := class:
    # The camera rig filming this shot. Use its transform to place markers or visuals.
    Camera:shot_camera_device
    # Name of the set, for the call sheet ("Western", "Horror"...).
    SetName:string
    # Score multiplier of this shot: 1.0, 2.0 or 3.0.
    Value:float
    # How long the camera rolls, in seconds. 0.0 means until told otherwise.
    Duration:float
    # Seconds between the call sheet announcement and the camera rolling.
    CallSheetSeconds:float = 0.0
    # True when the Director is re-running the shot that just ended ("Take two!").
    IsTakeTwo:logic = false
    # True for the single final shot of the match.
    IsHeroShot:logic = false

# One line of the billing: an actor, their score, and whether the Director has cut them.
billing_entry := class:
    Actor:agent
    Score:float
    IsCut:logic = false

# The shared events. One instance lives on the director_device as `Events`.
show_events := class:
    # The call sheet has started: the Director named the next shot. The camera is not rolling yet.
    ShotAnnouncedEvent:event(shot_info) = event(shot_info){}
    # "Action!" The camera is rolling and actors in frame are scoring.
    ShotStartedEvent:event(shot_info) = event(shot_info){}
    # "Cut!" The camera stopped rolling.
    ShotEndedEvent:event(shot_info) = event(shot_info){}
    # An act began or ended. Payload is the act number: 1, 2 or 3.
    ActStartedEvent:event(int) = event(int){}
    ActEndedEvent:event(int) = event(int){}
    # The Director cut this actor from the film. They become crew and stop scoring.
    ActorCutEvent:event(agent) = event(agent){}
    # The billing changed. Payload is every actor, highest score first. Sent at most once a second.
    BillingChangedEvent:event([]billing_entry) = event([]billing_entry){}
    # The match is over. Payload is the final billing, winner first.
    MatchEndedEvent:event([]billing_entry) = event([]billing_entry){}

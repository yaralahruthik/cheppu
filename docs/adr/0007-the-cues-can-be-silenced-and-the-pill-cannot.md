---
status: accepted
---

# The Cues can be silenced, and the Pill cannot

`docs/product-experience.md` §3 asks for every state a user cares about to be unambiguous through at least two senses, and #10 asks for the Cues to be turnable off. Both are right, and they disagree: a user who has turned the Cues off knows the state of a Dictation through one sense.

Off wins, because the case for it is not comfort. Someone dictating notes in a meeting, a shared office, or next to a sleeping child has a laptop that chirps twice a sentence, and the only thing they can do about it is stop dictating. A dictation app that cannot be used quietly is one that is not used at all for half the day, and a Cue that must never be silenced makes §3 an argument for using something else.

What §3 is protecting is that the user is never left guessing, and the Pill alone is enough for that when the user can see it: it is up for the whole of a Dictation, it moves with the voice, and its two states differ in shape. The Cue is what carries the state when their eyes are elsewhere — which is exactly the case the meeting is not. So the sense that is dropped is the one whose value is lowest in the moment it is dropped in, and it is dropped by the user, deliberately, and given back with one click.

The Pill is not switchable, and is not to become so. Turning both off is an app that dictates in silence with no sign it is running, which is the outcome §4 rules out, and it is one setting away from a microphone the user has forgotten is open.

## Consequences

- The switch lives in front of the speakers (`Cues`), not in the machine. The core goes on deciding that a Dictation started and that the moment is worth marking; whether the room hears it is the user's. A machine whose decisions changed with a preference would be one whose sequence could only be asserted a setting at a time.
- It is read at each Cue rather than held, so turning the Cues off silences the Dictation under way rather than the next one after a restart.
- It is a menu bar item as well as a Settings row (#15), because of when it is reached for: someone sitting down in a meeting has one hand and two seconds.
- Off is silent rather than quieter. A Cue at a lower volume is still a sound the room can hear, which is the whole reason it was turned off.
- Cancel keeps its Cue for as long as the Cues are on. With them off, Escape is answered by the Pill disappearing and nothing else — which is the one moment where a user with their eyes on their work learns nothing, and the reason the switch is worth an ADR rather than a line in the README.

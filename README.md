# RoleRoulette

Randomly assigns roles, classes and specs for a 5-person group: one tank, one
healer and three DPS, each with a spec picked from what that person said they're
willing to play. Only one person in the group needs the addon.

## Install

Copy the `RoleRoulette` folder to

    World of Warcraft/_retail_/Interface/AddOns/

so that `AddOns/RoleRoulette/RoleRoulette.toc` exists, then restart the game
(or `/reload` if it is already running) and make sure RoleRoulette is ticked in
the AddOns list on the character screen.

## Use

1. `/rr` (or `/roleroulette`) opens the window.
2. **Build the roster.** Type a name and press **Add**, or press
   **Import Party** to add everyone in your current party.
3. **Pick specs.** Click a name to open the spec picker beside the window and
   tick every class/spec that person is willing to play tonight, alts included.
   The three role icons next to each name light up for the roles their pool
   covers.
4. **Tick who's playing.** The checkbox next to each name marks them available.
   Exactly five must be ticked.
5. **Randomize!** You get one tank, one healer and three DPS, each with a spec
   from their pool, listed tank first.
6. **Re-roll** if you don't like it, **Announce** to post it to party chat
   (if you're not in a party it's printed to your own chat window instead).

If no valid group exists, the window says why, for example
"Nobody has a healer spec in their pool."

### Options

- **Rotate roles**: makes it much less likely that people get the same role as
  last game. Re-rolling doesn't count as a game, so it steers away from the
  game before, not the result you just threw away.
- **Announce to chat after every roll**: posts each result automatically.

### Slash commands

| Command | |
|---|---|
| `/rr` | open or close the window |
| `/rr roll` | randomize without opening the window |
| `/rr announce` | post the last result |
| `/rr help` | list these |

## Development

Classes and specs are read from the game when you log in, so new specs appear
without an update. After a patch, only the `## Interface:` number in
`RoleRoulette.toc` needs changing (`/dump select(4, GetBuildInfo())` in game
prints the right one).

The randomizer in `Core.lua` is plain Lua with no game calls, and
`test_randomizer.lua` tests it outside the game:

    cd RoleRoulette
    lua test_randomizer.lua

It checks that every roll is 1 tank / 1 healer / 3 DPS with specs matching the
roles, that impossible rosters give the right message, and that rotation
weighting cuts repeats.

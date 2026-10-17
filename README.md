# RoleRoulette

Randomly assigns roles, classes and specs for up to five people: one tank, one
healer and three DPS, each with a spec picked from what that person said they're
willing to play. Only one person in the group needs the addon.

Fewer than five works too, for a few friends picking specs before queueing:
they get a slice of a normal group (never two tanks or two healers), and the
group finder fills the rest.

## Install

Copy the `RoleRoulette` folder to

    World of Warcraft/_retail_/Interface/AddOns/

so that `AddOns/RoleRoulette/RoleRoulette.toc` exists, then log in (or `/reload`
if you're already in game). If it doesn't load, check RoleRoulette is ticked in
the AddOns list on the character screen.

## Use

1. `/rr` (or `/roleroulette`) opens the window. It's the same window as
   SquizzFrames and Squizzumables, and with either of those installed
   `/squizz` lists RoleRoulette alongside them.
2. **Build the roster** (left column). Type a name and press **Add**, or press
   **Import Party** to add everyone in your current party.
3. **Pick specs** (middle column). Click a name and tick every class/spec that
   person is willing to play tonight, alts included. The three role icons next
   to each name light up for the roles their pool covers.
4. **Switch on who's playing.** The switch next to each name marks them
   available. Anywhere from one to five.
5. **Randomize!** (right column). Five people get one tank, one healer and
   three DPS; fewer get at most one tank, one healer and three DPS between
   them. Everyone gets a spec from their pool, listed tank first.
6. **Re-roll** if you don't like it, **Announce** to post it to party chat
   (if you're not in a party it's printed to your own chat window instead).

If no valid group exists, the window says why, for example
"Nobody has a healer spec in their pool."

### Settings page

- **Rotate roles**: makes it much less likely that people get the same role as
  last game. Re-rolling doesn't count as a game, so it steers away from the
  game before, not the result you just threw away.
- **Announce to chat after every roll**: posts each result automatically.
- **Theme**: one theme shared with SquizzFrames and Squizzumables. Picking one
  here changes all three.

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

`Libs/` holds LibStub plus LibSquizzTheme-1.0 and LibSquizzShell-1.0, the
theme and window shared with SquizzFrames and Squizzumables. They are
byte-identical copies of theirs: a change to one goes into all three addons,
with the library's `MINOR` bumped.

The randomizer in `Core.lua` is plain Lua with no game calls, and
`test_randomizer.lua` tests it outside the game:

    cd RoleRoulette
    lua test_randomizer.lua

It checks that five people always come out 1 tank / 1 healer / 3 DPS and fewer
never go over that, that specs always match roles, that impossible rosters give
the right message, and that rotation weighting cuts repeats.

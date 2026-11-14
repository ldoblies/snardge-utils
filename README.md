# SnardgeUtils

A collection of small quality of life tools for **WoW Forever**. Every feature can be switched off on its own, and every addon it builds on is optional: a feature that needs a missing addon simply stays off.

| Optional addon | Used for |
|---|---|
| Bagnon | Bag marks, mailing, bank bag icons |
| ItemTree | Greying out items only worth their vendor price |
| Questie | Quest mobs for the target macro, quest XP fallback |
| Leatrix Plus | Settings appear as a page in its panel |
| Mastercraft | Instant fishing recast |

## Features

### Bag marks (Bagnon)

Mark items in your bags with a modified left click, and SnardgeUtils handles them the next time you visit the right NPC:

| Click | Action |
|---|---|
| Ctrl+click | Sell at the next merchant |
| Alt+click | Deposit at the next bank |
| Shift+Alt+click | Always bank |
| Ctrl+Shift+click | Always mail to your chosen character |

- The same click again removes the mark. All four clicks can be changed, or turned off, with the cog next to **Bag marks** in the settings.
- Marked items get a small icon in the top-left corner and a colored border: red for sell, blue for bank, gold for mail.
- With ItemTree installed, items only worth their vendor price are greyed out too.
- Bank bags show their own icons instead of question marks.

### Mailing (Bagnon)

Set a recipient in the cog window next to **Bag marks**. When you open a mailbox on any other character, every item marked for mail is attached and sent, twelve stacks per mail, and chat lists what went out:

```
SnardgeUtils: mailing to Bank Alt: [Linen Cloth] x40, [Copper Ore] x20
SnardgeUtils: keeping part stacks: [Copper Ore] x7
```

**Full stacks only** (on by default) keeps part stacks in your bags until they fill up. Without a recipient nothing is mailed, and the mailbox tells you so.

### Experience bar

- Recent and session **xp/hr** on the right of the bar.
- A gold segment showing the **XP waiting in completed quests**, with the total on the left, for example `+4.1k from 3 quests (23%, reaches 25)`.

### Target macro

The `SUTarget` macro is rewritten out of combat with `/targetexact` lines for the nearest mobs your quests still need, using Questie's spawn data, within a range you choose (50 to 500 yards). Mobs you have looted at least twice in the last 30 minutes nearby are added too, so it also follows what you are farming. The nearest mob always wins. Drag it from `/macro` onto an action bar once; the settings show what it currently targets.

### Low health warning

Plays the raid warning sound once each time your health drops below a threshold, from 10% to 50% in 10% steps.

WoW Forever does not let addons read your health, so this runs on Blizzard's own Combat Audio Alerts: SnardgeUtils turns on the health pulse with its volume at zero, keeps every spoken alert off, and plays its sound when the pulse starts. These are account-wide game settings; turning the warning off in SnardgeUtils switches the alerts back off after a `/reload`.

### More

- **Map:** group member pins on the world map are drawn above Questie's icons.
- **Looking For Group:** the browser's gear menu filters listings by class and role, and sorts them by level, highest first.
- **Mana:** mana per second next to the player frame's mana bar while mana is not full.
- **Fishing (Mastercraft):** its fishing key casts again as soon as you let go of it after a catch.

## Settings

`/su` opens the settings. With Leatrix Plus installed they are a **SnardgeUtils** page in its panel, otherwise a window of their own. Switching a feature on or off takes effect after a `/reload`; the page says so when it is needed and unlocks the Reload button.

## Commands

| Command | Does |
|---|---|
| `/su` | Open the settings |
| `/suxp` | Print xp/hr, `/suxp reset` to start over |
| `/suqxp` | List completed quests and the XP they give |
| `/sumana` | Print mana regen while casting and not casting |
| `/sulow` | Show the state of the low health warning and Blizzard's audio alerts |
| `/sumap` | Show the group pin frame level and size |

## Installation

1. Download `SnardgeUtils-<version>.zip` from [Releases](https://github.com/ldoblies/snardge-utils/releases).
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, so the folder `AddOns/SnardgeUtils` exists.
3. Start WoW or run `/reload`, then open the settings with `/su`.

## License

MIT, see [`LICENSE`](LICENSE).

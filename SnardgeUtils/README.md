# SnardgeUtils

A collection of small quality of life tools for **WoW Forever**. Every feature can be switched off on its own, and the addons it builds on (Bagnon, ItemTree, Questie, Leatrix Plus, Mastercraft) are all optional.

## Features

### Bags (needs Bagnon)

- **Ctrl+click** an item to sell it at the next merchant.
- **Alt+click** to deposit it at the next bank, **Shift+Alt+click** to always bank it.
- **Ctrl+Shift+click** to always mail it to a character of your choice. Mailing runs by itself when you open a mailbox on any other character, and chat lists what went out. By default only full stacks are sent and part stacks stay in your bags until they fill up.
- The cog next to **Bag marks** in the settings sets the mail recipient and changes the clicks.
- Marked items get a small icon in the top-left corner and a colored border (red sell, blue bank, gold mail).
- With ItemTree installed, items only worth their vendor price are greyed out.
- Bank bags show their own icons instead of question marks.

### Experience bar

- Recent and session xp/hr on the right of the bar.
- A gold segment for the XP your completed quests give when handed in, with the total on the left.

### Target macro

The `SUTarget` macro is rewritten out of combat with `/targetexact` lines for the nearest mobs your quests still need (from Questie's spawn data), within a range you choose. Mobs you have looted at least twice in the last 30 minutes nearby are added too, so it also follows what you are farming. Drag it from `/macro` onto an action bar once.

### Low health warning

Plays the raid warning sound once each time your health drops below a threshold (10% to 50%, in 10% steps).

WoW Forever does not let addons read your health, so this runs on Blizzard's own Combat Audio Alerts: SnardgeUtils turns on the health pulse with its volume at zero, keeps every spoken alert off, and plays its sound when the pulse starts. These are account-wide game settings. Turning the warning off in SnardgeUtils switches the alerts back off after a `/reload`.

### More

- Group member pins on the world map are drawn above Questie's icons.
- The Looking For Group browser's gear menu filters listings by class and role, and sorts them by level, highest first.
- Mana per second next to the player frame's mana bar while mana is not full.
- With Mastercraft, its fishing key casts again as soon as you let go of it after a catch.

## Settings

`/su` opens the settings. With Leatrix Plus installed they are a SnardgeUtils page in its panel, otherwise a window of their own. Switching a feature on or off takes effect after a `/reload`; the page says so when it is needed.

## Commands

- `/su` - open the settings
- `/suxp` - print xp/hr, `/suxp reset` to start over
- `/suqxp` - list completed quests and the XP they give
- `/sumana` - print mana regen while casting and not casting
- `/sulow` - show the state of the low health warning and Blizzard's audio alerts
- `/sumap` - show the group pin frame level and size

## Installation

1. Copy the `SnardgeUtils` folder to `World of Warcraft/_forever_/Interface/AddOns/`.
2. Start WoW or run `/reload`.
3. Open the settings with `/su`. To use mailing, click the cog next to **Bag marks** and type the recipient under **Mail to**.

## License

MIT, see `LICENSE`.

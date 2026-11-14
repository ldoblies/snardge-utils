# SnardgeUtils

A collection of small quality of life tools for **WoW Forever**. Every feature can be switched off on its own, and every addon it builds on is optional: a feature that needs a missing addon simply stays off.

| Optional addon | Used for |
|---|---|
| Bagnon | Bag marks work in Bagnon as well as in the default bags; fixes its bank bag icons |
| Questie | Quest mobs for the target macro, quest XP fallback |
| Leatrix Plus | Settings appear as a page in its panel |
| Mastercraft | Instant fishing recast; recipes it already scanned show up in vendor profit right away |
| TradeSkillMaster | Auction house prices for vendor profit and high prices at login (required for both) |

## Features

### Bag marks

Mark items in your bags with a modified left click, in the default bags or in Bagnon, and SnardgeUtils handles them the next time you visit the right NPC:

| Click | Action |
|---|---|
| Ctrl+click | Sell at the next merchant |
| Alt+click | Deposit at the next bank |
| Shift+Alt+click | Always bank |
| Ctrl+Shift+click | Always mail to your chosen character |

- The same click again removes the mark. All four clicks can be changed, or turned off, with the cog next to **Bag marks** in the settings.
- Marked items get a small icon in the top-left corner and a colored border: red for sell, blue for bank, gold for mail.
- Items marked to sell are greyed out.
- With Bagnon, its bank bags show their own icons instead of question marks.

### Mailing

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

The `SUTarget` macro is rewritten out of combat with `/targetexact` lines for the nearest mobs your quests still need, using Questie's spawn data, within a range you choose (50 to 500 yards). Mobs you have looted at least twice in the last 30 minutes nearby are added too, so it also follows what you are farming. The nearest mob always wins. Newly added mobs are announced in chat, like RestedXP does (`SUTarget macro updated with: Kobold Vermin`), once per mob each session; this can be switched off. Drag it from `/macro` onto an action bar once; the settings show what it currently targets.

### Low health warning

Plays the raid warning sound once each time your health drops below a threshold, from 10% to 50% in 10% steps.

WoW Forever does not let addons read your health, so this runs on Blizzard's own Combat Audio Alerts: SnardgeUtils turns on the health pulse with its volume at zero, keeps every spoken alert off, and plays its sound when the pulse starts. These are account-wide game settings; turning the warning off in SnardgeUtils switches the alerts back off after a `/reload`.

### Vendor profit

`/suprofit` lists every recipe your characters know by what one craft brings when you sell the result to a vendor, most profitable first:

```
+1s 22c  Light Leather Pants  Pepe Soft, Leatherworking 150
      AH: 10 Light Leather + 1 Light Hide = 3s 49c, break-even 4s 71c  |  sells 5s 99c  |  vendor: 1 Fine Thread + 1 Salt = 1s 35c
```

- **Materials** cost the cheaper of TSM's auction house price and the vendor price. The break-even is the most the auction house materials may cost before the craft stops paying.
- **Vendor prices are what you actually paid:** every merchant you open is remembered per character, so a reputation discount counts. Items you never saw at a merchant use TSM's vendor price.
- **Cheapest way:** a material the same character can make (a Cured Light Hide from a Light Hide and Salt) counts at its crafting cost when that is cheaper.
- **Recipes you don't know yet** are listed too (switch off with **Unlearned too**): every Forever recipe that makes something a vendor buys, with where to learn it (trainer and skill, or the pattern vendor of your faction, its zone, price and whether its stock is limited, or drop or quest) and which of your characters is closest. The list comes from Wowhead's Forever data, built into the addon.
- **Filters:** profitable only, still gives skill (orange, yellow or green), unlearned too, and one character at a time.
- **Your other license:** characters on your other WoW license appear on their own while both are online at the same time: SnardgeUtils finds them over the guild channel or a group and shares known recipes and vendor prices by whisper, and remembers them for next time. Without a shared guild or group, run `/suprofit add Name Surname` once on either side.
- Recipes are read when you open a profession window, or taken from Mastercraft's own scans.

### High prices at login

A few seconds after you log in, a popup lists the items you own that sell for at least **120% of their usual price** right now, biggest jump first, with how many you have and the price each. It covers your bags and your bank as of your last bank visit, leaves out soulbound and grey items, and stays away when nothing qualifies. `/suprices` shows it any time.

Prices come from TSM: the recent price (3-day, then 14-day market value, then the region average) against the 60-day historical price, the realm's first and the region's for commodities.

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
| `/suprices` | Show the items that sell for at least 120% of their usual price |
| `/suprofit` | Open the vendor profit list; `add Name` or `remove Name` to sync with a character on your other license, `sync` to ask for an update now, `source <TSM price>` to change the auction house price (default `first(dbminbuyout, dbmarket)`) |

## Installation

1. Download `SnardgeUtils-<version>.zip` from [Releases](https://github.com/ldoblies/snardge-utils/releases).
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, so the folder `AddOns/SnardgeUtils` exists.
3. Start WoW or run `/reload`, then open the settings with `/su`.

## License

MIT, see [`LICENSE`](LICENSE).

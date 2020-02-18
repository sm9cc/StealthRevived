## Stealth Revived ##

### What is this? ###
   Stealth Revived is a plugin which aims to help server admins catch cheaters by hiding them when they go into spectator.

### What does the plugin currently do? ###

    Hides stealthed admins from scoreboard.
    Hides stealthed admins from status.
    Blocks cheats with 'Show spectators'


### How does it work? ###
Simply join spectator while you have Admin kick flag (Or you can change it using the override 'admin_stealth') and you will vanish, Now you can easily spectate cheaters and they will never know!

### Does it support games other than CSGO / TF2? ###
It does partially, but the status rewrite for games other than CSGO and TF2 is not yet supported.

### Why did you remove fake disconnect etc? ###
I will attempt to add these features back later but they have been very problematic, causing issues with radar, event messages showing 'Unconnected' etc.. and I struggled fixing them, Sorry!
Currently all messages are hidden when you join spectator or a team from being stealthed.

### Requirements (These are optional but recommended for better functionality): ###

    PTaH (CSGO ONLY) - For the status rewrite.
    SteamWorks - For more accurate IP and VAC checking.


### Installation ###

    Copy the folder structure to your gameserver and it should work straight away.
    Install the optional extensions for improved functionality.
    Configure the override 'admin_stealth' to whatever flag you like.
    Join spectator and have fun catching cheaters.


### ConVars ###

    sm_stealthrevived_status (Should the plugin rewrite status?) [Default 1]
    sm_stealthrevived_hidecheats (Should the plugin prevent cheats with 'spectator list' working? (This option may cause performance issues on some servers) [Default 1]


### Notes / Known issues ###

    - The TF2 status rewrite does not yet properly count points (I will get round to this at some point once I have setup a TF2 test server).
    - TF2 has not been thoroughly tested, but it should work fine other than the above issue.
    - I will attempt to add back the removed features later.


### Credits ###

I would like to thank everyone who has helped made this project possible, I am sorry if I forgot anyone.

    Drixevel Always been around for questions on steam, has more TF2 knowledge than me.
    komashchenko For PTAH, without this extension rewriting status in CSGO is not possible!
    Byte Private testing and helping me come up with ShouldTransmit method.
    Sneak Private testing.
    Psychonic Help and suggestions over sourcemod IRC.
    Asherkin Help and suggestions over sourcemod IRC.
    Necavi For original admin stealth plugin. (https://forums.alliedmods.net/showthread.php?p=1796351)

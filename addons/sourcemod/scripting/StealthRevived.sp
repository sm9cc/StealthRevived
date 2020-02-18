/****************************************************************************************************
	Stealth Revivived
*****************************************************************************************************

*****************************************************************************************************
	CHANGELOG: 
			0.1 - First version.
			0.2 - 
				- Improved spectator blocking with SendProxy (If installed) - Credits to Chaosxk
				- Make PTaH optional, sm_stealth_customstatus wont work in CSGO unless PTaH is installed until we find a way to rewrite status without dependencies.
				- Only rewrite status if there is atleast 1 stealthed client.
				- Improved late loading to account for admins already in spectator.
				- Improved support for other games, Still need to do the status rewrite for other games though.
				- Improved status anti-spam.
			0.3 - 
				- Fixed variables not being reset on client disconnect.
				- Added intial TF2 support (Needs further testing)
			0.4 - 
				- Use SteamWorks or SteamTools for more accurate IP detection, If you have both installed then only SteamWorks is used.
			0.5 - 
				- Fix console ending loop (Thanks Bara for report)
				- Fix error spam in TF2 (Thanks rengo)
				- Fixed TF2 disconnect reason (Thanks Drixevel)
			0.6 - 
				- Fix more error spam scenarios (Thanks rengo)
				- Correct TF2 disconnect reason.
				- Misc code changes.
			0.7 - 
				- Fixed issue with fake disconnect event breaking hud / radar.
				- Improved logic inside fake event creation.
				- General fixes.
			0.8 - 
				- Fixed issue where team broadcast being disabled caused the team menu to get stuck.
				- Fixed bad logic in SendProxy Callback.
				- Fixed "unconnected" bug on team changes.
				- Added check to make sure team event exists.
			0.9 - 
				- Removed SendProxy (It's too problematic)
				- Added a ConVar 'sm_stealthrevived_hidecheats' for cheat blocking (SetTransmit is inherently expensive thus this option can cause performance issues on some setups)
			0.9.1 - 
				- Support PtaH 1.1.0 (fix by FIVE)
			1.0.0 -
				- Removed Fake Disconnect / Connect (Now it wont show any messages)
					- I will attempt to fix this later but it has been very problematic, causing issues with radar, event messages showing 'Unconnected' etc.
				- Remove SteamTools support - Use SteamWorks already!
				- Remove Updater support.
				- Fixed PTaH hook.
				- Fixed 'version' in status.
				- Improved SetTransmit performance when using 'sm_stealthrevived_hidecheats' by only hooking stealthed clients.
				- Removed 'status' cmd interval ConVar to keep things simple.
				- General fixes.
				
*****************************************************************************************************
*****************************************************************************************************
	INCLUDES
*****************************************************************************************************/
#include <StealthRevived>
#include <sdktools>
#include <sdkhooks>
#include <regex>
#include <autoexecconfig>

#undef REQUIRE_EXTENSIONS
#tryinclude <ptah>
#tryinclude <SteamWorks>

/****************************************************************************************************
	DEFINES
*****************************************************************************************************/
#define PL_VERSION "1.0.0"
#define LoopValidPlayers(%1) for(int %1 = 1; %1 <= MaxClients; %1++) if(IsValidClient(%1))
#define LoopValidClients(%1) for(int %1 = 1; %1 <= MaxClients; %1++) if(IsValidClient(%1, false))

/****************************************************************************************************
	ETIQUETTE.
*****************************************************************************************************/
#pragma newdecls required;
#pragma semicolon 1;

/****************************************************************************************************
	PLUGIN INFO.
*****************************************************************************************************/
public Plugin myinfo =  {
	name = "Stealth Revived", 
	author = "SM9();", 
	description = "Just another Stealth plugin.", 
	version = PL_VERSION, 
	url = "https://sm9.dev"
}

/****************************************************************************************************
	HANDLES.
*****************************************************************************************************/
ConVar g_cvHostName = null;
ConVar g_cvHostPort = null;
ConVar g_cvHostIP = null;
ConVar g_cvTags = null;
ConVar g_cvCustomStatus = null;
ConVar g_cvSetTransmit = null;

/****************************************************************************************************
	BOOLS.
*****************************************************************************************************/
bool g_bStealthed[MAXPLAYERS + 1];
bool g_bWindows = false;
bool g_bRewriteStatus = false;
bool g_bDataCached = false;
bool g_bSetTransmit = true;
bool g_bPTaH = false;

/****************************************************************************************************
	INTS.
*****************************************************************************************************/
int g_iLastCommand[MAXPLAYERS + 1];
int g_iTickRate = 0;
int g_iServerPort = 0;
int g_iPlayerManager = -1;
int g_iTF2Stats[10][6];


/****************************************************************************************************
	STRINGS.
*****************************************************************************************************/
char g_sVersion[32];
char g_sHostName[256];
char g_sServerIP[32];
char g_sCurrentMap[PLATFORM_MAX_PATH];
char g_sMaxPlayers[12];
char g_sGameName[32];
char g_sAccount[24];
char g_sServerSteamId[24];
char g_sTags[128];

public void OnPluginStart() {
	AutoExecConfig_SetFile("StealthRevived", "SM9");
	
	g_cvCustomStatus = AutoExecConfig_CreateConVar("sm_stealthrevived_status", "1", "Should the plugin rewrite status?", _, true, 0.0, true, 1.0);
	g_cvCustomStatus.AddChangeHook(OnCvarChanged);
	
	g_cvSetTransmit = AutoExecConfig_CreateConVar("sm_stealthrevived_hidecheats", "1", "Should the plugin prevent cheats with 'spectator list' working? (This option may cause performance issues on some servers)", _, true, 0.0, true, 1.0);
	g_cvSetTransmit.AddChangeHook(OnCvarChanged);
	
	AutoExecConfig_CleanFile(); AutoExecConfig_ExecuteFile();
	
	g_cvHostName = FindConVar("hostname");
	g_cvHostPort = FindConVar("hostport");
	g_cvHostIP = FindConVar("hostip");
	g_cvTags = FindConVar("sv_tags");
	
	if (g_cvTags != null) {
		g_cvTags.AddChangeHook(OnCvarChanged);
	}
	
	#if defined _PTaH_included
	if (LibraryExists("PTaH")) {
		g_bPTaH = PTaH(PTaH_ExecuteStringCommandPre, Hook, ExecuteStringCommand);
	}
	#endif
	
	if (!g_bPTaH) {
		AddCommandListener(Command_Status, "status");
	}
	
	GetGameFolderName(g_sGameName, sizeof(g_sGameName));
	
	if (!HookEventEx("player_team", Event_PlayerTeam_Pre, EventHookMode_Pre)) {
		SetFailState("player_team event does not exist on this mod, plugin disabled");
		return;
	}
	
	if (StrEqual(g_sGameName, "tf", false)) {
		HookEventEx("player_spawn", TF2Events_CallBack);
		HookEventEx("player_escort_score", TF2Events_CallBack);
		HookEventEx("player_death", TF2Events_CallBack);
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] eror, int err_max) {
	RegPluginLibrary("StealthRevived");
	CreateNative("SR_IsClientStealthed", Native_IsClientStealthed);
	return APLRes_Success;
}

public void OnCvarChanged(ConVar conVar, const char[] oldValue, const char[] newValue) {
	if (conVar == g_cvCustomStatus) {
		g_bRewriteStatus = view_as<bool>(StringToInt(newValue));
	} else if (conVar == g_cvTags) {
		strcopy(g_sTags, sizeof(g_sTags), newValue);
	} else if (conVar == g_cvSetTransmit) {
		g_bSetTransmit = view_as<bool>(StringToInt(newValue));
		
		if (g_bSetTransmit) {
			LoopValidPlayers(client) {
				if (!g_bStealthed[client]) {
					continue;
				}
				
				SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
			}
		}
	}
}

public void OnConfigsExecuted() {
	g_bRewriteStatus = g_cvCustomStatus.BoolValue;
	g_cvTags.GetString(g_sTags, sizeof(g_sTags));
	g_bSetTransmit = g_cvSetTransmit.BoolValue;
	
	LoopValidPlayers(client) {
		if (!CanGoStealth(client) || GetClientTeam(client) > 1) {
			continue;
		}
		
		if (g_bSetTransmit) {
			SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
		}
		
		g_bStealthed[client] = true;
	}
}

public void OnMapStart() {
	GetCurrentMap(g_sCurrentMap, sizeof(g_sCurrentMap));
	
	for (int i = 0; i < 10; i++) {
		for (int y = 0; y < 6; y++) {
			g_iTF2Stats[i][y] = 0;
		}
	}
	
	g_iPlayerManager = GetPlayerResourceEntity();
	
	if (g_iPlayerManager != -1) {
		SDKHook(g_iPlayerManager, SDKHook_ThinkPost, Hook_PlayerManagerThinkPost);
	}
}

public Action Command_Status(int client, const char[] sCommand, int args) {
	if (client < 1) {
		return Plugin_Continue;
	}
	
	if (g_iLastCommand[client] > -1 && GetTime() - g_iLastCommand[client] < 1) {
		return Plugin_Handled;
	}
	
	if (!g_bRewriteStatus) {
		return Plugin_Continue;
	}
	
	ExecuteStringCommand(client, "status");
	
	return Plugin_Handled;
}

public Action ExecuteStringCommand(int client, char message[1024]) {
	if (client < 1 || client > MaxClients) {
		return Plugin_Continue;
	}
	
	if (g_iLastCommand[client] > -1 && GetTime() - g_iLastCommand[client] < 1) {
		return Plugin_Handled;
	}
	
	if (!g_bRewriteStatus) {
		return Plugin_Continue;
	}
	
	static char message2[1024]; message2 = message;
	
	TrimString(message2);
	
	if (StrContains(message2, "status") == -1) {
		return Plugin_Continue;
	}
	
	if (!IsClientInGame(client)) {
		return Plugin_Handled;
	}
	
	return PrintCustomStatus(client) ? Plugin_Handled : Plugin_Continue;
}

public Action Event_PlayerTeam_Pre(Event event, char[] eventName, bool dontBroadcast) {
	int client;
	
	if (!(client = GetClientOfUserId(event.GetInt("userid"))) || IsFakeClient(client) || view_as<bool>(event.GetInt("disconnect"))) {
		return Plugin_Continue;
	}
	
	int toTeam = event.GetInt("team");
	
	if (toTeam > 1) {
		if (g_bStealthed[client]) {
			event.BroadcastDisabled = true;
		}
		g_bStealthed[client] = false;
		return Plugin_Continue;
	}
	
	if (CanGoStealth(client)) {
		g_bStealthed[client] = true;
		event.BroadcastDisabled = true;
		
		if (g_bSetTransmit) {
			SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
		}
	}
	
	return Plugin_Continue;
}

public Action TF2Events_CallBack(Event event, char[] eventName, bool dontBroadcast) {
	int eventIndex = -1;
	int playerClass = -1;
	int attackerClass = -1;
	int assisterClass = -1;
	
	if (StrEqual(eventName, "player_spawn", false)) {
		playerClass = TF2_GetPlayerClass(GetClientOfUserId(event.GetInt("userid")));
		eventIndex = TF_SR_Spawns;
	} else if (StrEqual(eventName, "player_escort_score", false)) {
		playerClass = TF2_GetPlayerClass(event.GetInt("player"));
		eventIndex = TF_SR_Points;
	} else if (StrEqual(eventName, "player_death", false)) {
		playerClass = TF2_GetPlayerClass(GetClientOfUserId(event.GetInt("userid")));
		attackerClass = TF2_GetPlayerClass(GetClientOfUserId(event.GetInt("attacker")));
		assisterClass = TF2_GetPlayerClass(GetClientOfUserId(event.GetInt("assister")));
		eventIndex = TF_SR_Deaths;
	}
	
	switch (eventIndex) {
		case TF_SR_Spawns :  {
			if (TF2_IsValidClass(playerClass)) {
				g_iTF2Stats[playerClass][TF_SR_Spawns]++;
			}
		}
		
		case TF_SR_Points :  {
			if (TF2_IsValidClass(playerClass)) {
				g_iTF2Stats[playerClass][TF_SR_Points] += event.GetInt("points");
			}
		}
		
		case TF_SR_Deaths :  {
			if (TF2_IsValidClass(playerClass)) {
				g_iTF2Stats[playerClass][TF_SR_Deaths]++;
			}
			
			if (TF2_IsValidClass(attackerClass)) {
				g_iTF2Stats[attackerClass][TF_SR_Kills]++;
			}
			
			if (TF2_IsValidClass(assisterClass)) {
				g_iTF2Stats[assisterClass][TF_SR_Assists]++;
			}
		}
	}
}

public void OnClientDisconnect(int client) {
	g_iLastCommand[client] = -1;
	g_bStealthed[client] = false;
	
}

public void OnEntityCreated(int entity, const char[] className) {
	if (StrContains(className, "player_manager", false) == -1) {
		return;
	}
	
	g_iPlayerManager = entity;
	SDKHook(g_iPlayerManager, SDKHook_ThinkPost, Hook_PlayerManagerThinkPost);
}

public void Hook_PlayerManagerThinkPost(int entity) {
	bool changed = false;
	
	LoopValidPlayers(client) {
		if (!g_bStealthed[client]) {
			continue;
		}
		
		SetEntProp(g_iPlayerManager, Prop_Send, "m_bConnected", false, _, client);
		changed = true;
	}
	
	if (changed) {
		ChangeEdictState(entity);
	}
}

public Action Hook_SetTransmit(int entity, int client) {
	if (entity == client) {
		return Plugin_Continue;
	}
	
	if (!g_bSetTransmit || !g_bStealthed[entity]) {
		SDKUnhook(entity, SDKHook_SetTransmit, Hook_SetTransmit);
		return Plugin_Continue;
	}
	
	return Plugin_Handled;
}

stock bool PrintCustomStatus(int client) {
	g_iLastCommand[client] = GetTime();
	
	if (!g_bDataCached) {
		CacheInformation();
	}
	
	PrintToConsole(client, "hostname: %s", g_sHostName);
	PrintToConsole(client, g_sVersion);
	
	bool gameTF2 = false;
	
	if (!StrEqual(g_sGameName, "tf", false)) {
		PrintToConsole(client, "udp/ip  : %s:%d", g_sServerIP, g_iServerPort);
		PrintToConsole(client, "os      : %s", g_bWindows ? "Windows" : "Linux");
		PrintToConsole(client, "type    : community dedicated");
		PrintToConsole(client, "map     : %s", g_sCurrentMap);
		PrintToConsole(client, "players : %d humans, %d bots %s (not hibernating)\n", GetPlayerCount(), GetBotCount(), g_sMaxPlayers);
		PrintToConsole(client, "# userid name uniqueid connected ping loss state rate");
	} else {
		gameTF2 = true;
		
		PrintToConsole(client, "udp/ip  : %s:%d  (public ip: %s)", g_sServerIP, g_iServerPort, g_sServerIP);
		PrintToConsole(client, g_sServerSteamId);
		PrintToConsole(client, g_sAccount);
		PrintToConsole(client, "map     : %s at: 0 x, 0 y, 0 z", g_sCurrentMap);
		PrintToConsole(client, "tags    : %s", g_sTags);
		PrintToConsole(client, "players : %d humans, %d bots %s", GetPlayerCount(), GetBotCount(), g_sMaxPlayers);
		PrintToConsole(client, "edicts  : %d used of 2048 max", GetEntityCount());
		PrintToConsole(client, "         Spawns Points Kills Deaths Assists");
		
		PrintToConsole(client, "Scout         %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Scout][TF_SR_Spawns], g_iTF2Stats[TFClass_Scout][TF_SR_Points], g_iTF2Stats[TFClass_Scout][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Scout][TF_SR_Deaths], g_iTF2Stats[TFClass_Scout][TF_SR_Assists]);
		
		PrintToConsole(client, "Sniper        %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Sniper][TF_SR_Spawns], g_iTF2Stats[TFClass_Sniper][TF_SR_Points], g_iTF2Stats[TFClass_Sniper][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Sniper][TF_SR_Deaths], g_iTF2Stats[TFClass_Sniper][TF_SR_Assists]);
		
		PrintToConsole(client, "Soldier       %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Soldier][TF_SR_Spawns], g_iTF2Stats[TFClass_Soldier][TF_SR_Points], g_iTF2Stats[TFClass_Soldier][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Soldier][TF_SR_Deaths], g_iTF2Stats[TFClass_Soldier][TF_SR_Assists]);
		
		PrintToConsole(client, "Demoman       %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_DemoMan][TF_SR_Spawns], g_iTF2Stats[TFClass_DemoMan][TF_SR_Points], g_iTF2Stats[TFClass_DemoMan][TF_SR_Kills], 
			g_iTF2Stats[TFClass_DemoMan][TF_SR_Deaths], g_iTF2Stats[TFClass_DemoMan][TF_SR_Assists]);
		
		PrintToConsole(client, "Medic         %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Medic][TF_SR_Spawns], g_iTF2Stats[TFClass_Medic][TF_SR_Points], g_iTF2Stats[TFClass_Medic][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Medic][TF_SR_Deaths], g_iTF2Stats[TFClass_Medic][TF_SR_Assists]);
		
		PrintToConsole(client, "Heavy         %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Heavy][TF_SR_Spawns], g_iTF2Stats[TFClass_Heavy][TF_SR_Points], g_iTF2Stats[TFClass_Heavy][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Heavy][TF_SR_Deaths], g_iTF2Stats[TFClass_Heavy][TF_SR_Assists]);
		
		PrintToConsole(client, "Pyro          %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Pyro][TF_SR_Spawns], g_iTF2Stats[TFClass_Pyro][TF_SR_Points], g_iTF2Stats[TFClass_Pyro][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Pyro][TF_SR_Deaths], g_iTF2Stats[TFClass_Pyro][TF_SR_Assists]);
		
		PrintToConsole(client, "Spy           %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Spy][TF_SR_Spawns], g_iTF2Stats[TFClass_Spy][TF_SR_Points], g_iTF2Stats[TFClass_Spy][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Spy][TF_SR_Deaths], g_iTF2Stats[TFClass_Spy][TF_SR_Assists]);
		
		PrintToConsole(client, "Engineer      %d      %d     %d      %d       %d\n", 
			g_iTF2Stats[TFClass_Engineer][TF_SR_Spawns], g_iTF2Stats[TFClass_Engineer][TF_SR_Points], g_iTF2Stats[TFClass_Engineer][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Engineer][TF_SR_Deaths], g_iTF2Stats[TFClass_Engineer][TF_SR_Assists]);
		
		PrintToConsole(client, "# userid name                uniqueid            connected ping loss state");
	}
	
	char clientAuthId[64]; char sTime[9]; char sRate[9]; char clientName[MAX_NAME_LENGTH];
	
	LoopValidClients(i) {
		if (g_bStealthed[i]) {
			continue;
		}
		
		FormatEx(clientName, sizeof(clientName), "\"%N\"", i);
		
		if (gameTF2) {
			GetClientAuthId(i, AuthId_Steam3, clientAuthId, sizeof(clientAuthId));
			
			if (!IsFakeClient(i)) {
				FormatShortTime(RoundToFloor(GetClientTime(i)), sTime, sizeof(sTime));
				PrintToConsole(client, "# %6d %-19s %19s %9s %4d %4d active", GetClientUserId(i), clientName, clientAuthId, sTime, GetPing(i), GetLoss(i));
			} else {
				PrintToConsole(client, "# %6d %-19s %19s                     active", GetClientUserId(i), clientName, clientAuthId);
			}
		} else {
			if (!IsFakeClient(i)) {
				GetClientAuthId(i, AuthId_Steam2, clientAuthId, sizeof(clientAuthId));
				GetClientInfo(i, "rate", sRate, sizeof(sRate));
				FormatShortTime(RoundToFloor(GetClientTime(i)), sTime, sizeof(sTime));
				
				PrintToConsole(client, "# %d %d %s %s %s %d %d active %s", GetClientUserId(i), i, clientName, clientAuthId, sTime, GetPing(i), GetLoss(i), sRate);
			} else {
				PrintToConsole(client, "#%d %s BOT active %d", i, clientName, g_iTickRate);
			}
		}
	}
	
	if (!gameTF2) {
		PrintToConsole(client, "#end");
	}
	
	return true;
}

public void CacheInformation() {
	bool secure = false; bool steamWorks;
	char sStatus[512]; char sBuffer[512]; ServerCommandEx(sStatus, sizeof(sStatus), "status");
	
	g_iTickRate = RoundToZero(1.0 / GetTickInterval());
	
	g_bWindows = StrContains(sStatus, "os      :  Windows", true) != -1;
	g_cvHostName.GetString(g_sHostName, sizeof(g_sHostName));
	g_iServerPort = g_cvHostPort.IntValue;
	
	#if defined _SteamWorks_Included
	steamWorks = LibraryExists("SteamWorks");
	
	if (steamWorks) {
		int ip[4];
		
		if (steamWorks) {
			SteamWorks_GetPublicIP(ip);
			secure = SteamWorks_IsVACEnabled();
		}
		
		FormatEx(g_sServerIP, sizeof(g_sServerIP), "%d.%d.%d.%d", ip[0], ip[1], ip[2], ip[3]);
	}
	#endif
	
	if (!steamWorks) {
		int serverIP = g_cvHostIP.IntValue;
		FormatEx(g_sServerIP, sizeof(g_sServerIP), "%d.%d.%d.%d", serverIP >>> 24 & 255, serverIP >>> 16 & 255, serverIP >>> 8 & 255, serverIP & 255);
	}
	
	Regex regex = null;
	int matches = 0;
	
	if (StrEqual(g_sGameName, "csgo", false)) {
		regex = CompileRegex("version (.*?) secure");
		matches = regex.Match(sStatus);
		
		if (matches < 1) {
			delete regex;
			
			if (!steamWorks) {
				secure = false;
			}
			
			regex = CompileRegex("version (.*?) insecure");
			matches = regex.Match(sStatus);
			
		} else if (!steamWorks) {
			secure = true;
		}
		
		if (matches > 0) {
			regex.GetSubString(0, sBuffer, sizeof(sBuffer));
		}
		
		delete regex;
		
		char sSplit[2][64]; ExplodeString(sBuffer, "/", sSplit, sizeof(sSplit), sizeof(sSplit[]));
		FormatEx(g_sVersion, sizeof(g_sVersion), "%s %s", sSplit[0], secure ? "secure" : "insecure");
	} else if (StrEqual(g_sGameName, "tf", false)) {
		regex = CompileRegex("version.*");
		matches = regex.Match(sStatus);
		
		if (matches > 0) {
			regex.GetSubString(0, g_sVersion, sizeof(g_sVersion));
		}
		
		delete regex;
		
		regex = CompileRegex("account.*");
		matches = regex.Match(sStatus);
		
		if (matches > 0) {
			regex.GetSubString(0, g_sAccount, sizeof(g_sAccount));
		}
		
		delete regex;
		
		regex = CompileRegex("steamid.*");
		matches = regex.Match(sStatus);
		
		if (matches > 0) {
			regex.GetSubString(0, g_sServerSteamId, sizeof(g_sServerSteamId));
		}
		
		delete regex;
	}
	
	regex = CompileRegex("\\((.*? max)\\)");
	matches = regex.Match(sStatus);
	
	if (matches > 0) {
		regex.GetSubString(1, sBuffer, sizeof(sBuffer));
	}
	
	delete regex;
	
	FormatEx(g_sMaxPlayers, sizeof(g_sMaxPlayers), "(%s)", sBuffer);
	
	g_bDataCached = true;
}

stock bool IsValidClient(int client, bool ignoreBots = true) {
	if (client < 1 || client > MaxClients) {
		return false;
	}
	
	if (!IsClientInGame(client)) {
		return false;
	}
	
	if (IsFakeClient(client) && ignoreBots) {
		return false;
	}
	
	return true;
}

stock bool CanGoStealth(int client) {
	return CheckCommandAccess(client, "admin_stealth", ADMFLAG_KICK);
}

stock int GetPlayerCount() {
	int count = 0;
	
	LoopValidPlayers(client) {
		if (g_bStealthed[client]) {
			continue;
		}
		
		count++;
	}
	
	return count;
}

stock int GetBotCount() {
	int count = 0;
	
	LoopValidClients(client) {
		if (!IsFakeClient(client)) {
			continue;
		}
		
		count++;
	}
	
	return count;
}

stock int GetLoss(int client) {
	return RoundFloat(GetClientAvgLoss(client, NetFlow_Both));
}

stock int GetPing(int client) {
	return RoundFloat(GetClientLatency(client, NetFlow_Both) * 1000.0);
}

stock bool TF2_IsValidClass(int iClass) {
	return iClass < 10 && iClass > 0;
}

stock int TF2_GetPlayerClass(int client) {
	if (!IsValidClient(client, false)) {
		return -1;
	}
	
	if (!HasEntProp(client, Prop_Send, "m_iClass")) {
		return -1;
	}
	
	return GetEntProp(client, Prop_Send, "m_iClass");
}

// Thanks Necavi - https://forums.alliedmods.net/showthread.php?p=1796351
stock void FormatShortTime(int time, char[] sOut, int iSize) {
	int tempInt = time % 60;
	
	FormatEx(sOut, iSize, "%02d", tempInt);
	tempInt = (time % 3600) / 60;
	
	FormatEx(sOut, iSize, "%02d:%s", tempInt, sOut);
	
	tempInt = (time % 86400) / 3600;
	
	if (tempInt > 0) {
		FormatEx(sOut, iSize, "%d%:s", tempInt, sOut);
	}
}

public int Native_IsClientStealthed(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	return g_bStealthed[client];
} 
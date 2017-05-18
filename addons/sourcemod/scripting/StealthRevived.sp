/****************************************************************************************************
	[CSGO/Others Soon™] Stealth Revived
*****************************************************************************************************

*****************************************************************************************************
	CHANGELOG: 
			0.1 - First version.
			0.2 - 
				- Improved spectator blocking with SendProxy (If installed) - Credits to Chaosxk
				- Make PTAH optional, sm_stealth_customstatus wont work in CSGO unless PTAH is installed until we find a way to rewrite status without dependencies.
				- Only rewrite status if there is atleast 1 stealthed client.
				- Improved late loading to account for admins already in spectator.
				- Improved support for other games, Still need to do the status rewrite for other games though.
				- Improved status anti-spam.
			0.3 - 
				- Fixed variables not being reset on client disconnect.
				- Added intial TF2 support (Needs further testing)
				
*****************************************************************************************************
*****************************************************************************************************
	INCLUDES
*****************************************************************************************************/
#include <StealthRevived>
#include <sdktools>
#include <sdkhooks>
#include <regex>
#include <autoexecconfig>

#undef REQUIRE_PLUGIN
#tryinclude <updater>

#undef REQUIRE_EXTENSIONS
#tryinclude <sendproxy>
#tryinclude <ptah>

#define UPDATE_URL    "https://bitbucket.org/SM91337/stealthrevived/raw/master/addons/sourcemod/update.txt"

/****************************************************************************************************
	DEFINES
*****************************************************************************************************/
#define PL_VERSION "0.3"
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
public Plugin myinfo = 
{
	name = "Stealth Revived", 
	author = "SM9();", 
	description = "A proper stealth plugin that actually works.", 
	version = PL_VERSION, 
	url = "http://www.fragdeluxe.com/"
}

/****************************************************************************************************
	HANDLES.
*****************************************************************************************************/
ConVar g_cHostName = null;
ConVar g_cHostPort = null;
ConVar g_cHostIP = null;
ConVar g_cTags = null;
ConVar g_cCustomStatus = null;
ConVar g_cFakeDisconnect = null;
ConVar g_cCmdInterval = null;

/****************************************************************************************************
	BOOLS.
*****************************************************************************************************/
bool g_bStealthed[MAXPLAYERS + 1] = false;
bool g_bWindows = false;
bool g_bRewriteStatus = false;
bool g_bFakeDC = false;
bool g_bSendProxy = false;
bool g_bDataCached = false;

/****************************************************************************************************
	INTS.
*****************************************************************************************************/
int g_iLastCommand[MAXPLAYERS + 1] = -1;
int g_iCmdInterval = 1;
int g_iTickRate = 0;
int g_iServerPort = 0;
int g_iPlayerManager = -1;
int g_iTF2Stats[10][6];

/****************************************************************************************************
	STRINGS.
*****************************************************************************************************/
char g_szVersion[128];
char g_szHostName[128];
char g_szServerIP[128];
char g_szCurrentMap[128];
char g_szMaxPlayers[128];
char g_szGameName[128];
char g_szAccount[128];
char g_szSteamId[128];
char g_szTags[512];

public void OnPluginStart()
{
	AutoExecConfig_SetFile("plugin.stealthrevived");
	
	g_cCustomStatus = AutoExecConfig_CreateConVar("sm_stealth_customstatus", "1", "Should the plugin rewrite status out? 0 = False, 1 = True", _, true, 0.0, true, 1.0);
	g_cCustomStatus.AddChangeHook(OnCvarChanged);
	
	g_cFakeDisconnect = AutoExecConfig_CreateConVar("sm_stealth_fakedc", "1", "Should the plugin fire a fake disconnect when somebody goes stealth? 0 = False, 1 = True", _, true, 0.0, true, 1.0);
	g_cFakeDisconnect.AddChangeHook(OnCvarChanged);
	
	g_cCmdInterval = AutoExecConfig_CreateConVar("sm_stealth_cmd_interval", "1", "How often can the status cmd be used in seconds?", _, true, 0.0);
	g_cCmdInterval.AddChangeHook(OnCvarChanged);
	
	AutoExecConfig_CleanFile(); AutoExecConfig_ExecuteFile();
	
	g_cHostName = FindConVar("hostname");
	g_cHostPort = FindConVar("hostport");
	g_cHostIP = FindConVar("hostip");
	g_cTags = FindConVar("sv_tags");
	
	if (g_cTags != null) {
		g_cTags.AddChangeHook(OnCvarChanged);
	}
	
	#if defined _updater_included
	if (LibraryExists("updater")) {
		Updater_AddPlugin(UPDATE_URL);
	}
	#endif
	
	#if defined _PTaH_included
	if (LibraryExists("PTaH")) {
		PTaH(PTaH_ExecuteStringCommand, Hook, ExecuteStringCommand);
	}
	#endif
	
	g_bSendProxy = LibraryExists("sendproxy");
	
	AddCommandListener(Command_Status, "status");
	OnConfigsExecuted();
	
	LoopValidPlayers(iClient) {
		OnClientPutInServer(iClient);
		
		if (!IsClientStealthWorthy(iClient)) {
			continue;
		}
		
		if (GetClientTeam(iClient) < 2) {
			g_bStealthed[iClient] = true;
		}
	}
	
	GetGameFolderName(g_szGameName, sizeof(g_szGameName));
	
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	
	if (StrEqual(g_szGameName, "tf", false)) {
		HookEventEx("player_spawn", TF2Events_CallBack);
		HookEventEx("player_escort_score", TF2Events_CallBack);
		HookEventEx("player_death", TF2Events_CallBack);
	}
}

public void OnLibraryAdded(const char[] szName)
{
	if (StrEqual(szName, "updater", false)) {
		Updater_AddPlugin(UPDATE_URL);
	} else if (StrEqual(szName, "sendproxy", false)) {
		g_bSendProxy = true;
	}
}

public void OnLibraryRemoved(const char[] szName)
{
	if (StrEqual(szName, "sendproxy", false)) {
		g_bSendProxy = false;
	}
}

public APLRes AskPluginLoad2(Handle hNyself, bool bLate, char[] chError, int iErrMax)
{
	RegPluginLibrary("StealthRevived");
	CreateNative("SR_IsClientStealthed", Native_IsClientStealthed);
	return APLRes_Success;
}

public void OnCvarChanged(ConVar cConVar, const char[] szOldValue, const char[] szNewValue)
{
	if (cConVar == g_cCustomStatus) {
		g_bRewriteStatus = view_as<bool>(StringToInt(szNewValue));
	} else if (cConVar == g_cFakeDisconnect) {
		g_bFakeDC = view_as<bool>(StringToInt(szNewValue));
	} else if (cConVar == g_cCmdInterval) {
		g_iCmdInterval = StringToInt(szNewValue);
	} else if (cConVar == g_cTags) {
		strcopy(g_szTags, 512, szNewValue);
	}
}

public void OnConfigsExecuted()
{
	g_bRewriteStatus = g_cCustomStatus.BoolValue;
	g_bFakeDC = g_cFakeDisconnect.BoolValue;
	g_iCmdInterval = g_cCmdInterval.IntValue;
	g_cTags.GetString(g_szTags, 512);
}

public void OnMapStart()
{
	GetCurrentMap(g_szCurrentMap, 128);
	
	for (int i = 0; i < 10; i++) {
		for (int y = 0; y < 6; y++) {
			g_iTF2Stats[i][y] = 0;
		}
	}
	
	g_iPlayerManager = GetPlayerResourceEntity();
	
	if (g_iPlayerManager == -1) {
		return;
	}
	
	SDKHook(g_iPlayerManager, SDKHook_ThinkPost, Hook_PlayerManagerThinkPost);
}

public Action Command_Status(int iClient, const char[] szComman, int iArgs)
{
	if (iClient < 1) {
		return Plugin_Continue;
	}
	
	if (g_iLastCommand[iClient] > -1 && GetTime() - g_iLastCommand[iClient] < g_iCmdInterval) {
		return Plugin_Handled;
	}
	
	if (!g_bRewriteStatus) {
		return Plugin_Continue;
	}
	
	/*
	if (GetStealthCount() < 1) {
		return Plugin_Continue;
	} */
	
	ExecuteStringCommand(iClient, "status");
	
	return Plugin_Handled;
}

public Action ExecuteStringCommand(int iClient, char sMessage[1024])
{
	if (g_iLastCommand[iClient] > -1 && GetTime() - g_iLastCommand[iClient] < g_iCmdInterval) {
		return Plugin_Handled;
	}
	
	if (!g_bRewriteStatus) {
		return Plugin_Continue;
	}
	
	static char sMessage2[1024];
	sMessage2 = sMessage;
	
	TrimString(sMessage2);
	
	if (StrContains(sMessage2, "status") == -1) {
		return Plugin_Continue;
	}
	
	return PrintCustomStatus(iClient) ? Plugin_Handled : Plugin_Continue;
}

public Action Event_PlayerTeam(Event evEvent, char[] szEvent, bool bDontBroadcast)
{
	int iUserId = evEvent.GetInt("userid");
	int iClient = GetClientOfUserId(iUserId);
	
	if (iClient <= 0 || iClient > MaxClients || view_as<bool>(evEvent.GetInt("disconnect"))) {
		return Plugin_Continue;
	}
	
	int iOldTeam = evEvent.GetInt("oldteam");
	int iTeam = evEvent.GetInt("team");
	
	if (iTeam > 1) {
		if (g_bStealthed[iClient]) {
			g_bStealthed[iClient] = false;
			
			Event evFakeTeam = CreateEvent("player_team", true);
			
			if (evFakeTeam == null) {
				return Plugin_Continue;
			}
			
			evFakeTeam.SetInt("userid", iUserId);
			evFakeTeam.SetInt("team", iTeam);
			evFakeTeam.SetInt("oldteam", iOldTeam);
			evFakeTeam.SetInt("disconnect", false);
			evFakeTeam.FireToClient(iClient);
			evFakeTeam.Cancel();
			
			return Plugin_Handled;
		}
		
		return Plugin_Continue;
	}
	
	if (!IsClientStealthWorthy(iClient)) {
		return Plugin_Continue;
	}
	
	if (iOldTeam > 1 && g_bFakeDC) {
		Event evFakeDC = CreateEvent("player_disconnect", true);
		
		if (evFakeDC != null) {
			char szName[MAX_NAME_LENGTH]; GetClientName(iClient, szName, MAX_NAME_LENGTH);
			char szAuthId[64]; GetClientAuthId(iClient, AuthId_Steam2, szAuthId, 64);
			
			evFakeDC.SetInt("userid", iUserId);
			evFakeDC.SetString("reason", "Disconnect");
			evFakeDC.SetString("name", szName);
			evFakeDC.SetString("networkid", szAuthId);
			evFakeDC.SetInt("bot", false);
			evFakeDC.Fire();
		}
	}
	
	g_bStealthed[iClient] = true;
	
	return Plugin_Handled;
}

public Action TF2Events_CallBack(Event evEvent, char[] szEvent, bool bDontBroadcast)
{
	int iEvent = -1;
	
	int iClassPlayer = -1;
	int iClassAttacker = -1;
	int iClassAssister = -1;
	
	if (StrEqual(szEvent, "player_spawn", false)) {
		iClassPlayer = view_as<int>(TF2_GetPlayerClass(GetClientOfUserId(evEvent.GetInt("userid"))));
		iEvent = TF_SR_Spawns;
	} else if (StrEqual(szEvent, "player_escort_score", false)) {
		iClassPlayer = view_as<int>(TF2_GetPlayerClass(evEvent.GetInt("player")));
		iEvent = TF_SR_Points;
	} else if (StrEqual(szEvent, "player_death", false)) {
		iClassPlayer = view_as<int>(TF2_GetPlayerClass(GetClientOfUserId(evEvent.GetInt("userid"))));
		iClassAttacker = view_as<int>(TF2_GetPlayerClass(GetClientOfUserId(evEvent.GetInt("attacker"))));
		
		int iAssister = GetClientOfUserId(evEvent.GetInt("assister"));
		
		if (iAssister > 0) {
			iClassAssister = view_as<int>(TF2_GetPlayerClass(iAssister));
		}
		
		iEvent = TF_SR_Deaths;
	}
	
	switch (iEvent) {
		case TF_SR_Spawns :  {
			g_iTF2Stats[iClassPlayer][TF_SR_Spawns]++;
		}
		
		case TF_SR_Points :  {
			g_iTF2Stats[iClassPlayer][TF_SR_Points] += evEvent.GetInt("points");
		}
		
		case TF_SR_Deaths :  {
			g_iTF2Stats[iClassPlayer][TF_SR_Deaths]++;
			g_iTF2Stats[iClassAttacker][TF_SR_Kills]++;
			
			if (iClassAssister > -1) {
				g_iTF2Stats[iClassAssister][TF_SR_Assists]++;
			}
		}
	}
}

public void OnClientPutInServer(int iClient)
{
	SDKHook(iClient, SDKHook_SetTransmit, Hook_SetTransmit);
	
	#if defined _SENDPROXYMANAGER_INC_
	if (g_bSendProxy) {
		SendProxy_Hook(iClient, "m_hObserverTarget", Prop_Int, PropHook_CallBack);
	}
	#endif
	
	g_iLastCommand[iClient] = -1;
	g_bStealthed[iClient] = false;
}

public void OnClientDisconnect(int iClient)
{
	g_iLastCommand[iClient] = -1;
	g_bStealthed[iClient] = false;
}

public void OnEntityCreated(int iEntity, const char[] szClassName)
{
	if (StrEqual(szClassName, "cs_player_manager", false) || StrEqual(szClassName, "tf_player_manager", false)) {
		g_iPlayerManager = iEntity;
		
		SDKHook(g_iPlayerManager, SDKHook_ThinkPost, Hook_PlayerManagerThinkPost);
	}
}

public void Hook_PlayerManagerThinkPost(int iEntity)
{
	LoopValidPlayers(iClient) {
		SetEntProp(iEntity, Prop_Send, "m_bConnected", !g_bStealthed[iClient], _, iClient);
	}
}

#if defined _SENDPROXYMANAGER_INC_
public Action PropHook_CallBack(int iEntity, const char[] szPropName, int &iValue, int iElement)
{
	if (iEntity != iValue) {
		return Plugin_Continue;
	}
	
	iValue = g_bStealthed[iEntity] ? -1 : iValue;
	
	return Plugin_Changed;
}
#endif

public Action Hook_SetTransmit(int iEntity, int iClient)
{
	if (iEntity == iClient) {
		return Plugin_Continue;
	}
	
	if (!IsValidClient(iEntity)) {
		return Plugin_Continue;
	}
	
	if (!g_bStealthed[iEntity]) {
		return Plugin_Continue;
	}
	
	return Plugin_Handled;
}

stock bool PrintCustomStatus(int iClient)
{
	g_iLastCommand[iClient] = GetTime();
	
	/*
	if (GetStealthCount() < 1) {
		return false;
	} */
	
	if (!g_bDataCached) {
		CacheInformation(0);
	}
	
	PrintToConsole(iClient, "hostname: %s", g_szHostName);
	PrintToConsole(iClient, g_szVersion);
	
	bool bTF2 = false;
	
	
	if (!StrEqual(g_szGameName, "tf", false)) {
		PrintToConsole(iClient, "udp/ip  : %s:%d", g_szServerIP, g_iServerPort);
		PrintToConsole(iClient, "os      : %s", g_bWindows ? "Windows" : "Linux");
		PrintToConsole(iClient, "type    : community dedicated");
		PrintToConsole(iClient, "map     : %s", g_szCurrentMap);
		PrintToConsole(iClient, "players : %d humans, %d bots %s (not hibernating)\n", GetPlayerCount(), GetBotCount(), g_szMaxPlayers);
		PrintToConsole(iClient, "# userid name uniqueid connected ping loss state rate");
	} else {
		bTF2 = true;
		
		PrintToConsole(iClient, "udp/ip  : %s:%d  (public ip: %s)", g_szServerIP, g_iServerPort, g_szServerIP);
		PrintToConsole(iClient, g_szSteamId);
		PrintToConsole(iClient, g_szAccount);
		PrintToConsole(iClient, "map     : %s at: 0 x, 0 y, 0 z", g_szCurrentMap);
		PrintToConsole(iClient, "tags    : %s", g_szTags);
		PrintToConsole(iClient, "players : %d humans, %d bots %s", GetPlayerCount(), GetBotCount(), g_szMaxPlayers);
		PrintToConsole(iClient, "edicts  : %d used of 2048 max", GetEntityCount());
		PrintToConsole(iClient, "         Spawns Points Kills Deaths Assists");
		
		PrintToConsole(iClient, "Scout         %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Scout][TF_SR_Spawns], g_iTF2Stats[TFClass_Scout][TF_SR_Points], g_iTF2Stats[TFClass_Scout][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Scout][TF_SR_Deaths], g_iTF2Stats[TFClass_Scout][TF_SR_Assists]);
		
		PrintToConsole(iClient, "Sniper        %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Sniper][TF_SR_Spawns], g_iTF2Stats[TFClass_Sniper][TF_SR_Points], g_iTF2Stats[TFClass_Sniper][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Sniper][TF_SR_Deaths], g_iTF2Stats[TFClass_Sniper][TF_SR_Assists]);
		
		PrintToConsole(iClient, "Soldier       %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Soldier][TF_SR_Spawns], g_iTF2Stats[TFClass_Soldier][TF_SR_Points], g_iTF2Stats[TFClass_Soldier][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Soldier][TF_SR_Deaths], g_iTF2Stats[TFClass_Soldier][TF_SR_Assists]);
		
		PrintToConsole(iClient, "Demoman       %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_DemoMan][TF_SR_Spawns], g_iTF2Stats[TFClass_DemoMan][TF_SR_Points], g_iTF2Stats[TFClass_DemoMan][TF_SR_Kills], 
			g_iTF2Stats[TFClass_DemoMan][TF_SR_Deaths], g_iTF2Stats[TFClass_DemoMan][TF_SR_Assists]);
		
		PrintToConsole(iClient, "Medic         %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Medic][TF_SR_Spawns], g_iTF2Stats[TFClass_Medic][TF_SR_Points], g_iTF2Stats[TFClass_Medic][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Medic][TF_SR_Deaths], g_iTF2Stats[TFClass_Medic][TF_SR_Assists]);
		
		PrintToConsole(iClient, "Heavy         %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Heavy][TF_SR_Spawns], g_iTF2Stats[TFClass_Heavy][TF_SR_Points], g_iTF2Stats[TFClass_Heavy][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Heavy][TF_SR_Deaths], g_iTF2Stats[TFClass_Heavy][TF_SR_Assists]);
		
		PrintToConsole(iClient, "Pyro          %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Pyro][TF_SR_Spawns], g_iTF2Stats[TFClass_Pyro][TF_SR_Points], g_iTF2Stats[TFClass_Pyro][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Pyro][TF_SR_Deaths], g_iTF2Stats[TFClass_Pyro][TF_SR_Assists]);
		
		PrintToConsole(iClient, "Spy           %d      %d     %d      %d       %d", 
			g_iTF2Stats[TFClass_Spy][TF_SR_Spawns], g_iTF2Stats[TFClass_Spy][TF_SR_Points], g_iTF2Stats[TFClass_Spy][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Spy][TF_SR_Deaths], g_iTF2Stats[TFClass_Spy][TF_SR_Assists]);
		
		PrintToConsole(iClient, "Engineer      %d      %d     %d      %d       %d\n", 
			g_iTF2Stats[TFClass_Engineer][TF_SR_Spawns], g_iTF2Stats[TFClass_Engineer][TF_SR_Points], g_iTF2Stats[TFClass_Engineer][TF_SR_Kills], 
			g_iTF2Stats[TFClass_Engineer][TF_SR_Deaths], g_iTF2Stats[TFClass_Engineer][TF_SR_Assists]);
		
		PrintToConsole(iClient, "# userid name                uniqueid            connected ping loss state");
	}
	
	char szAuthId[64]; char szTime[9]; char szRate[9]; char szName[MAX_NAME_LENGTH];
	
	LoopValidClients(i) {
		if (g_bStealthed[i]) {
			continue;
		}
		
		Format(szName, sizeof(szName), "\"%N\"", i);
		
		if (bTF2) {
			GetClientAuthId(i, AuthId_Steam3, szAuthId, 64);
			if (!IsFakeClient(i)) {
				FormatShortTime(RoundToFloor(GetClientTime(i)), szTime, 9);
				PrintToConsole(iClient, "# %6d %-19s %19s %9s %4d %4d active", GetClientUserId(i), szName, szAuthId, szTime, GetPing(i), GetLoss(i));
			} else {
				PrintToConsole(iClient, "# %6d %-19s %19s                     active", GetClientUserId(i), szName, szAuthId);
			}
		} else {
			if (IsFakeClient(i)) {
				PrintToConsole(iClient, "#%d %s BOT active %d", i, szName, g_iTickRate);
			} else {
				GetClientAuthId(i, AuthId_Steam2, szAuthId, 64);
				GetClientInfo(i, "rate", szRate, 9);
				FormatShortTime(RoundToFloor(GetClientTime(i)), szTime, 9);
				
				PrintToConsole(iClient, "# %d %d %s %s %s %d %d active %s", GetClientUserId(i), i, szName, szAuthId, szTime, GetPing(i), GetLoss(i), szRate);
			}
			
			PrintToConsole(iClient, "#end");
		}
	}
	
	return true;
}

public void CacheInformation(any anything)
{
	bool bSecure = false;
	char szStatus[512]; char szBuffer[512]; ServerCommandEx(szStatus, sizeof(szStatus), "status");
	
	g_iTickRate = RoundToZero(1.0 / GetTickInterval());
	
	g_bWindows = StrContains(szStatus, "os      :  Windows", true) != -1;
	g_cHostName.GetString(g_szHostName, sizeof(g_szHostName));
	
	int iServerIP = g_cHostIP.IntValue;
	g_iServerPort = g_cHostPort.IntValue;
	
	Format(g_szServerIP, sizeof(g_szServerIP), "%d.%d.%d.%d", iServerIP >>> 24 & 255, iServerIP >>> 16 & 255, iServerIP >>> 8 & 255, iServerIP & 255);
	
	Regex rRegex = null;
	int iMatches = 0;
	
	if (StrEqual(g_szGameName, "csgo", false)) {
		rRegex = CompileRegex("version (.*?) secure");
		
		iMatches = rRegex.Match(szStatus);
		
		if (iMatches < 1) {
			delete rRegex; bSecure = false;
			rRegex = CompileRegex("version (.*?) insecure");
			iMatches = rRegex.Match(szStatus);
			
		} else {
			bSecure = true;
		}
		
		if (iMatches > 0) {
			rRegex.GetSubString(0, szBuffer, sizeof(szBuffer));
		}
		
		delete rRegex;
		
		char szSplit[2][64];
		
		if (ExplodeString(szBuffer, "/", szSplit, 2, 64) < 1) {
			return;
		}
		
		Format(g_szVersion, sizeof(g_szVersion), "%s %s", szSplit[0], bSecure ? "secure" : "insecure");
	} else if (StrEqual(g_szGameName, "tf", false)) {
		rRegex = CompileRegex("version.*");
		iMatches = rRegex.Match(szStatus);
		
		if (iMatches > 0) {
			rRegex.GetSubString(0, g_szVersion, sizeof(g_szVersion));
		}
		
		delete rRegex;
		
		rRegex = CompileRegex("account.*");
		iMatches = rRegex.Match(szStatus);
		
		if (iMatches > 0) {
			rRegex.GetSubString(0, g_szAccount, sizeof(g_szAccount));
		}
		
		delete rRegex;
		
		rRegex = CompileRegex("steamid.*");
		iMatches = rRegex.Match(szStatus);
		
		if (iMatches > 0) {
			rRegex.GetSubString(0, g_szSteamId, sizeof(g_szSteamId));
		}
		
		delete rRegex;
	}
	
	rRegex = CompileRegex("\\((.*? max)\\)");
	iMatches = rRegex.Match(szStatus);
	
	if (iMatches > 0) {
		rRegex.GetSubString(1, szBuffer, sizeof(szBuffer));
	}
	
	delete rRegex;
	
	Format(g_szMaxPlayers, sizeof(g_szMaxPlayers), "(%s)", szBuffer);
	
	g_bDataCached = true;
}

stock bool IsValidClient(int iClient, bool bIgnoreBots = true)
{
	if (iClient <= 0 || iClient > MaxClients) {
		return false;
	}
	
	if (!IsClientInGame(iClient)) {
		return false;
	}
	
	if (IsFakeClient(iClient) && bIgnoreBots) {
		return false;
	}
	
	return true;
}

stock bool IsClientStealthWorthy(int iClient) {
	return CheckCommandAccess(iClient, "admin_stealth", ADMFLAG_KICK);
}

stock int GetPlayerCount()
{
	int iCount = 0;
	
	LoopValidPlayers(iClient) {
		if (g_bStealthed[iClient]) {
			continue;
		}
		
		iCount++;
	}
	
	return iCount;
}

stock int GetBotCount()
{
	int iCount = 0;
	
	LoopValidClients(iClient) {
		if (!IsFakeClient(iClient)) {
			continue;
		}
		
		iCount++;
	}
	
	return iCount;
}

stock int GetStealthCount()
{
	int iCount = 0;
	
	LoopValidClients(iClient) {
		if (!g_bStealthed[iClient]) {
			continue;
		}
		
		iCount++;
	}
	
	return iCount;
}

stock int GetLoss(int iClient) {
	return RoundFloat(GetClientAvgLoss(iClient, NetFlow_Both));
}

stock int GetPing(int iClient)
{
	float fPing = GetClientLatency(iClient, NetFlow_Both);
	fPing *= 1000.0;
	
	return RoundFloat(fPing);
}

stock TFClassType TF2_GetPlayerClass(int iClient) {
	return view_as<TFClassType>(GetEntProp(iClient, Prop_Send, "m_iClass"));
}

// Thanks Necavi - https://forums.alliedmods.net/showthread.php?p=1796351
stock void FormatShortTime(int iTime, char[] szOut, int iSize)
{
	int iTemp = iTime % 60;
	
	Format(szOut, iSize, "%02d", iTemp);
	iTemp = (iTime % 3600) / 60;
	
	Format(szOut, iSize, "%02d:%s", iTemp, szOut);
	
	iTemp = (iTime % 86400) / 3600;
	
	if (iTemp > 0) {
		Format(szOut, iSize, "%d%:s", iTemp, szOut);
	}
}

public int Native_IsClientStealthed(Handle hPlugin, int iNumParams)
{
	int iClient = GetNativeCell(1);
	
	return g_bStealthed[iClient];
} 
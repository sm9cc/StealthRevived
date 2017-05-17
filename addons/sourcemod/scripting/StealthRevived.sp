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
#define PL_VERSION "0.2"
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

/****************************************************************************************************
	INTS.
*****************************************************************************************************/
int g_iLastCommand[MAXPLAYERS+1] = -1;
int g_iCmdInterval = 1;
int g_iTickRate = 0;

/****************************************************************************************************
	STRINGS.
*****************************************************************************************************/
char g_szVersion[32];
char g_szHostName[128];
char g_szServerIP[128];
char g_szCurrentMap[128];
char g_szMaxPlayers[32];

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
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
	OnConfigsExecuted();
	
	LoopValidPlayers(iClient) {
		OnClientPutInServer(iClient);
		
		if (!IsClientStealthWorthy(iClient)) {
			continue;
		}
		
		if(GetClientTeam(iClient) < 2) {
			g_bStealthed[iClient] = true;
		}
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
	} else if(cConVar == g_cFakeDisconnect) {
		g_bFakeDC = view_as<bool>(StringToInt(szNewValue));
	} else if(cConVar == g_cCmdInterval) {
		g_iCmdInterval = StringToInt(szNewValue);
	}
}

public void OnConfigsExecuted() 
{
	RequestFrame(CacheInformation, -1);
	
	g_bRewriteStatus = g_cCustomStatus.BoolValue;
	g_bFakeDC = g_cFakeDisconnect.BoolValue;
	g_iCmdInterval = g_cCmdInterval.IntValue;
}

public void OnMapStart() 
{
	GetCurrentMap(g_szCurrentMap, 128);
	
	int iPlayerManager = GetPlayerResourceEntity();
	
	if (iPlayerManager == -1) {
		return;
	}
	
	SDKHook(iPlayerManager, SDKHook_ThinkPost, Hook_PlayerManagerThinkPost);
}

public Action Command_Status(int iClient, const char[] szComman, int iArgs)
{
	if(g_iLastCommand[iClient] > -1 && GetTime() - g_iLastCommand[iClient] < g_iCmdInterval) {
		return Plugin_Handled;
	}
	
	if(!g_bRewriteStatus) {
		return Plugin_Continue;
	}
	
	if(GetStealthCount() < 1) {
		return Plugin_Continue;
	}
	
	ExecuteStringCommand(iClient, "status");
	
	return Plugin_Handled;
}

public Action ExecuteStringCommand(int iClient, char sMessage[1024])
{
	if(g_iLastCommand[iClient] > -1 && GetTime() - g_iLastCommand[iClient] < g_iCmdInterval) {
		return Plugin_Handled;
	}
	
	if(!g_bRewriteStatus) {
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

public Action Event_PlayerTeam(Event evEvent, char[] chEvent, bool bDontBroadcast)
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

public void OnClientPutInServer(int iClient) 
{
	SDKHook(iClient, SDKHook_SetTransmit, Hook_SetTransmit);
	
	#if defined _SENDPROXYMANAGER_INC_
	if (g_bSendProxy) {
		SendProxy_Hook(iClient, "m_hObserverTarget", Prop_Int, PropHook_CallBack);
	}
	#endif
}

public void OnEntityCreated(int iEntity, const char[] szClassName)
{
	if (StrEqual(szClassName, "cs_player_manager", false)) {
		SDKHook(iEntity, SDKHook_ThinkPost, Hook_PlayerManagerThinkPost);
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
	
	if(GetStealthCount() < 1) {
		return false;
	}
	
	PrintToConsole(iClient, "hostname: %s", g_szHostName);
	PrintToConsole(iClient, g_szVersion);
	PrintToConsole(iClient, "udp/ip  : %s", g_szServerIP);
	PrintToConsole(iClient, "os      : %s", g_bWindows ? "Windows" : "Linux");
	PrintToConsole(iClient, "type    : community dedicated");
	PrintToConsole(iClient, "map     : %s", g_szCurrentMap);
	PrintToConsole(iClient, "players : %d humans, %d bots %s (not hibernating)\n", GetPlayerCount(), GetBotCount(), g_szMaxPlayers);
	PrintToConsole(iClient, "# userid name uniqueid connected ping loss state rate");
	
	char szAuthId[64]; char szTime[9]; char szRate[9];
	
	LoopValidClients(i) {
		if (g_bStealthed[i]) {
			continue;
		}
		
		if (IsFakeClient(i)) {
			PrintToConsole(iClient, "#%d \"%N\" BOT active %d", i, i, g_iTickRate);
		} else {
			GetClientAuthId(i, AuthId_Steam2, szAuthId, 64);
			GetClientInfo(i, "rate", szRate, 9);
			FormatShortTime(RoundToFloor(GetClientTime(i)), szTime, 9);
			
			PrintToConsole(iClient, "# %d %d \"%N\" %s %s %d %d active %s", GetClientUserId(i), i, i, szAuthId, szTime, GetPing(i), GetLoss(i), szRate);
		}
	}
	
	PrintToConsole(iClient, "#end");
	
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
	int iServerPort = g_cHostPort.IntValue;
	
	Format(g_szServerIP, sizeof(g_szServerIP), "%d.%d.%d.%d:%d", iServerIP >>> 24 & 255, iServerIP >>> 16 & 255, iServerIP >>> 8 & 255, iServerIP & 255, iServerPort);
	
	Regex rRegex = CompileRegex("version (.*?) secure");
	int iMatches = rRegex.Match(szStatus);
	
	if (iMatches < 1) {
		delete rRegex; bSecure = false;
		rRegex = CompileRegex("version (.*?) insecure");
		iMatches = rRegex.Match(szStatus);
		
	} else {
		bSecure = true;
	}
	
	if (iMatches < 1) {
		delete rRegex;
		return;
	}
	
	if (!rRegex.GetSubString(0, szBuffer, sizeof(szBuffer))) {
		delete rRegex;
		return;
	}
	
	delete rRegex;
	
	char szSplit[2][64];
	
	if (ExplodeString(szBuffer, "/", szSplit, 2, 64) < 1) {
		return;
	}
	
	Format(g_szVersion, sizeof(g_szVersion), "%s %s", szSplit[0], bSecure ? "secure" : "insecure");
	
	rRegex = CompileRegex("\\((.*? max)\\)");
	iMatches = rRegex.Match(szStatus);
	
	if (iMatches < 1) {
		delete rRegex;
		return;
	}
	
	if (!rRegex.GetSubString(1, szBuffer, sizeof(szBuffer))) {
		delete rRegex;
		return;
	}
	
	delete rRegex;
	
	Format(g_szMaxPlayers, sizeof(g_szMaxPlayers), "(%s)", szBuffer);
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
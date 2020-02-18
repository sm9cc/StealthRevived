#if defined _simplestealth_included_
#endinput
#endif
#define _simplestealth_included_

enum {
	TF_SR_Spawns = 1,
	TF_SR_Points,
	TF_SR_Kills,
	TF_SR_Deaths,
	TF_SR_Assists
}

enum TFClassType
{
	TFClass_Unknown = 0,
	TFClass_Scout,
	TFClass_Sniper,
	TFClass_Soldier,
	TFClass_DemoMan,
	TFClass_Medic,
	TFClass_Heavy,
	TFClass_Pyro,
	TFClass_Spy,
	TFClass_Engineer
};

public SharedPlugin __pl_stealthrevived = 
{
	name = "SimpleStealth", 
	file = "SimpleStealth.smx", 
	#if defined REQUIRE_PLUGIN
	required = 1, 
	#else
	required = 0, 
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_stealthrevived_SetNTVOptional() {
	MarkNativeAsOptional("SS_IsClientStealthed");
}
#endif

/**
 * Returns true if a client is stealthed.
 *
 * @return		True if a client is stealthed. False otherwise.
 */
native bool SS_IsClientStealthed(int iClient);
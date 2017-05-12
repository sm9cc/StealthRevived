#if defined _stealthrevived_included_
#endinput
#endif
#define _stealthrevived_included_


public SharedPlugin __pl_stealthrevived = 
{
	name = "StealthRevived", 
	file = "StealthRevived.smx", 
	#if defined REQUIRE_PLUGIN
	required = 1, 
	#else
	required = 0, 
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_stealthrevived_SetNTVOptional() {
	MarkNativeAsOptional("SR_IsClientStealthed");
}
#endif

IN_ALT1

/**
 * Returns if a a client is stealthed/
 *
 * @return		True if a client is stealthed. False otherwise.
 */
native bool SR_IsClientStealthed(int iClient);
#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Rowdy"
#define PLUGIN_VERSION "1.00"
#define MAX_LOBBIES 24

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <multicolors>
#include <stamm>

#pragma newdecls required

enum Lobby {
	eChallenger,
	eOpponent,
	eAmount,
	bool:ePunishment,
	bool:eStarted
};

int iLobby[MAX_LOBBIES][Lobby];

enum Client {
	eLobbyId,
	eLastOpponent,
	bool:eWaitingForAmount,
	bool:eInvitesEnabled,
	bool:eCookieInvitesEnabled,
	bool:eIsDisconnected
};

int iClient[MAXPLAYERS + 1][Client];

Handle hCookie;

ConVar cvCommands;
char cCommands[255];
ConVar cvSCommands;
char cSCommands[255];
ConVar cvPunishment;
int iPunishment;
ConVar cvMinStammpoints;
int iMinStammpoints;
ConVar cvChallengeStartNextRound;
int iChallengeStartNextRound;

char cDisconnectReason[48];

public Plugin myinfo = 
{
	name = "Stamm Challenges",
	author = PLUGIN_AUTHOR,
	description = "Challenge your enemies and win some Stammpoints!",
	version = PLUGIN_VERSION,
	url = "https://steamcommunity.com/profiles/76561198307962930"
};

public void OnPluginStart()
{	
	LoadTranslations("stammchallenges.phrases");
	
	RegConsoleCmd("say", OnPlayerSay);
	RegConsoleCmd("say_team", OnPlayerSay);
	
	HookEvent("round_start", OnRoundStart);
	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_hurt", OnPlayerHurt);
	HookEvent("player_team", OnPlayerTeam);
	HookEvent("player_disconnect", OnPlayerDisconnect, EventHookMode_Pre);
	
	cvCommands = CreateConVar("schal_commands", "sf,sc", "Set custom commands for Stamm challenges menu.");
	cvSCommands = CreateConVar("schal_settings_commands", "scs,sfs", "Set custom commands for Stamm challenges settings menu.");
	cvPunishment = CreateConVar("schal_punishment_stammpoints", "500", "Set punishment as Stammpoints for leaving challenge via disconnect.");
	cvMinStammpoints = CreateConVar("schal_minimum_stammpoints", "10", "Set minimum Stammpoints to be visible in stamm challenges menu.");
	cvChallengeStartNextRound = CreateConVar("schal_challenge_start_nextround", "1", "Set if challenge after accept from challenger will start in next round.\n0 => No, challenge will start instantly\n1 => Yes");
	 
	AutoExecConfig(true, "stammchallenges");
	
	hCookie = RegClientCookie("sc_invite_enabled", "Stamm Fight Invite", CookieAccess_Protected);
	
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsValidClient(i))
			continue;
			
		OnClientPostAdminCheck(i);
		OnClientCookiesCached(i);
	}
	
}

public void OnMapStart() 
{
	for (int i = 0; i < MAX_LOBBIES; i++) 
	{
		RefreshLobby(i);
	}
}

public void OnConfigsExecuted()
{
	iPunishment = GetConVarInt(cvPunishment);
	iMinStammpoints = GetConVarInt(cvMinStammpoints);
	iChallengeStartNextRound = GetConVarInt(cvChallengeStartNextRound);
	
	char cCmds[12][24], cCmd[24];
	
	GetConVarString(cvCommands, cCommands, 255);
	ReplaceString(cCommands, sizeof(cCommands), " ", "");
	GetConVarString(cvSCommands, cSCommands, 255);
	ReplaceString(cSCommands, sizeof(cSCommands), " ", "");
	
	int iCountCommands, iCountSCommands;
	
	iCountCommands = ExplodeString(cCommands, ",", cCmds, 12, 24);
	for (int i = 0; i < iCountCommands; i++) {
		Format(cCmd, sizeof(cCmd), "sm_%s", cCmds[i]);
		if (GetCommandFlags(cCmd) == INVALID_FCVAR_FLAGS) {
			RegConsoleCmd(cCmd, Command_SC);
		}
	}
	
	iCountSCommands = ExplodeString(cSCommands, ",", cCmds, 12, 24);
	for (int y = 0; y < iCountSCommands; y++) {
		Format(cCmd, sizeof(cCmd), "sm_%s", cCmds[y]);
		if (GetCommandFlags(cCmd) == INVALID_FCVAR_FLAGS) {
			RegConsoleCmd(cCmd, Command_SCSettings);
		}
	}
}

public void OnClientCookiesCached(int client) {
	char cCookie[5];
	GetClientCookie(client, hCookie, cCookie, sizeof(cCookie));
	
	bool bCookie;
	if (strlen(cCookie) == 0) {
		bCookie = true;
	} else {
		bCookie = view_as<bool>(StringToInt(cCookie));
	}
	
	iClient[client][eInvitesEnabled] = bCookie;
	iClient[client][eCookieInvitesEnabled] = bCookie;
}

public void OnRoundStart(Event event, char[] name, bool dontBroadcast)
{
	for (int i = 0; i < MAX_LOBBIES; i++) {
		iLobby[i][ePunishment] = false;
		
		if (!IsValidClient(iLobby[i][eChallenger]))
			continue;
		if (!IsValidClient(iLobby[i][eOpponent]))
			continue;
		if (iLobby[i][eStarted])
			continue;
		
		iLobby[i][eStarted] = true;
		CPrintToChat(iLobby[i][eChallenger], "%t%t", "ChatTag", "Challenge started", iLobby[i][eAmount], iLobby[i][eOpponent], i);
		CPrintToChat(iLobby[i][eOpponent], "%t%t", "ChatTag", "Challenge started", iLobby[i][eAmount], iLobby[i][eChallenger], i);
	}
}

public void OnPlayerDeath(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int lobbyid = (iClient[client][eLobbyId] == iClient[attacker][eLobbyId] ? iClient[client][eLobbyId] : -1);
	
	if (iClient[client][eIsDisconnected]) {
		int nlobbyid;
		int opponent = GetChallengerIfExists(client);
		if ((nlobbyid = iClient[client][eLobbyId]) != -1) {
			if (StrEqual(cDisconnectReason, "Disconnect")) {
				if (IsValidClient(opponent)) {
					if (iLobby[nlobbyid][ePunishment]) {
						STAMM_DelClientPoints(client, iPunishment);
						CPrintToChatAll("%t%t", "ChatTag", "Player disconnected from challenge", client, iLobby[nlobbyid][eAmount], iClient[client][eLastOpponent], nlobbyid, iPunishment);
						RefreshClient(opponent);
						RefreshClient(client);
						RefreshLobby(nlobbyid);
					}
				}
			}
		}
	} else {
		if ((client == attacker || iClient[client][eLastOpponent] == attacker) && lobbyid != -1 && iLobby[lobbyid][eStarted] && iLobby[lobbyid][ePunishment]) {
			
			int realattacker = iClient[client][eLastOpponent];
			STAMM_AddClientPoints(realattacker, iLobby[lobbyid][eAmount]);
			CPrintToChat(realattacker, "%t%t", "ChatTag", "You won challenge", iLobby[lobbyid][eAmount], client);
			
			STAMM_DelClientPoints(client, iLobby[lobbyid][eAmount]);
			CPrintToChat(client, "%t%t", "ChatTag", "You lost challenge", iLobby[lobbyid][eAmount], attacker);
			
			RefreshClient(client);
			RefreshClient(attacker);
			RefreshLobby(lobbyid);
		}
	}
}

public void OnPlayerHurt(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	int lobbyid = (iClient[client][eLobbyId] == iClient[attacker][eLobbyId] ? iClient[client][eLobbyId] : -1);
	
	if (lobbyid != -1 && !iLobby[lobbyid][ePunishment] && iLobby[lobbyid][eStarted]) {
		iLobby[lobbyid][ePunishment] = true;
	}
}

public void OnPlayerTeam(Event event, char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int opponent = iClient[client][eLastOpponent];
	int lobbyid = (iClient[client][eLobbyId] != -1 && iClient[client][eLobbyId] == iClient[opponent][eLobbyId] ? iClient[client][eLobbyId] : -1);
	
	if (lobbyid != -1 && IsValidClient(client) && IsValidClient(opponent)) {
		CPrintToChat(client, "%t%t", "ChatTag", "Player changed his team - client", opponent);
		CPrintToChat(opponent, "%t%t", "ChatTag", "Player changed his team - opponent", client);
		
		RefreshClient(client);
		RefreshClient(opponent);
		RefreshLobby(lobbyid);
	}
}

public void OnPlayerDisconnect(Event event, char[] name, bool dontBroadcast)
{
	event.GetString("reason", cDisconnectReason, sizeof(cDisconnectReason));
}


public void OnClientDisconnect(int client)
{	
	if (iClient[client][eInvitesEnabled] != iClient[client][eCookieInvitesEnabled]) 
	{
		char cCookie[24];
		Format(cCookie, sizeof(cCookie), "%i", view_as<int>(iClient[client][eInvitesEnabled]));
		SetClientCookie(client, hCookie, cCookie);
	}
	
	int lobbyid;
	int opponent = GetChallengerIfExists(client);
	if ((lobbyid = iClient[client][eLobbyId]) != -1) {
		if (StrEqual(cDisconnectReason, "Disconnect")) {
			if (IsValidClient(opponent)) {
				if (!iLobby[lobbyid][ePunishment]) {
					CPrintToChat(opponent, "Challenge failed! Player disconnected from challenge", client, iLobby[lobbyid][eAmount]);
					RefreshClient(opponent);
					RefreshClient(client);
					RefreshLobby(lobbyid);
				}
			}
		} else {
			if (IsValidClient(opponent)) {
				RefreshClient(opponent);
				CPrintToChat(opponent, "Challenge failed! Player droped from challenge", client, iLobby[lobbyid][eAmount]);
			}
			RefreshClient(client);
			RefreshLobby(lobbyid);
		}
	} else {
		if (IsValidClient(opponent)) {
			RefreshClient(opponent);
		}
		RefreshClient(client);
	}
	iClient[client][eIsDisconnected] = true;
}

public void OnClientPostAdminCheck(int client) 
{
	RefreshClient(client);
	iClient[client][eIsDisconnected] = false;
}

public Action OnPlayerSay(int client, int args) {
	if (iClient[client][eWaitingForAmount]) {
		char cText[255];
		GetCmdArgString(cText, sizeof(cText));
		StripQuotes(cText);
		int amount = StringToInt(cText);
		
		if (StrContains(cText, "abort", false) == -1) {
			int opponent = GetChallengerIfExists(client);
			if (IsValidClient(opponent)) {
				int stammpoints_challenger = STAMM_GetClientPoints(client);
				int stammpoints_opponent = STAMM_GetClientPoints(opponent);
				int maxamount = (stammpoints_challenger >= stammpoints_opponent ? stammpoints_opponent : stammpoints_challenger);
				
				if (amount <= 0 || amount > maxamount) {
					CPrintToChat(client, "%t%t", "ChatTag", "Challenge with amount failed! Try it again", amount, maxamount);
				} else {
					if (iClient[opponent][eLastOpponent] != client && iClient[opponent][eLastOpponent] > 0) {
						CPrintToChat(client, "%t%t", "ChatTag", "Challenge failed! Challenger challenging another player");
					} else if (GetClientTeam(opponent) == GetClientTeam(client)) {
						CPrintToChat(client, "%t%t", "ChatTag", "Challenge failed! Challenger is in same team");
					} else if (GetClientTeam(opponent) <= 1) {
						CPrintToChat(client, "%t%t", "ChatTag", "Challenge failed! Player is in wrong team", opponent);
					} else if (GetClientTeam(client) <= 1) {
						CPrintToChat(client, "%t%t", "ChatTag", "Challenge failed! Wrong team");
					} else {
						RequestMenu(client, iClient[client][eLastOpponent], amount);
						CPrintToChat(client, "%t%t", "ChatTag", "Challenge with amount has been sent", amount, opponent);
					}
					iClient[client][eWaitingForAmount] = false;
				}
			} else {
				CPrintToChat(client, "%t%t", "ChatTag", "Oops! Invalid client");
				iClient[client][eWaitingForAmount] = false;
			}
		} else {
			RefreshClient(client);
			CPrintToChat(client, "%t%t", "ChatTag", "Challenge has been aborted");
			iClient[client][eWaitingForAmount] = false;
		}
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action Command_SCSettings(int client, int args) {
	SettingsMenu(client);
	return Plugin_Handled;
}

public void SettingsMenu(int client) {
	Menu menu = new Menu(SettingsMenuHandler);
	menu.SetTitle("%t", "Menu Title - Settings");
	
	char buffer[128];
	
	Format(buffer, sizeof(buffer), "%t%t", "Menu Item - On", iClient[client][eInvitesEnabled] ? "Menu Item - Pinned" : "Menu Item - Unpinned");
	menu.AddItem("on", buffer, (iClient[client][eInvitesEnabled] ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT));
	Format(buffer, sizeof(buffer), "%t%t", "Menu Item - Off", !iClient[client][eInvitesEnabled] ? "Menu Item - Pinned" : "Menu Item - Unpinned");
	menu.AddItem("off", buffer, (!iClient[client][eInvitesEnabled] ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT));
	
	menu.Display(client, 15);
}

public int SettingsMenuHandler(Menu menu, MenuAction action, int client, int pos) 
{
	if (action == MenuAction_Select)
	{
		char cItem[5];
		menu.GetItem(pos, cItem, sizeof(cItem));
		
		if (StrEqual(cItem, "on")) {
			iClient[client][eInvitesEnabled] = true;
		} else if (StrEqual(cItem, "off")) {
			iClient[client][eInvitesEnabled] = false;
		}
		SettingsMenu(client);
	}
}

public Action Command_SC(int client, int args) 
{
	int stammpoints = STAMM_GetClientPoints(client);
	int stammpoints_needed = (iMinStammpoints - stammpoints);
	
	if (stammpoints < iMinStammpoints) {
		CPrintToChat(client, "%t%t", "ChatTag", "Oops! Minimum Stammpoints", iMinStammpoints, stammpoints_needed);
		return Plugin_Continue;
	} else if (GetClientTeam(client) <= 1) {
		CPrintToChat(client, "%t%t", "ChatTag", "Oops! Wrong team");
		return Plugin_Continue;
	}
	
	OpponentChoiceMenu(client);
	return Plugin_Handled;
}

public void OpponentChoiceMenu(int client) 
{
	char buffer[128];
	int lobbyid;
	if ((lobbyid = iClient[client][eLobbyId]) >= 0) {
		Menu menu = new Menu(OpponentChoiceCancelMenuHandler);
		menu.SetTitle("%t", "Menu Title - Active challenge", iLobby[lobbyid][eAmount], iClient[client][eLastOpponent]);
		
		Format(buffer, sizeof(buffer), "%t", "Menu Item - Cancel challenge");
		menu.AddItem("cancel", buffer, (iLobby[lobbyid][ePunishment] ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT));
		menu.Display(client, 30);
		return;
	}
	
	Menu menu = new Menu(OpponentChoiceMenuHandler);
	menu.SetTitle("%t", "Menu Title - Choose client");
	
	char cClientId[5];
	int totalclients = 0;
	int team = GetClientTeam(client);
	
	if (iClient[client][eLastOpponent] > 0 && iClient[iClient[client][eLastOpponent]][eLastOpponent] == -1) {
		RefreshClient(client);
	}
	
	for (int i = 1; i <= MaxClients; i++) {
		if (!IsValidClient(i))
			continue;
		
		int iteam = GetClientTeam(i);
		if (!iClient[i][eInvitesEnabled] || iClient[i][eLastOpponent] > 0 || iteam < 2 || iteam == team || i == client)
			continue;
			
		int istammpoints = STAMM_GetClientPoints(i);
		if (istammpoints < iMinStammpoints)
			continue;
		
		Format(buffer, sizeof(buffer), "%t", "Menu Item - Client", i, STAMM_GetClientPoints(i));
		Format(cClientId, sizeof(cClientId), "%i", i);
		menu.AddItem(cClientId, buffer);
		totalclients++;
	}
	
	if (totalclients == 0) {	
		Format(buffer, sizeof(buffer), "%t", "Menu Item - Empty");
		menu.AddItem("x", buffer, ITEMDRAW_DISABLED);
	}
	
	menu.Display(client, 30);
}

public int OpponentChoiceCancelMenuHandler(Menu menu, MenuAction action, int client, int pos) {
	if (action == MenuAction_Select) {
		char cItem[10];
		menu.GetItem(pos, cItem, sizeof(cItem));
		
		int lobbyid;
		
		if (StrEqual(cItem, "cancel") && (lobbyid = iClient[client][eLobbyId]) >= 0 && !iLobby[lobbyid][ePunishment]) {
			int opponent = iClient[client][eLastOpponent];
			if (IsValidClient(opponent)) {
				CPrintToChat(client, "%t%t", "ChatTag", "You cancelled challenge", opponent);
				CPrintToChat(opponent, "%t%t", "ChatTag", "Challenge has been canceled", client);
				
				RefreshClient(iLobby[lobbyid][eChallenger]);
				RefreshClient(iLobby[lobbyid][eOpponent]);
			}
			RefreshLobby(lobbyid);
		}
	}
}

public int OpponentChoiceMenuHandler(Menu menu, MenuAction action, int client, int pos) 
{
	if (action == MenuAction_Select) 
	{
		char cItem[5];
		menu.GetItem(pos, cItem, sizeof(cItem));
		
		int challenger = StringToInt(cItem);
		
		if (IsValidClient(challenger)) {
			iClient[client][eLastOpponent] = challenger;
			iClient[client][eWaitingForAmount] = true;
			
			int stammpoints_challenger = STAMM_GetClientPoints(challenger);
			int stammpoints_client = STAMM_GetClientPoints(client);
			int maxamount = (stammpoints_challenger >= stammpoints_client ? stammpoints_client : stammpoints_challenger);
			
			CPrintToChat(client, "%t%t", "ChatTag", "Type amount of Stammpoints for challenge or abort", maxamount);
		} else {
			CPrintToChat(client, "%t%t", "ChatTag", "Oops! Invalid client");
		}
	}
}

public void RequestMenu(int challenger, int client, int amount) 
{
	Menu menu = new Menu(RequestMenuHandler);
	menu.SetTitle("%t", "Menu Title - Challenge request", challenger, amount);
	
	char buffer[128], cAmount[60];
	iClient[client][eLastOpponent] = challenger;
	
	Format(buffer, sizeof(buffer), "%t", "Menu Item - Deny");
	menu.AddItem("deny", buffer);
	menu.AddItem("deny", buffer);
	Format(buffer, sizeof(buffer), "%t", "Menu Item - Accept");
	Format(cAmount, sizeof(cAmount), "a_%i", amount);
	menu.AddItem(cAmount, buffer);
	
	menu.Display(client, 15);
}

public int RequestMenuHandler(Menu menu, MenuAction action, int client, int pos)
{
	if (action == MenuAction_Select) 
	{
		char cItem[60];
		menu.GetItem(pos, cItem, sizeof(cItem));
		bool refresh = false;
		
		int challenger = iClient[client][eLastOpponent];
		if (IsValidClient(challenger)) {
			if (iClient[challenger][eLastOpponent] != client && iClient[challenger][eLastOpponent] > 0) {
				refresh = true;
				CPrintToChat(client, "%t%t", "ChatTag", "Challenge failed! Challenger challenging another player");
			} else if (GetClientTeam(challenger) == GetClientTeam(client)) {
				refresh = true;
				CPrintToChat(client, "%t%t", "ChatTag", "Challenge failed! Challenger is in same team");
			} else if (GetClientTeam(challenger) <= 1) {
				refresh = true;
				CPrintToChat(challenger, "%t%t", "ChatTag", "Challenge failed! Wrong team");
				CPrintToChat(client, "%t%t", "ChatTag", "Challenge failed! Player is in wrong team", challenger);
			} else if (GetClientTeam(client) <= 1) {
				refresh = true;
				CPrintToChat(client, "%t%t", "ChatTag", "Challenge failed! Wrong team");
				CPrintToChat(challenger, "%t%t", "ChatTag", "Challenge failed! Player is in wrong team", client);
			} else {
				if (StrContains(cItem, "a", false) != -1) 
				{
					int lobbyid;
					strcopy(cItem, sizeof(cItem), cItem[2]);
					int amount = StringToInt(cItem);
					
					if ((lobbyid = GetLobby(challenger, client, amount)) != -1) {
						if (iChallengeStartNextRound == 0) {
							iLobby[lobbyid][eStarted] = true;
							CPrintToChat(challenger, "%t%t", "ChatTag", "Challenge started", iLobby[lobbyid][eAmount], client, lobbyid);
							CPrintToChat(client, "%t%t", "ChatTag", "Challenge started", iLobby[lobbyid][eAmount], challenger, lobbyid);
						} else {
							CPrintToChat(challenger, "%t%t", "ChatTag", "Challenge will be started next round", iLobby[lobbyid][eAmount], client, lobbyid);
							CPrintToChat(client, "%t%t", "ChatTag", "Challenge will be started next round", iLobby[lobbyid][eAmount], challenger, lobbyid);
						}
					} else {
						CPrintToChat(challenger, "%t%t", "ChatTag", "Lobby is not available", client);
						CPrintToChat(client, "%t%t", "ChatTag", "Lobby is not available", challenger);
						refresh = true;
					}
				} else if (StrEqual(cItem, "deny")) {
					CPrintToChat(challenger, "%t%t", "ChatTag", "Challenge denied - challenger", client);
					CPrintToChat(client, "%t%t", "ChatTag", "Challenge denied - opponent", challenger);
					refresh = true;
				}
			}
		} else {
			refresh = true;
			CPrintToChat(challenger, "%t%t", "ChatTag", "Oops! Invalid client");
			CPrintToChat(client, "%t%t", "ChatTag", "Oops! Invalid client");
		}
	
		if (refresh) {
			RefreshClient(challenger);
			RefreshClient(client);
		}
	}
	if (action == MenuAction_Cancel)
	{
		int challenger;
		if ((challenger = iClient[client][eLastOpponent]) > 0) {
			RefreshClient(challenger);
			RefreshClient(client);
			
			CPrintToChat(challenger, "%t%t", "ChatTag", "Opponent didn't react to your challenge", client);
			CPrintToChat(client, "%t%t", "ChatTag", "You didn't react to challenge", challenger);
		}
	}
}

public bool IsValidClient(int client) 
{
	return (1 <= client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

public int GetLobby(int challenger, int opponent, int amount) 
{
	int lobbyid;
	if ((lobbyid = GetFreeLobbyId()) != -1)
	{
		RefreshLobby(lobbyid);
		
		iLobby[lobbyid][eChallenger] = challenger;
		iLobby[lobbyid][eOpponent] = opponent;
		iLobby[lobbyid][eAmount] = amount;
		
		iClient[challenger][eLobbyId] = lobbyid;
		iClient[opponent][eLobbyId] = lobbyid;
		
		return lobbyid;
	}
	
	return -1;
	
}

public int GetFreeLobbyId()
{
	for (int i = 0; i < MAX_LOBBIES; i++)
	{
		if (iLobby[i][eChallenger] <= 0 && iLobby[i][eOpponent] <= 0)
		{
			return i;
		}
	}
	return -1;
}

public int GetChallengerIfExists(int client) {
	for (int i = 1; i <= MaxClients; i++) 
	{
		if (iClient[client][eLastOpponent] == i) 
		{
			return i;
		}
	}
	return -1;
}

public void RefreshClient(int client) 
{
	if (IsValidClient(client)) {
		iClient[client][eLobbyId] = -1;
		iClient[client][eLastOpponent] = -1;
		iClient[client][eWaitingForAmount] = false;
	}
}

public void RefreshLobby(int lobbyid)
{
	iLobby[lobbyid][eChallenger] = 0;
	iLobby[lobbyid][eOpponent] = 0;
	iLobby[lobbyid][eAmount] = 0;
	iLobby[lobbyid][ePunishment] = false;
	iLobby[lobbyid][eStarted] = false;
}


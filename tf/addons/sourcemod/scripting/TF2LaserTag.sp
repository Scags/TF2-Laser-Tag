#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <tf2items>
#include <tf2_stocks>

#define PLUGIN_VERSION 		"1.0.0"
#define RED 2
#define BLU 3

public Plugin myinfo =
{
	name = "[TF2] Laser Tag",
	author = "Scag/Ragenewb",
	description = "Game over man! Game over!",
	version = PLUGIN_VERSION,
	url = "https://github.com/Scags/TF2-Jailbreak-Redux"
};

int
	iDownTime[MAXPLAYERS+1],
	iPoints[MAXPLAYERS+1],
	iKills[MAXPLAYERS+1],
	iTimeLeft,
	tf_arena_use_queue,
	tf_arena_first_blood,
	mp_forcecamera,
	iHalo,
	iLaserBeam
;

bool
	bDowned[MAXPLAYERS+1],
	bHasRapidFire[MAXPLAYERS+1],
	bActiveRound
;

float
	flShotDelay[MAXPLAYERS+1],
	flKillSpree[MAXPLAYERS+1]
;

ConVar
	bEnabled,
	cvDownTime,
	cvPointsPerKill,
	cvKillsForRapidFire,
	cvRapidFireTime,
	cvCapPoints,
	cvCapStartDelay,
	cvCapDelay,
	cvMaxSpeed,
	cvRoundTime,
	cvXCoord,
	cvYCoord,
	cvALPHA,
	cvBLU,
	cvGREEN,
	cvRED
;

// So when is this actually gonna be a thing...
methodmap HUD < Handle
{
	public HUD()
	{
		return view_as< HUD > (CreateHudSynchronizer());
	}
	public int Show( int client, const char[] message, any ... )
	{
		char buffer[32];	// Bleh
		VFormat(buffer, sizeof(buffer), message, 4);
		return ShowSyncHudText(client, this, buffer);
	}
	public void Clear( int client )
	{
		ClearSyncHud(client, this);
	}
};

HUD
	hPointsHud,
	hTimerHud
;

Handle
	hCapDelay,
	hDownTimer[MAXPLAYERS+1],
	hKillSpreeTimer[MAXPLAYERS+1]
;

public void OnPluginStart()
{
	CreateConVar("sm_tf2lasertag_version", PLUGIN_VERSION, "TF2 Laser Tag Plugin Version", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);
	bEnabled = CreateConVar("sm_tf2lasertag_enable", "1", "Enable the TF2 Laser Tag Plugin?", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvDownTime = CreateConVar("sm_tf2lasertag_down_time", "3", "Upon being \"downed\", how long must a player wait until they revive in seconds?", FCVAR_NOTIFY, true, 1.0);
	cvPointsPerKill = CreateConVar("sm_tf2lasertag_points", "100", "How many points does a player receive upon downing another player? (Not scoreboard points)", FCVAR_NOTIFY, true, 1.0);
	cvKillsForRapidFire = CreateConVar("sm_tf2lasertag_rapidfire", "3", "How many kills in a row does a player need in order to get the rapid fire buff?", FCVAR_NOTIFY, true, 2.0);
	cvRapidFireTime = CreateConVar("sm_tf2lasertag_rapidfire_time", "15", "When a player receives rapid fire, how long do they have the perk?", FCVAR_NOTIFY, true, 1.0);
	cvCapPoints = CreateConVar("sm_tf2lasertag_cap_points", "1001", "Players who cap the point receive how many bonus points? 0 to disable capping.", FCVAR_NOTIFY, true, 0.0);
	cvCapStartDelay = CreateConVar("sm_tf2lasertag_cap_start_delay", "30", "Time until cap point is enabled directly after round start. 0 for no delay. Does not apply if \"sm_tf2lasertag_cap_points\" is disabled.", FCVAR_NOTIFY, true, 0.0);
	cvCapDelay = CreateConVar("sm_tf2lasertag_cap_delay", "30", "Time between capping until the point is reenabled. 0 for no delay. Does not apply if \"sm_tf2lasertag_cap_points\" is disabled.", FCVAR_NOTIFY, true, 0.0);
	cvMaxSpeed = CreateConVar("sm_tf2lasertag_max_speed", "300", "Max speed for players while playing", FCVAR_NOTIFY, true, 1.0);
	cvRoundTime = CreateConVar("sm_tf2lasertag_round_time", "300", "Round time length.", FCVAR_NOTIFY, true, 1.0);
	cvXCoord = CreateConVar("sm_tf2lasertag_xcoord", "0.80", "X Coordinate for points HUD.", FCVAR_NOTIFY, true, -1.0, true, 1.0);
	cvYCoord = CreateConVar("sm_tf2lasertag_ycoord", "0.60", "Y Coordinate for points HUD.", FCVAR_NOTIFY, true, -1.0, true, 1.0);
	cvALPHA = CreateConVar("sm_tf2lasertag_alpha", "0", "Alpha magnitude for points HUD.", FCVAR_NOTIFY, true, 0.0, true, 255.0);
	cvBLU = CreateConVar("sm_tf2lasertag_blu", "255", "Blue magnitude for points HUD.", FCVAR_NOTIFY, true, 0.0, true, 255.0);
	cvGREEN = CreateConVar("sm_tf2lasertag_green", "150", "Green magnitude for points HUD.", FCVAR_NOTIFY, true, 0.0, true, 255.0);
	cvRED = CreateConVar("sm_tf2lasertag_red", "0", "Red magnitude for points HUD.", FCVAR_NOTIFY, true, 0.0, true, 255.0);

	AutoExecConfig(true, "TF2LaserTag");

	hTimerHud = new HUD();
	hPointsHud = new HUD();

	for (int i = MaxClients; i; --i)
		if (IsClientInGame(i))
			OnClientPutInServer(i);

	HookEvent("arena_round_start", OnRoundStart);
	// HookEvent("player_death", OnPlayerDied, EventHookMode_Pre);
	HookEvent("teamplay_point_captured", OnPointCap);
	HookEvent("player_spawn", OnSpawn);
	HookEvent("teamplay_round_win", OnRoundEnd);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_PreThink, OnPreThink);

	ResetVars(client);
}

public void OnMapStart()
{
	tf_arena_use_queue = FindConVar("tf_arena_use_queue").IntValue;
	tf_arena_first_blood = FindConVar("tf_arena_first_blood").IntValue;
	mp_forcecamera = FindConVar("mp_forcecamera").IntValue;
	FindConVar("tf_arena_use_queue").SetInt(0);
	FindConVar("tf_arena_first_blood").SetInt(0);
	FindConVar("mp_forcecamera").SetInt(0);

	iHalo = PrecacheModel("materials/sprites/glow01.vmt", true);
	iLaserBeam = PrecacheModel("materials/sprites/laserbeam.vmt", true);

	char s[PLATFORM_MAX_PATH];
	for (int i = 1; i <= 4; i++)
	{
		if (i <= 2)
		{
			Format(s, sizeof(s), "weapons/bison_main_shot_0%d.wav", i);
			PrecacheSound(s, true);
		}

		Format(s, sizeof(s), "player/resistance_light%d.wav", i);
		PrecacheSound(s, true);
	}
	PrecacheSound("weapons/buffed_off.wav", true);
}

public void OnMapEnd()
{
	FindConVar("tf_arena_use_queue").SetInt(tf_arena_use_queue);
	FindConVar("tf_arena_first_blood").SetInt(tf_arena_first_blood);
	FindConVar("mp_forcecamera").SetInt(mp_forcecamera);
}

//---------------------
//-------EVENTS--------
//---------------------
public Action OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!bEnabled.BoolValue)
		return Plugin_Continue;


	for (int i = MaxClients; i; --i)
		if (IsClientInGame(i))
			ResetVars(i);

	iTimeLeft = cvRoundTime.IntValue;
	CreateTimer(1.0, RoundTimer, _, TIMER_REPEAT);

	if (cvCapPoints.BoolValue)
		SetArenaCapEnableTime(cvCapStartDelay.FloatValue);

	bActiveRound = true;

	return Plugin_Continue;
}

public Action OnPointCap(Event event, const char[] name, bool dontBroadcast)
{
	if (!bEnabled.BoolValue || !cvCapPoints.BoolValue)
		return Plugin_Continue;

	// int team = event.GetInt("team");
	char strCappers[MAXPLAYERS];
	event.GetString("cappers", strCappers, MAXPLAYERS);

	int i;
	while (strCappers[i] != '\0')
	{
		if (IsClientValid(i))
			iPoints[i] += cvCapPoints.IntValue;
		i++;
	}

	SetCapOwner(0, cvCapDelay.FloatValue);

	return Plugin_Continue;
}

public Action OnSpawn(Event event, const char[] name, bool dontBroadcast)
{
	if (!bEnabled.BoolValue)
		return Plugin_Continue;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClientValid(client))
		return Plugin_Continue;

	TF2_SetPlayerClass(client, TFClass_Soldier);
	TF2_RegeneratePlayer(client);
	TF2_RemoveAllWeapons(client);
	SetClientOverlay(client, "");

	int wep = TF2_SpawnWeapon(client, "tf_weapon_raygun", 442, GetRandomInt(0, 100), 10, "");
	SetEntPropFloat(wep, Prop_Send, "m_flNextPrimaryAttack", GetGameTime()+9999.0);	// Bleh
	SetEntPropEnt(client, Prop_Send, "m_hActiveWeapon", wep);
	SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);

	return Plugin_Continue;
}

public Action OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!bEnabled.BoolValue)
		return Plugin_Continue;

	int iTop3[3], i;

	for (i = MaxClients; i; --i)
	{
		if (!IsClientInGame(i))
			continue;

		SetClientOverlay(i, "");

		if (iPoints[i] <= 0)
			continue;

		if (iPoints[i] >= iPoints[iTop3[0]])
		{
			iTop3[2] = iTop3[1];
			iTop3[1] = iTop3[0];
			iTop3[0] = i;
		}
		else if (iPoints[i] >= iPoints[iTop3[1]])
		{
			iTop3[2] = iTop3[1];
			iTop3[1] = i;
		}
		else if (iPoints[i] >= iPoints[iTop3[2]])
			iTop3[2] = i;
	}

	char s1[32], s2[32], s3[32];
	if (IsClientValid(iTop3[0]) && GetClientTeam(iTop3[0]) > 1)
		GetClientName(iTop3[0], s1, 32);
	else
	{
		strcopy(s1, 32, "---");
		iTop3[0] = 0;
	}
	
	if (IsClientValid(iTop3[1]) && GetClientTeam(iTop3[1]) > 1)
		GetClientName(iTop3[1], s2, 32);
	else
	{
		strcopy(s2, 32, "---");
		iTop3[1] = 0;
	}
	
	if (IsClientValid(iTop3[2]) && GetClientTeam(iTop3[2]) > 1)
		GetClientName(iTop3[2], s3, 32);
	else
	{
		strcopy(s3, 32, "---");
		iTop3[2] = 0;
	}

	SetHudTextParams(-1.0, 0.4, 10.0, 255, 255, 255, 255);
	PrintCenterTextAll("");

	for (i = MaxClients; i; --i)
		if (IsClientInGame(i))
			if (!(GetClientButtons(i) & IN_SCORE))
				ShowHudText(i, -1, "Top scorers this round:\n1)%i - %s\n2)%i - %s\n3)%i - %s\n\nYour score: %i", iPoints[iTop3[0]], s1, iPoints[iTop3[1]], s2, iPoints[iTop3[2]], s3, iPoints[i]);

	delete hCapDelay;
	bActiveRound = false;

	return Plugin_Continue;
}

public void OnPreThink(int client)
{
	if (!bEnabled.BoolValue)
		return;

	SetHudTextParams(cvXCoord.FloatValue, cvYCoord.FloatValue, 0.1, cvRED.IntValue, cvGREEN.IntValue, cvBLU.IntValue, cvALPHA.IntValue);
	hPointsHud.Show(client, "Points:\n%d", iPoints[client]);
	
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", cvMaxSpeed.FloatValue);

	if (bDowned[client])
		return;

	float currtime = GetGameTime();
	if (currtime < flShotDelay[client])
		return;

	int buttons = GetClientButtons(client);
	if (buttons & IN_ATTACK && bActiveRound)
	{
		int wep = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if (wep <= MaxClients || !IsValidEntity(wep))
			return;

		if (GetEntProp(wep, Prop_Send, "m_iItemDefinitionIndex") != 442)
			return;
		
		float vecOrigin[3], vecAng[3];
		GetClientEyeAngles(client, vecAng);
		GetClientEyePosition(client, vecOrigin);
		Handle trace = TR_TraceRayFilterEx(vecOrigin, vecAng, MASK_NPCSOLID | MASK_PLAYERSOLID, RayType_Infinite, KillOnTrace, client);
		
		if (!TR_DidHit(trace))
		{
			delete trace;
			return;
		}
		
		float vecEnd[3];
		TR_GetEndPosition(vecEnd, trace);
		delete trace;

		char s[PLATFORM_MAX_PATH];
		Format(s, sizeof(s), "weapons/bison_main_shot_0%d.wav", GetRandomInt(1, 2));
		EmitSoundToAll(s, client, _, _, _, 0.5);

		vecOrigin[2] -= 5.0;	// Shooting lasers out of your eyes seems a bit out of place in this context

		TE_SetupBeamPoints(vecOrigin, vecEnd, iLaserBeam, 0, 0, 0, 0.1, 0.5, 0.0, 1, 0.0, GetClientTeam(client) == BLU ? {0, 100, 255, 255} : {255, 100, 0, 255}, 0);
		TE_SendToAll();

		TE_SetupGlowSprite(vecOrigin, iHalo, 0.1, 0.25, 30);
		TE_SendToAll();

		flShotDelay[client] = currtime + (bHasRapidFire[client] ? 0.3 : 1.0);
	}
}

public bool KillOnTrace(int ent, int mask, any data)
{
	if (0 < ent <= MaxClients)
	{
		if (ent == data)
			return false;

		if (GetClientTeam(ent) == GetClientTeam(data))
			return true;

		if (bDowned[ent])
			return true;

		bDowned[ent] = true;
		if (bHasRapidFire[ent])
		{
			delete hKillSpreeTimer[ent];
			TF2_RemoveCondition(ent, TFCond_Kritzkrieged);
			bHasRapidFire[ent] = false;
		}

		EmitSoundToClient(ent, "weapons/buffed_off.wav");
		iDownTime[ent] = cvDownTime.IntValue;
		hDownTimer[ent] = CreateTimer(1.0, DownTimer, GetClientUserId(ent), TIMER_REPEAT);
		PrintCenterText(ent, "%d", iDownTime[ent]);

		SetEntityRenderMode(ent, RENDER_TRANSCOLOR);
		SetEntityRenderColor(ent, 35, 35, 35, 255);	// Grayish

		SetVariantInt(1);
		AcceptEntityInput(ent, "SetForcedTauntCam");
		SetClientOverlay(ent, "debug/yuv");

		iPoints[data] += cvPointsPerKill.IntValue;

		char s[PLATFORM_MAX_PATH];
		Format(s, sizeof(s), "player/resistance_light%d.wav", GetRandomInt(1, 4));
		EmitSoundToClient(data, s);

		if (bHasRapidFire[data])
			return true;

		float currtime = GetGameTime();
		if (currtime <= flKillSpree[data])
			iKills[data]++;
		else iKills[data] = 0;

		if (iKills[data] == cvKillsForRapidFire.IntValue)
		{
			bHasRapidFire[data] = true;
			float time = cvRapidFireTime.FloatValue;
			hKillSpreeTimer[data] = CreateTimer(time, KillSpreeTimer, GetClientUserId(data), TIMER_FLAG_NO_MAPCHANGE);
			TF2_AddCondition(data, TFCond_Kritzkrieged, time);
		}
		else flKillSpree[data] = currtime + 10;
	}
	return true;
}

public Action DownTimer(Handle timer, any id)
{
	if (!bActiveRound)
		return Plugin_Stop;

	int client = GetClientOfUserId(id);
	if (!IsClientInGame(client))
		return Plugin_Stop;

	SetClientOverlay(client, "debug/yuv");
	iDownTime[client]--;

	if (!iDownTime[client])
	{
		PrintCenterText(client, "");
		bDowned[client] = false;
		SetEntityRenderColor(client);
		SetEntityRenderMode(client, RENDER_NORMAL);
		SetClientOverlay(client, "");

		SetVariantInt(0);
		AcceptEntityInput(client, "SetForcedTauntCam");
		return Plugin_Stop;
	}

	PrintCenterText(client, "%d", iDownTime[client]);

	return Plugin_Continue;
}

public Action KillSpreeTimer(Handle timer, any id)
{
	int client = GetClientOfUserId(id);
	if (!IsClientInGame(client))
		return Plugin_Continue;

	TF2_RemoveCondition(client, TFCond_Kritzkrieged);
	bHasRapidFire[client] = false;
	return Plugin_Continue;
}

public Action RoundTimer(Handle timer)
{
	if (!bActiveRound)
		return Plugin_Stop;

	int time = iTimeLeft;
	iTimeLeft--;
	char strTime[6];
	
	if (time / 60 > 9)
		IntToString(time / 60, strTime, 6);
	else Format(strTime, 6, "0%i", time / 60);
	
	if (time % 60 > 9)
		Format(strTime, 6, "%s:%i", strTime, time % 60);
	else Format(strTime, 6, "%s:0%i", strTime, time % 60);
	
	SetHudTextParams(-1.0, 0.17, 1.1, 255, 255, 255, 255);
	for (int i = MaxClients; i; --i)
		if (IsClientInGame(i))
			hTimerHud.Show(i, strTime);

	switch (time)
	{
		case 60:EmitSoundToAll("vo/announcer_ends_60sec.mp3");
		case 30:EmitSoundToAll("vo/announcer_ends_30sec.mp3");
		case 10:EmitSoundToAll("vo/announcer_ends_10sec.mp3");
		case 1, 2, 3, 4, 5:
		{
			char sound[PLATFORM_MAX_PATH];
			Format(sound, PLATFORM_MAX_PATH, "vo/announcer_ends_%isec.mp3", time);
			EmitSoundToAll(sound);
		}
		case 0:
		{
			ForceRoundEnd();
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}

public Action EnableCap(Handle timer)
{
	SetControlPoint(true);
	return Plugin_Continue;
}

public void ResetVars(int client)
{
	iDownTime[client] = 0;
	iPoints[client] = 0;
	iKills[client] = 0;
	bDowned[client] = false;
	flShotDelay[client] = 0.0;
	flKillSpree[client] = 0.0;
	if (bHasRapidFire[client])
	{
		delete hKillSpreeTimer[client];
		TF2_RemoveCondition(client, TFCond_Kritzkrieged);
		bHasRapidFire[client] = false;
	}
}

//---------------------
//-------STOCKS--------
//---------------------
stock void SetArenaCapEnableTime(float time)
{
	int ent = -1;
	char strTime[32]; FloatToString(time, strTime, sizeof(strTime));
	if ((ent = FindEntityByClassname(-1, "tf_logic_arena")) != -1)
		DispatchKeyValue(ent, "CapEnableDelay", strTime);
}

stock void SetControlPoint(bool enable)
{
	int CPm = -1;
	while ((CPm = FindEntityByClassname(CPm, "team_control_point")) != -1)
	{
		if (CPm > MaxClients && IsValidEdict(CPm))
		{
			AcceptEntityInput(CPm, (enable ? "ShowModel" : "HideModel"));
			SetVariantInt(enable ? 0 : 1);
			AcceptEntityInput(CPm, "SetLocked");
		}
	}
}

stock bool IsClientValid(int client)
{
	return ((0 < client <= MaxClients) && IsClientInGame(client));
}

stock int TF2_SpawnWeapon(const int client, char[] name, int index, int level, int qual, char[] att)
{
	Handle hWeapon = TF2Items_CreateItem(OVERRIDE_ALL|FORCE_GENERATION);
	if (hWeapon == null)
		return -1;
	
	TF2Items_SetClassname(hWeapon, name);
	TF2Items_SetItemIndex(hWeapon, index);
	TF2Items_SetLevel(hWeapon, level);
	TF2Items_SetQuality(hWeapon, qual);
	char atts[32][32];
	int count = ExplodeString(att, " ; ", atts, 32, 32);
	count &= ~1;
	if (count > 0)
	{
		TF2Items_SetNumAttributes(hWeapon, count/2);
		int i2;
		for (int i = 0 ; i < count ; i += 2)
		{
			TF2Items_SetAttribute(hWeapon, i2, StringToInt(atts[i]), StringToFloat(atts[i+1]));
			i2++;
		}
	}
	else TF2Items_SetNumAttributes(hWeapon, 0);

	int entity = TF2Items_GiveNamedItem(client, hWeapon);
	delete hWeapon;
	EquipPlayerWeapon(client, entity);
	return entity;
}
// Props to DarthNinja
stock void ForceRoundEnd(int team = 0)
{
	int iEnt = -1;
	iEnt = FindEntityByClassname(iEnt, "game_round_win");
	
	if (iEnt < 1)
	{
		iEnt = CreateEntityByName("game_round_win");
		if (IsValidEntity(iEnt))
			DispatchSpawn(iEnt);
		else
		{
			LogError("Unable to find nor create a game_round_win entity!");
			return;
		}
	}

	SetVariantInt(team);
	AcceptEntityInput(iEnt, "SetTeam");
	AcceptEntityInput(iEnt, "RoundWin");
}

stock void SetCapOwner(int iCapTeam, float flEnableTime)
{
	int i = -1;
	int cap_master = FindEntityByClassname(-1, "team_control_point_master");
	while ((i = FindEntityByClassname(i, "team_control_point")) != -1)
	{
		if (IsValidEntity(i))
		{	// From Arena:Respawn
			SetVariantInt(iCapTeam);
			AcceptEntityInput(i, "SetOwner", -1, cap_master);	// Must have team_control_point_master as the activator, less it will just ignore the Input
			SetVariantInt(1);
			AcceptEntityInput(i, "SetLocked");
			hCapDelay = CreateTimer(flEnableTime, EnableCap);
		}
	}
}

stock void SetClientOverlay(int client, const char[] strOverlay)
{
	int flags = GetCommandFlags("r_screenoverlay") & (~FCVAR_CHEAT);
	SetCommandFlags("r_screenoverlay", flags);
	ClientCommand(client, "r_screenoverlay \"%s\"", strOverlay);
}
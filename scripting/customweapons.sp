#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo =
{
	name = "Custom Weapons",
	author = "Empyrean",
	description = "Change weapon's view, world and drop models.",
	version = "0.1",
};

int g_ViewModelId[MAXPLAYERS + 1];

ArrayList g_ModelClasses;
ArrayList g_ModelVIndicies;
ArrayList g_ModelWIndicies;
ArrayList g_ModelWDIndicies;

KeyValues kv;

public void OnPluginStart() {
	g_ModelClasses = new ArrayList(ByteCountToCells(64));
	g_ModelVIndicies = new ArrayList(ByteCountToCells(16));
	g_ModelWIndicies = new ArrayList(ByteCountToCells(16));
	g_ModelWDIndicies = new ArrayList(ByteCountToCells(128));
	
	LoadKV();
	
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_PostNoCopy);
	
	for(int i = 1; i <= MaxClients; i++)
		if(IsValidClient(i))
			OnClientPutInServer(i);
}

public void OnClientPutInServer(int client) {
	SDKHook(client, SDKHook_WeaponSwitchPost, OnClientWeaponSwitchPost);
	SDKHook(client, SDKHook_WeaponDropPost, OnClientWeaponDropPost);
}

public void OnClientDisconnect(int client) {
	SDKUnhook(client, SDKHook_WeaponSwitchPost, OnClientWeaponSwitchPost);
	SDKUnhook(client, SDKHook_WeaponDropPost, OnClientWeaponDropPost);
}

public void OnClientWeaponSwitchPost(int client, int weapon)
{
	if(!IsValidEdict(weapon))
		return;

	char classname[64];
	char compareclass[64];
	GetEntityClassname(weapon, classname, sizeof(classname));
	
	int index = -1;
	for (int i = 0; i < GetArraySize(g_ModelClasses); i++) {
		GetArrayString(g_ModelClasses, i, compareclass, sizeof(compareclass));
		if (StrEqual(classname, compareclass))
			index = i;
	}
	
	if(index <= -1)
		return;

	if(GetArrayCell(g_ModelVIndicies, index) <= 0)
		return;

	SetEntProp(weapon, Prop_Send, "m_nModelIndex", 0);
	SetEntProp(g_ViewModelId[client], Prop_Send, "m_nModelIndex", GetArrayCell(g_ModelVIndicies, index));

	if(GetArrayCell(g_ModelWIndicies, index) <= 0)
		return;

	SetEntProp(GetEntPropEnt(weapon, Prop_Send, "m_hWeaponWorldModel"), Prop_Send, "m_nModelIndex", GetArrayCell(g_ModelWIndicies, index));
	
	//SetEntProp(g_ViewModelId[client], Prop_Data, "m_nViewModelIndex", index);
	//ChangeEdictState(g_ViewModelId[client], FindDataMapInfo(g_ViewModelId[client], "m_nViewModelIndex"));
}

public void OnClientWeaponDropPost(int client, int weapon) {
	if(!IsValidClient(client))
		return;

	CreateTimer(0.0, TimerSetWorldModel, EntIndexToEntRef(weapon));
}

public Action TimerSetWorldModel(Handle timer, int ref) {
	int weapon = EntRefToEntIndex(ref);
	if(!IsValidEdict(weapon))
		return Plugin_Stop;
		
	char classname[64];
	char compareclass[64];
	GetEntityClassname(weapon, classname, sizeof(classname));
	
	int index = -1;
	for (int i = 0; i < GetArraySize(g_ModelClasses); i++) {
		GetArrayString(g_ModelClasses, i, compareclass, sizeof(compareclass));
		if (StrEqual(classname, compareclass))
			index = i;
	}
	
	if(index <= -1)
		return Plugin_Stop;
		
	char model[128];
	GetArrayString(g_ModelWDIndicies, index, model, sizeof(model));
	SetEntityModel(weapon, model);
	return Plugin_Stop;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dB) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(!IsValidClient(client))
		return;

	g_ViewModelId[client] = Weapon_GetViewModelIndex(client, -1);
}

public void OnMapStart() {
	PrecacheModels();
	DownloadModels();
}

// LOAD KV
void LoadKV() {
	kv.Close();
	
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/empyrean/customweapons.txt");
	
	kv = new KeyValues("CustomModels");
	kv.ImportFromFile(path);
}

// SOME METHODS
int Weapon_GetViewModelIndex(int client, int sIndex) {
	while ((sIndex = FindEntityByClassname2(sIndex, "predicted_viewmodel")) != -1)
	{
		int owner = GetEntPropEnt(sIndex, Prop_Send, "m_hOwner");
		if (owner != client)
			continue;

		return sIndex;
	}
	return -1;
}

int FindEntityByClassname2(int startEnt, char[] classname) {
	while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;
	return FindEntityByClassname(startEnt, classname);
}  

bool IsValidClient(int client) {
	if (!(1 <= client <= MaxClients) || !IsClientConnected(client) || !IsClientInGame(client)) return false;
	return true;
}

void PrecacheModels() {
	char model[256];
	char section[64];
	
	if(kv.GotoFirstSubKey())
		do {
			kv.GetSectionName(section, sizeof(section));
			g_ModelClasses.PushString(section);
			
			kv.GetString("v_model", model, sizeof(model));
			if(!StrEqual(model, "")) {
				int x = PrecacheModel(model);
				if(x > 0) g_ModelVIndicies.Push(x);
			} else g_ModelVIndicies.Push(-1);
			
			kv.GetString("w_model", model, sizeof(model));
			if(!StrEqual(model, "")) {
				int y = PrecacheModel(model);
				if(y > 0) g_ModelWIndicies.Push(y);
			} else g_ModelWIndicies.Push(-1);
	
			kv.GetString("wd_model", model, sizeof(model));
			if(!StrEqual(model, "")) {
				int z = PrecacheModel(model);
				if(z > 0) g_ModelWDIndicies.PushString(model);	
			} else g_ModelWDIndicies.Push(-1);

		} while (kv.GotoNextKey());
		
	kv.Close();
}

void DownloadModels() {
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "configs/empyrean/downloads.txt");
	
	Handle file = OpenFile(path, "r");
	
	char line[192];
	if(file != INVALID_HANDLE) {
		while (!IsEndOfFile(file)) {
			if (!ReadFileLine(file, line, sizeof(line)))
				break;
			
			TrimString(line);
			if( strlen(line) > 0 && FileExists(line))
				AddFileToDownloadsTable(line);
		}

		CloseHandle(file);
	}
	else
		LogError("[SM] 'configs/empyrean/downloads.txt' not found!");
}
/**
Group Assigner is not a core plugin.
This plugin is a helper to allow you to define steamids to certain groups when they connect to the server.
**/
#pragma semicolon 1
#include <GroupHandler>

#define CONFIG_FILE     "configs/player_groups.cfg"

ConVar cProfile;
ArrayList profiles;
KeyValues kvPlayers = null;
bool ignoreThisSection = false;

#define PLUGIN_VERSION "1.1.1"
public Plugin myinfo = {
    name = "Group Assigner",
    author = "Mitch",
    description = "Plugin assigns certain steamids to groups listen in the keyvalues.",
    version = PLUGIN_VERSION,
    url = "mtch.tech"
};

public void OnPluginStart() {
    CreateConVar("sm_groupassigner_version", PLUGIN_VERSION, "Group Assigner Version", FCVAR_DONTRECORD);
    cProfile = CreateConVar("sm_groupassigner_profile", "", "Current server profile, for multiple separate with comma");
    AutoExecConfig(true, "GroupAssigner");
}

public void OnLibraryAdded(const char[] name) {
    if(StrEqual(name, "GroupHandler") && kvPlayers != null) {
        for(int client = 1; client <= MaxClients; client++) {
            if(IsClientAuthorized(client) && IsClientAuthorized(client) && !IsFakeClient(client)) {
                OnClientPostAdminCheck(client);
            }
        }
    }
}

public void OnConfigsExecuted() {
    ParseConfig();
}

public OnClientPostAdminCheck(client) {
    AssignPlayerGroups(client);
}

public void AssignPlayerGroups(int client) {
    if(kvPlayers == null || IsFakeClient(client)) {
        return;
    }
    // Get the player's steamid.
    char authId[32];
    if(!GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId))) {
        return;
    }
    if(kvPlayers.GetDataType(authId) != KvData_String) {
        return;
    }
    // Find the player's steamid in the string map.
    char buffer[512];
    kvPlayers.GetString(authId, buffer, sizeof(buffer), "");
    // Split the string into multiple groups.
    TrimString(buffer);
    if(buffer[0] == '\0') {
        return;
    }
    char groupPart[32];
    int strLength = strlen(buffer);
    for(int bufferPos = 0; bufferPos < strLength;) {
        int tempPos = StrContains(buffer[bufferPos], ",", false);
        if(tempPos == -1) {
            tempPos = strLength;
        }
        strcopy(groupPart, tempPos+1, buffer[bufferPos]);
        bufferPos += tempPos+1;
        TrimString(groupPart);
        if(strlen(groupPart) > 0) {
            GroupHandler_Assign(client, groupPart);
        }
    }
}

public void ParseConfig() {
    delete kvPlayers;
    delete profiles;
    //Parse Profile first to get list of profiles.
    char profileBuffer[512];
    cProfile.GetString(profileBuffer, sizeof(profileBuffer));
    TrimString(profileBuffer);
    profiles = new ArrayList(ByteCountToCells(32));
    char profilePart[32];
    int strLength = strlen(profileBuffer);
    for(int bufferPos = 0; bufferPos < strLength;) {
        int tempPos = StrContains(profileBuffer[bufferPos], ",", false);
        if(tempPos == -1) {
            tempPos = strLength;
        }
        strcopy(profilePart, tempPos+1, profileBuffer[bufferPos]);
        bufferPos += tempPos+1;
        TrimString(profilePart);
        if(strlen(profilePart) > 0) {
            profiles.PushString(profilePart);
        }
    }
    if(profiles.Length <= 0) {
        delete profiles;
    }
    char filepath[256];
    BuildPath(Path_SM, filepath, sizeof(filepath), CONFIG_FILE);
    if(!FileExists(filepath, false)) {
        //KeyValue config does not exist, create a template.
        File tempConfig = OpenFile(filepath, "w");
        tempConfig.WriteString("\"GroupAssigner\"\n{\n\t//Config auto generated, for more documentation see:\n\t//https://github.com/MitchDizzle/GroupHandlerAPI/blob/master/GroupAssigner.md\n\n\t//\"STEAM_ID_0\"\t\t\"Group1,Group2,Group3\" //Player 1\n\t\"Server 1\"\n\t{\n\t\t//\"STEAM_ID_0\"\t\t\"Group4,Group5\" //Player 1 has more groups when on 'Server 1'\n\t}\n}\n", false);
        tempConfig.Close();
    }
    // Load KV from File
    kvPlayers = new KeyValues("");
    SMCParser parser = new SMCParser();
    parser.OnEnterSection = EnterSectionParse;
    parser.OnKeyValue = KeyValueParse;
    parser.OnLeaveSection = LeaveSectionParse;
    SMCError parseError = parser.ParseFile(filepath);
    delete profiles; //Clear the global profile arraylist.
    delete parser;
    if(parseError != SMCError_Okay) {
        delete kvPlayers;
        SetFailState("Parser error: %i (%s)", parseError, filepath);
    }
    for(int client = 1; client <= MaxClients; client++) {
        if(IsClientAuthorized(client) && !IsFakeClient(client)) {
            OnClientPostAdminCheck(client);
        }
    }
}

public SMCResult EnterSectionParse(SMCParser smc, const char[] name, bool opt_quotes) {
    ignoreThisSection = kvPlayers == null || !(StrEqual(name, "GroupAssigner") || (profiles != null && profiles.FindString(name) != -1));
}

public SMCResult LeaveSectionParse(SMCParser smc) {
    ignoreThisSection = false;
}

public SMCResult KeyValueParse(SMCParser smc, const char[] key, const char[] value, bool key_quotes, bool value_quotes) {
    if(ignoreThisSection || kvPlayers == null) {
        return SMCParse_Continue;
    }
    
    if(kvPlayers.GetDataType(key) == KvData_None) {
        //User wasn't found in kvPlayers, let's skip the rest and just add them now.
        kvPlayers.SetString(key, value);
        if(StrContains(key, "STEAM")) {
            GroupId groupId = FindAdmGroup(key);
            if(groupId != INVALID_GROUP_ID)
                GroupHandler_GroupCreated2(key, groupId);
        }
        return SMCParse_Continue;
    }
    char groupBuffer[512];
    kvPlayers.GetString(key, groupBuffer, sizeof(groupBuffer), "");
    Format(groupBuffer, sizeof(groupBuffer), "%s,%s", groupBuffer, value);
    kvPlayers.SetString(key, groupBuffer);
    if(StrContains(key, "STEAM")) {
        GroupId groupId = FindAdmGroup(key);
        if(groupId != INVALID_GROUP_ID)
            GroupHandler_GroupCreated2(key, groupId);
    }
    return SMCParse_Continue;
}

void GroupHandler_GroupCreated2(const char[] name, GroupId id) {
    if(kvPlayers.GetDataType(name) != KvData_String) {
        return;
    }
    
    char buffer[512];
    kvPlayers.GetString(name, buffer, sizeof(buffer));
    // Split the string into multiple groups.
    TrimString(buffer);
    if(buffer[0] == '\0') {
        return;
    }
    
    char overridePart[32];
    int strLength = strlen(buffer);
    for(int bufferPos = 0; bufferPos < strLength; )
    {
        int tempPos = StrContains(buffer[bufferPos], ",", false);
        if(tempPos == -1) {
            tempPos = strLength;
        }
        strcopy(overridePart, tempPos+1, buffer[bufferPos]);
        bufferPos += tempPos+1;
        TrimString(overridePart);
        if(strlen(overridePart) > 0) {
            AddAdmGroupCmdOverride(id, overridePart, Override_Command, Command_Allow);
        }
    }
}

public void GroupHandler_GroupCreated(char[] name, GroupId id) {
    GroupHandler_GroupCreated2(name, id);
}
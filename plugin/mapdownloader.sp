#pragma semicolon 1
#include <sourcemod>
#include <cURL>
#include <tf2>

public Plugin:myinfo =
{
	name = "map downloader",
	author = "Icewind",
	description = "Automatically download missing maps",
	version = "0.2",
	url = "https://spire.tf"
};

new CURL_Default_opt[][2] = {
	{_:CURLOPT_NOSIGNAL,1},
	{_:CURLOPT_NOPROGRESS,1},
	{_:CURLOPT_TIMEOUT,300},
	{_:CURLOPT_CONNECTTIMEOUT,120},
	{_:CURLOPT_USE_SSL,CURLUSESSL_TRY},
	{_:CURLOPT_SSL_VERIFYPEER,0},
	{_:CURLOPT_SSL_VERIFYHOST,0},
	{_:CURLOPT_VERBOSE,0}
};

#define CURL_DEFAULT_OPT(%1) curl_easy_setopt_int_array(%1, CURL_Default_opt, sizeof(CURL_Default_opt))

#define TEMP_PREFIX ".mapdownloader"

new Handle:g_hCvarUrl = INVALID_HANDLE;

public OnPluginStart() {
	g_hCvarUrl = CreateConVar("sm_map_download_base", "https://fastdl.serveme.tf/maps", "map download url", FCVAR_PROTECTED);

	RegAdminCmd("sm_map", HandleSmMapAction, ADMFLAG_CHANGEMAP, "sm_map <map>");
	RegServerCmd("changelevel", HandleChangeLevelAction);

	DeleteStaleTempFiles();
}

public DeleteStaleTempFiles() {
	decl String:prefix[64];
	Format(prefix, sizeof(prefix), "%s_%d_", TEMP_PREFIX, GetConVarInt(FindConVar("hostport")));

	new Handle:dir = OpenDirectory("maps");
	if (dir == INVALID_HANDLE) {
		return;
	}

	decl String:name[PLATFORM_MAX_PATH];
	decl String:path[PLATFORM_MAX_PATH];
	new FileType:type;
	while (ReadDirEntry(dir, name, sizeof(name), type)) {
		if (type == FileType_File && StrContains(name, prefix) == 0) {
			Format(path, sizeof(path), "maps/%s", name);
			DeleteFile(path);
		}
	}
	CloseHandle(dir);
}

public Action:HandleSmMapAction(_client, args) {
    if (args < 1) {
        return Plugin_Handled;
    }

    return HandleChangeLevelAction(args);
}

public Action:HandleChangeLevelAction(args) {
	new String:arg[PLATFORM_MAX_PATH];
	char displayName[PLATFORM_MAX_PATH];

	GetCmdArg(1, arg, sizeof(arg));

	if (arg[strlen(arg) - 1] == ':') {
		PrintToChatAll("Invalid input, to input urls, replace '://' with ':/'");
		return Plugin_Handled;
	}

	if (StrContains(arg, ":/") > 0) {
		ChangeLevelUrl(arg);
		return Plugin_Handled;
	}


	if (FindMap(arg, displayName, sizeof(displayName)) != FindMap_NotFound) {
		return Plugin_Continue;
	} else {
	    decl String:path[PLATFORM_MAX_PATH];
	    Format(path, sizeof(path), "maps/%s.bsp", arg);
		PrintToChatAll("Map %s not found, trying to download", arg);
		DownloadMap(arg, path);
		return Plugin_Handled;
	}
}

public ChangeLevelUrl(String:url[PLATFORM_MAX_PATH]) {
	decl String:path[PLATFORM_MAX_PATH];
	decl String:mapFull[PLATFORM_MAX_PATH];
	decl String:map[PLATFORM_MAX_PATH];
	decl String:fullUrl[512];
	strcopy(fullUrl, sizeof(fullUrl), url);

	// allow http:/foo as alias for http://foo to work around source messing with the arguments
	if (StrContains(fullUrl, "://") == -1) {
		ReplaceString(fullUrl, sizeof(fullUrl), ":/", "://");
	}

	int index = FindCharInString(fullUrl, '/', true);
	if (index == -1) {
		PrintToServer("Invalid url: %s", fullUrl);
		return;
	}
	strcopy(mapFull, sizeof(mapFull), url[index]);

	if (FindCharInString(mapFull, '.') > 0) {
		SplitString(mapFull, ".", map, sizeof(map));
	}

	Format(path, sizeof(path), "maps/%s.bsp", map);

	PrintToServer("Saving %s to %s", fullUrl, path);

	DownloadMapUrl(map, fullUrl, path);
}

public DownloadMap(String:map[PLATFORM_MAX_PATH], String:targetPath[PLATFORM_MAX_PATH]) {
	decl String:fullUrl[512];
	decl String:BaseUrl[PLATFORM_MAX_PATH];
	GetConVarString(g_hCvarUrl, BaseUrl, sizeof(BaseUrl));
	Format(fullUrl, sizeof(fullUrl), "%s/%s.bsp", BaseUrl, map);
	DownloadMapUrl(map, fullUrl, targetPath);
}

public DownloadMapUrl(String:map[PLATFORM_MAX_PATH], String:fullUrl[512], String:targetPath[PLATFORM_MAX_PATH]) {
	decl String:tempPath[PLATFORM_MAX_PATH];
	Format(tempPath, sizeof(tempPath), "maps/%s_%d_%08x.bsp.part", TEMP_PREFIX, GetConVarInt(FindConVar("hostport")), GetURandomInt());

	new Handle:output_file = curl_OpenFile(tempPath, "wb");
	if (output_file == INVALID_HANDLE) {
		PrintToChatAll("Error downloading map %s: can't write to the maps directory", map);
		return;
	}

	new Handle:curl = curl_easy_init();
	CURL_DEFAULT_OPT(curl);

	PrintToChatAll("Trying to download %s from %s", map, fullUrl);

	new Handle:hDLPack = CreateDataPack();
	WritePackCell(hDLPack, _:output_file);
	WritePackString(hDLPack, map);
	WritePackString(hDLPack, targetPath);
	WritePackString(hDLPack, tempPath);

	curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, output_file);
	curl_easy_setopt_string(curl, CURLOPT_URL, fullUrl);
	curl_easy_setopt_int(curl, CURLOPT_FOLLOWLOCATION, 1);
	curl_easy_perform_thread(curl, onComplete, hDLPack);
}

public onComplete(Handle:hndl, CURLcode:code, any hDLPack) {
	decl String:map[PLATFORM_MAX_PATH];
	decl String:targetPath[PLATFORM_MAX_PATH];
	decl String:tempPath[PLATFORM_MAX_PATH];

	ResetPack(hDLPack);
	CloseHandle(Handle:ReadPackCell(hDLPack)); // output_file
	ReadPackString(hDLPack, map, sizeof(map));
	ReadPackString(hDLPack, targetPath, sizeof(targetPath));
	ReadPackString(hDLPack, tempPath, sizeof(tempPath));
	CloseHandle(hDLPack);

	if (code != CURLE_OK) {
		CloseHandle(hndl);
		PrintToChatAll("Error downloading map %s", map);
		decl String:sError[256];
		curl_easy_strerror(code, sError, sizeof(sError));
		PrintToChatAll("cURL error: %s", sError);
		PrintToChatAll("cURL error code: %d", code);
		DeleteFile(tempPath);
		return;
	}

	new status_code;
	curl_easy_getinfo_int(hndl, CURLINFO_RESPONSE_CODE, status_code);
	CloseHandle(hndl);

	if (status_code == 404) {
		PrintToChatAll("Map %s not found", map);
		DeleteFile(tempPath);
		return;
	}
	if (status_code != 200) {
		PrintToChatAll("Error downloading map %s", map);
		PrintToChatAll("HTTP error: %d", status_code);
		DeleteFile(tempPath);
		return;
	}

	if (FileSize(tempPath) < 1024) {
		PrintToChatAll("Map file too small, discarding");
		DeleteFile(tempPath);
		return;
	}

	if (!RenameFile(targetPath, tempPath)) {
		PrintToChatAll("Error downloading map %s: can't move it into the maps directory", map);
		DeleteFile(tempPath);
		return;
	}

	PrintToChatAll("Successfully downloaded map %s", map);
	ForceChangeLevel(map, "changelevel");
}

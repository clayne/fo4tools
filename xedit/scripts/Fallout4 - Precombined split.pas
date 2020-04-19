{
	1. Split precombines into separate plugins based on their master.
	2. Recombine precombine/previs of loaded plugins into a final plugin.

	Hotkey: Ctrl+Shift+P
}

unit FO4_Precombined_Split;
const
	Debug = true;
//	Debug = false;
	Profile = true;
	StopOnError = true;
	NegativeCaching = true;
	CacheRvisGridCells = true;
	CacheRvisCells = true;
	CacheCells = true;
	CellCopyOverwrite = true;
	MasterForceQueue = false;
	MasterForcePlugin = true;
	MasterUseAddMasters = true;
	MergeIntoOverride = true;
	PrevisFlagRemove = true;
	PrevisFlagForceRemove = true; // false;
	PerElementMasters = true;
	OptionPrefix = '--pcv';
	InitFileSuffix = 'pcv';
	PrecombineFileBase = 'precombine';
	PrevisFileBase = 'previs';
	FinalFileSuffix = 'pcv.final';
	PluginSuffix = 'esp';
	MaxFileAttempts = 20;
	DMarker_FID = $00000001;
	XMarker_FID = $0000003B;
	F_DELETED = $20;
	F_NOPREVIS = $80;
	F_PERSISTENT = $400;
	F_INIT_DISABLED = $800;
	F_IGNORED = $1000;
	F_VISIBLE_DISTANT = $8000;
	F_MARKER = $800000;
	VIS_OFFSET = 1;
	VIS_WIDTH = 3;

	P_AREA_ALL = 1;
	P_AREA_MAIN = 2;
	P_AREA_INTS = 3;
	P_AREA_EXTS = 4;
	P_AREA_OTHER = 5;

	P_MODE_INIT = 1;
	P_MODE_INIT_ALT = 2;
	P_MODE_STATS = 3;
	P_MODE_PRECOMBINE_MERGE = 4;
	P_MODE_PRECOMBINE_EXTRACT = 5;
	P_MODE_PREVIS_MERGE = 6;
	P_MODE_PREVIS_EXTRACT = 7;
	P_MODE_MASTER_CLEAN = 10;
	P_MODE_FORMID_DUMP = 20;
	P_MODE_FINAL = 30;

	O_TYPE_NONE = 0;
	O_TYPE_CELL = 1;
	O_TYPE_EACH = 2;
	O_TYPE_COMBINED = 3;
	O_TYPE_DIRECT = 4;
var
	process_area: integer;
	process_mode: integer;
	winning_only, non_winning_only, promote_winning_only: boolean;
	cell_check, stat_check, rvis_check, require_static: boolean;
	cell_clean, rfgp_clean, refr_clean: boolean;
	xcri_clean, xpri_clean, previs_flag_clear: boolean;
	xcri_clean_master, xpri_clean_master, previs_flag_clear_master: boolean;
	stat_promote, stat_promote_all, stat_promote_marker_prefer, stat_promote_marker_door: boolean;
	stat_master_add, rvis_master_add: boolean;
	cell_clean_cnt, refr_clean_cnt: integer;

	plugin_process_all: boolean;
	plugin_base_process, plugin_base_esm, plugin_base_master_force: boolean;

	plugin_output_base_cell_use, plugin_output_base_cell_esm: boolean;
	plugin_output_base_each_use, plugin_output_base_each_esm: boolean;
	plugin_output_base_combined_use, plugin_output_base_combined_esm: boolean;
	plugin_output_base_use, plugin_output_base_esm: boolean;
	plugin_output_base_cell_prefix: string;
	plugin_output_base_each_prefix: string;
	plugin_output_base_combined_prefix: string;
	plugin_output_base_prefix: string;

	plugin_output_cell_use, plugin_output_cell_esm: boolean;
	plugin_output_each_use, plugin_output_each_esm: boolean;
	plugin_output_combined_use, plugin_output_combined_esm: boolean;
	plugin_output_use, plugin_output_esm: boolean;
	plugin_output_cell_prefix: string;
	plugin_output_each_prefix: string;
	plugin_output_combined_prefix: string;
	plugin_output_prefix: string;

	plugin_output_cell_list: THashedStringList;
	plugin_output_each_list: THashedStringList;
	plugin_output_combined_list: THashedStringList;
	plugin_output_list: THashedStringList;

	plugin_output_log_list: THashedStringList;
	plugin_output_log, plugin_output_log_prefix: string;
	plugin_output_log_use: boolean;

	cell_keep_use: boolean;
	cell_keep_xy: array[0..1] of TwbGridCell;

	pc_sig_tab: array [0..1] of string;
	pv_sig_tab: array [0..2] of string;
	pc_keep_map: THashedStringList;
	pc_base_keep_map: THashedStringList;
	pv_keep_map: THashedStringList;
	pv_base_keep_map: THashedStringList;

	plugin_generated_list: THashedStringList;
	plugin_cell_master_exclude_list: THashedStringList;

	plugin_file_map: THashedStringList;
	plugin_exclude_list: THashedStringList;
	plugin_include_list: THashedStringList;
	plugin_use_list: THashedStringList;

	plugin_master_force_queue: THashedStringList;
	plugin_master_force_seen: THashedStringList;
	plugin_master_force_list: THashedStringList;
	plugin_master_base_list: THashedStringList;
	plugin_master_exclude_list: THashedStringList;

	cell_queue: TList;
	cell_queue_seen: THashedStringList;

	cell_rvis_grid_cache: THashedStringList;
	cell_rvis_cache: THashedStringList;
	cell_cache: THashedStringList;

	cell_rvis_grid_cache_hits: integer;
	cell_rvis_grid_cache_misses: integer;
	cell_rvis_cache_hits: integer;
	cell_rvis_cache_misses: integer;
	cell_cache_hits: integer;
	cell_cache_misses: integer;

function Initialize: integer;
var
	i: integer;
	tl: TList;
begin
	process_mode := P_MODE_MASTER_CLEAN;
	process_area := P_AREA_MAIN;

	cell_keep_use := false;
	cell_keep_xy[0].x := -96;
	cell_keep_xy[0].y := -96;
	cell_keep_xy[1].x := 96;
	cell_keep_xy[1].y := 96;

	stat_promote := true;
	stat_promote_all := true;
	stat_promote_marker_prefer := true;
	stat_promote_marker_door := false;
	stat_master_add := true;
	rvis_master_add := true;
	cell_clean := true;
	refr_clean := false;
	rfgp_clean := true;
	xcri_clean := true;
	xpri_clean := true;
	previs_flag_clear := true;
	xcri_clean_master := true;
	xpri_clean_master := true;
	previs_flag_clear_master := true;
	require_static := false;
	winning_only := false;
	non_winning_only := false;
	promote_winning_only := false;
	cell_check := true;
	stat_check := false;
	rvis_check := false;

	plugin_process_all := false;

	plugin_base_esm := false;
	plugin_base_process := false;
	plugin_base_master_force := false;

	plugin_output_base_cell_use := false;
	plugin_output_base_each_use := false;
	plugin_output_base_combined_use := false;
	plugin_output_base_use := false;
	plugin_output_base_cell_esm := false;
	plugin_output_base_each_esm := false;
	plugin_output_base_combined_esm := false;
	plugin_output_base_esm := false;
	plugin_output_base_cell_prefix := nil;
	plugin_output_base_each_prefix := nil;
	plugin_output_base_combined_prefix := nil;
	plugin_output_base_prefix := nil;

	plugin_output_cell_use := false;
	plugin_output_each_use := false;
	plugin_output_combined_use := false;
	plugin_output_use := true;
	plugin_output_cell_esm := false;
	plugin_output_each_esm := false;
	plugin_output_combined_esm := false;
	plugin_output_esm := false;
	plugin_output_cell_prefix := nil;
	plugin_output_each_prefix := nil;
	plugin_output_combined_prefix := nil;
	plugin_output_prefix := nil;

	plugin_output_log_use := false;
	plugin_output_log_prefix := nil;
	plugin_output_log := nil;

	// Precombine specific signatures
	pc_sig_tab[0] := 'XCRI';
	pc_sig_tab[1] := 'PCMB';

	// Previs specific signatures
	pv_sig_tab[0] := 'XPRI';
	pv_sig_tab[1] := 'VISI';
	pv_sig_tab[2] := 'RVIS';

	pc_keep_map := THashedStringList.create;
	pc_keep_map.Sorted := true;
	pc_keep_map.add('REFR');

	pc_base_keep_map := THashedStringList.create;
	pc_base_keep_map.Sorted := true;
	pc_base_keep_map.add('SCOL');
	pc_base_keep_map.add('STAT');

	pv_keep_map := THashedStringList.create;
	pv_keep_map.Sorted := true;
	pv_keep_map.add('PHZD');
	pv_keep_map.add('PMIS');
	pv_keep_map.add('REFR');

	pv_base_keep_map := THashedStringList.create;
	pv_base_keep_map.Sorted := true;
	pv_base_keep_map.add('ACTI');
	pv_base_keep_map.add('CONT');
	pv_base_keep_map.add('FLOR');
	pv_base_keep_map.add('FURN');
	pv_base_keep_map.add('HAZD');
	pv_base_keep_map.add('MSTT');
	pv_base_keep_map.add('PROJ');
	pv_base_keep_map.add('SCOL');
	pv_base_keep_map.add('STAT');
	pv_base_keep_map.add('TACT');
	pv_base_keep_map.add('TERM');

	plugin_master_base_list := THashedStringList.create;
	plugin_master_base_list.sorted := false;
	plugin_master_base_list.duplicates := dupIgnore;
	plugin_master_base_list.add('Fallout4.esm');
	plugin_master_base_list.add('DLCRobot.esm');
	plugin_master_base_list.add('DLCworkshop01.esm');
	plugin_master_base_list.add('DLCCoast.esm');
	plugin_master_base_list.add('DLCworkshop02.esm');
	plugin_master_base_list.add('DLCworkshop03.esm');
	plugin_master_base_list.add('DLCNukaWorld.esm');
	plugin_master_base_list.add('DLCUltraHighResolution.esm');

	plugin_master_force_list := THashedStringList.create;
	plugin_master_force_list.sorted := false;
	plugin_master_force_list.duplicates := dupIgnore;
{
	plugin_master_force_list.add('Fallout4.esm');
	plugin_master_force_list.add('DLCRobot.esm');
	plugin_master_force_list.add('DLCworkshop01.esm');
	plugin_master_force_list.add('DLCCoast.esm');
	plugin_master_force_list.add('DLCworkshop02.esm');
	plugin_master_force_list.add('DLCworkshop03.esm');
	plugin_master_force_list.add('DLCNukaWorld.esm');
//	plugin_master_force_list.add('DLCUltraHighResolution.esm');
}

	plugin_master_exclude_list := THashedStringList.create;
	plugin_master_exclude_list.sorted := true;
	plugin_master_exclude_list.duplicates := dupIgnore;
	plugin_master_exclude_list.add('DLCUltraHighResolution.esm');

	plugin_generated_list := THashedStringList.create;
	plugin_generated_list.sorted := true;
	plugin_generated_list.duplicates := dupIgnore;
	plugin_generated_list.add('.' + InitFileSuffix);
	plugin_generated_list.add(PrecombineFileBase + '.');
	plugin_generated_list.add(PrevisFileBase + '.');
	plugin_generated_list.add('.' + FinalFileSuffix);

	plugin_file_map := THashedStringList.create;
	plugin_file_map.sorted := true;
	plugin_file_map.duplicates := dupIgnore;

	plugin_master_force_seen := THashedStringList.create;
	plugin_master_force_seen.sorted := true;
	plugin_master_force_seen.duplicates := dupIgnore;

	plugin_master_force_queue := THashedStringList.create;
	plugin_master_force_queue.sorted := false;
	plugin_master_force_queue.duplicates := dupIgnore;

	plugin_output_list := THashedStringList.create;
	plugin_output_cell_list := THashedStringList.create;
	plugin_output_each_list := THashedStringList.create;
	plugin_output_combined_list := THashedStringList.create;

	plugin_output_log_list := THashedStringList.create;

	plugin_use_list := nil;
	plugin_exclude_list := nil;
	plugin_include_list := nil;
	plugin_cell_master_exclude_list := nil;

	cell_rvis_grid_cache := THashedStringList.create;
	cell_rvis_grid_cache.Sorted := true;
	cell_rvis_grid_cache.Duplicates := dupIgnore;

	cell_rvis_cache := THashedStringList.create;
	cell_rvis_cache.Sorted := true;
	cell_rvis_cache.Duplicates := dupIgnore;

	cell_cache := THashedStringList.create;
	cell_cache.Sorted := true;
	cell_cache.Duplicates := dupIgnore;

	cell_queue_seen := THashedStringList.create;
	cell_queue_seen.sorted := true;
	cell_queue_seen.duplicates := dupIgnore;

	cell_queue := TList.create;
	cell_queue.count := FileCount;

	cell_rvis_grid_cache_hits := 0;
	cell_rvis_grid_cache_misses := 0;
	cell_rvis_cache_hits := 0;
	cell_rvis_cache_misses := 0;
	cell_cache_hits := 0;
	cell_cache_misses := 0;

	cell_clean_cnt := 0;
	refr_clean_cnt := 0;

	// Parse all command line options, optionally overriding various
	// defaults and lists.
	if not opts_parse then begin
		AddMessage('Error processing command line options');
		Result := true;
		Exit;
	end;

	if process_mode = P_MODE_FINAL then begin
		plugin_output_cell_use := false;
		plugin_output_each_use := false;
		plugin_output_combined_use := true;
		plugin_output_base_combined_use := false;

{
		// XXX: remove
		plugin_master_exclude_list.add('main.pcv.esp');
		plugin_master_exclude_list.add('ints.pcv.esp');
		plugin_master_exclude_list.add('other.pcv.esp');
}
	end;
end;

function bool_to_str(b: boolean): string;
begin
	if not b then begin
		Result := 'false';
	end else begin
		Result := 'true';
	end;
end;

function str_to_bool(s: string): boolean;
begin
	if (s = '0') or (s = 'false') then begin
		Result := false;
	end else begin
		Result := true;
	end;
end;

function p_area_to_str(i: integer): string;
begin
	case i of
	P_AREA_ALL:	Result := 'all';
	P_AREA_MAIN:	Result := 'main';
	P_AREA_INTS:	Result := 'ints';
	P_AREA_EXTS:	Result := 'exts';
	P_AREA_OTHER:	Result := 'other';
	end;
end;

function str_to_p_area(s: string): integer;
begin
	if s = 'all' then begin			Result := P_AREA_ALL;
	end else if s = 'main' then begin	Result := P_AREA_MAIN;
	end else if s = 'ints' then begin	Result := P_AREA_INTS;
	end else if s = 'exts' then begin	Result := P_AREA_EXTS;
	end else if s = 'other' then begin	Result := P_AREA_OTHER;
	end else begin
		Raise Exception.Create('str_to_p_area: no match');
	end;
end;

function p_mode_to_str(i: integer): string;
begin
	case i of
	P_MODE_INIT:				Result := 'init';
	P_MODE_INIT_ALT:			Result := 'init_alt';
	P_MODE_STATS:				Result := 'stats';
	P_MODE_PRECOMBINE_MERGE:		Result := 'precombine_merge';
	P_MODE_PRECOMBINE_EXTRACT:		Result := 'precombine_extract';
	P_MODE_PREVIS_MERGE:			Result := 'previs_merge';
	P_MODE_PREVIS_EXTRACT:			Result := 'previs_extract';
	P_MODE_MASTER_CLEAN:			Result := 'master_clean';
	P_MODE_FORMID_DUMP:			Result := 'formid_dump';
	P_MODE_FINAL:				Result := 'final';
	end;
end;

function str_to_p_mode(s: string): integer;
begin
	if s = 'init' then begin					Result := P_MODE_INIT;
	end else if s = 'init_alt' then begin				Result := P_MODE_INIT_ALT;
	end else if s = 'stats' then begin				Result := P_MODE_STATS;
	end else if s = 'precombine_merge' then begin			Result := P_MODE_PRECOMBINE_MERGE;
	end else if s = 'precombine_extract' then begin			Result := P_MODE_PRECOMBINE_EXTRACT;
	end else if s = 'previs_merge' then begin			Result := P_MODE_PREVIS_MERGE;
	end else if s = 'previs_extract' then begin			Result := P_MODE_PREVIS_EXTRACT;
	end else if s = 'master_clean' then begin			Result := P_MODE_MASTER_CLEAN;
	end else if s = 'formid_dump' then begin			Result := P_MODE_FORMID_DUMP;
	end else if s = 'final' then begin				Result := P_MODE_FINAL;
	end else begin
		Raise Exception.Create('str_to_p_mode: no match');
	end;
end;

function comma_split(v: string; sl: THashedStringList; sort, add: boolean): TStringList;
var
	tl: THashedStringList;
	i: integer;
begin
	tl := THashedStringList.create;
	tl.sorted := sort;
	tl.duplicates := dupIgnore;
	tl.strictdelimiter := true;
	tl.delimiter := ',';
	tl.delimitedtext := v;

	if sl = nil then begin
		Result := tl;
		Exit;
	end;

	if not add then
		sl.clear;

	for i := 0 to Pred(tl.count) do begin
		sl.add(tl[i]);
	end;

	tl.free;

	Result := sl;
end;

function opts_parse: boolean;
var
	i, j, k, opl, idx: integer;
	s, p, v: string;
	sl, sl2: THashedStringList;
begin
	opl := length(OptionPrefix);

	for i := 0 to ParamCount do begin
		s := ParamStr(i);
		AddMessage(Format('param[%d] == %s', [ i, s ]));

		if pos(OptionPrefix, s) = 0 then
			continue;

		idx := pos('=', s) or pos(':', s);
		if idx <> 0 then begin
			// --<OptionPrefix>-<opt>=value
			p := copy(s, (opl + 2), idx - (opl + 2));
			v := copy(s, idx + 1, length(s) - idx);
		end else begin
			// --<OptionPrefix>-<opt>
			p := copy(s, (opl + 2), length(s) - (opl + 2) + 1);
			v := '1';
		end;

//		AddMessage('p == ' + p);
//		AddMessage('v == ' + v);

		// the type of processing to apply to all plugins
		if p = 'mode' then begin
			process_mode := str_to_p_mode(v);

		// main, ints, other (which "area" to restrict processing to)
		end else if p = 'area' then begin
			process_area := str_to_p_area(v);

		// should non-matching cells be removed in general?
		end else if p = 'cell-clean' then begin
			cell_clean := str_to_bool(v);

		// should non stat refrs be removed?
		end else if p = 'refr-clean' then begin
			refr_clean := str_to_bool(v);

		// should reference groups be removed?
		end else if p = 'rfgp-clean' then begin
			rfgp_clean := str_to_bool(v);

		// should existing xcri/pcmb data be removed?
		end else if p = 'xcri-clean' then begin
			xcri_clean := str_to_bool(v);

		// should existing xpri/visi data be removed?
		end else if p = 'xpri-clean' then begin
			xpri_clean := str_to_bool(v);

		// should 'no previs' flags be removed?
		end else if p = 'previs-flag-clear' then begin
			previs_flag_clear  := str_to_bool(v);

		// should existing xcri/pcmb data be removed from masters?
		end else if p = 'xcri-clean-master' then begin
			xcri_clean_master := str_to_bool(v);

		// should existing xpri/visi data be removed from masters?
		end else if p = 'xpri-clean-master' then begin
			xpri_clean_master := str_to_bool(v);

		// should 'no previs' flags be removed from masters?
		end else if p = 'previs-flag-clear-master' then begin
			previs_flag_clear_master  := str_to_bool(v);

		// should cells not matching filter be removed?
		end else if p = 'cell-check' then begin
			cell_check := str_to_bool(v);

		// should cells without stat refrs be removed?
		end else if p = 'stat-check' then begin
			stat_check := str_to_bool(v);

		// should cells that do not overlap 3x3 rvis grids be removed?
		end else if p = 'rvis-check' then begin
			rvis_check := str_to_bool(v);

		// should only the last or "winning" cell be considered the candidate?
		end else if p = 'winning-only' then begin
			winning_only := str_to_bool(v);

		// should only intermediate or non-winning cells be considered candidates?
		end else if p = 'non-winning-only' then begin
			non_winning_only := str_to_bool(v);

		// should only the last or "winning" cell be used as a target of generation?
		end else if p = 'promote-winning-only' then begin
			promote_winning_only := str_to_bool(v);

		// should STAT refrs from plugins be cloned as overrides into output plugin?
		end else if p = 'stat-promote' then begin
			stat_promote := str_to_bool(v);

		// should STAT refrs from plugins be cloned as overrides even if the CELL has no statics?
		end else if p = 'stat-promote-all' then begin
			stat_promote_all := str_to_bool(v);

		// when promoting STATs, should a fake XMarker reference be used instead?
		end else if p = 'stat-promote-marker-prefer' then begin
			stat_promote_marker_prefer := str_to_bool(v);

		// when promoting STATs, should a fake door reference be used instead?
		end else if p = 'stat-promote-marker-door' then begin
			stat_promote_marker_door := str_to_bool(v);

		// should earlier plugins with stat refrs in the same cell be added as a master to a plugin?
		end else if p = 'stat-master-add' then begin
			stat_master_add := str_to_bool(v);

		// should earlier plugins with rvis overlapping cells be added as a master to a plugin?
		end else if p = 'rvis-master-add' then begin
			rvis_master_add := str_to_bool(v);

		// should all plugins be processed regardless of whether having CELL/STAT/SCOLs? (not used yet)
		end else if p = 'plugin-process-all' then begin
			plugin_process_all := str_to_bool(v);

		// should "base" plugins be esm flagged?
		end else if p = 'plugin-base-esm' then begin
			plugin_base_esm := str_to_bool(v);

		// should "base" plugins be considered candidates for processing?
		end else if p = 'plugin-base-process' then begin
			plugin_base_process := str_to_bool(v);

		// should a per-plugin-per-cell output plugin be generated for base plugins?
		end else if p = 'plugin-output-base-cell-use' then begin
			plugin_output_base_cell_use := str_to_bool(v);

		// should per-plugin-per-cell output plugins for base plugins be esm flagged?
		end else if p = 'plugin-output-base-cell-esm' then begin
			plugin_output_base_cell_esm := str_to_bool(v);

		// should a per-plugin output plugin be generated for base plugins?
		end else if p = 'plugin-output-base-each-use' then begin
			plugin_output_base_each_use := str_to_bool(v);

		// should a per-plugin output plugins for base plugins be esm flaggd?
		end else if p = 'plugin-output-base-each-esm' then begin
			plugin_output_base_each_esm := str_to_bool(v);

		// should a single output plugin oriented around area (e.g. main, ints, others) be used for base plugins?
		end else if p = 'plugin-output-base-combined-use' then begin
			plugin_output_base_combined_use := str_to_bool(v);

		// should a single output plugin oriented around area (e.g. main, ints, others) be esm flagged?
		end else if p = 'plugin-output-base-combined-esm' then begin
			plugin_output_base_combined_esm := str_to_bool(v);

		// should plugin output files for base plugins be generated at all?
		end else if p = 'plugin-output-base-use' then begin
			plugin_output_base_use := str_to_bool(v);

		// should plugin output files for base plugins be esm flagged?
		end else if p = 'plugin-output-base-esm' then begin
			plugin_output_base_esm := str_to_bool(v);

		// force a prefix to be added to generated output plugin names?
		end else if p = 'plugin-output-base-cell-prefix' then begin
			plugin_output_base_cell_prefix := v;

		// force a prefix to be added to generated output plugin names?
		end else if p = 'plugin-output-base-each-prefix' then begin
			plugin_output_base_each_prefix := v;

		// force a prefix to be added to generated output plugin names?
		end else if p = 'plugin-output-base-combined-prefix' then begin
			plugin_output_base_combined_prefix := v;

		// force a prefix to be added to generated output plugin names?
		end else if p = 'plugin-output-base-prefix' then begin
			plugin_output_base_prefix := v;

		// should a per-plugin-per-cell output plugin be generated?
		end else if p = 'plugin-output-cell-use' then begin
			plugin_output_cell_use := str_to_bool(v);

		// should a per-plugin-per-cell output plugins be esm flagged?
		end else if p = 'plugin-output-cell-esm' then begin
			plugin_output_cell_esm := str_to_bool(v);

		// should a per-plugin output plugin be generated?
		end else if p = 'plugin-output-each-use' then begin
			plugin_output_each_use := str_to_bool(v);

		// should a per-plugin output plugins be esm flagged?
		end else if p = 'plugin-output-each-esm' then begin
			plugin_output_each_esm := str_to_bool(v);

		// should a single output plugin oriented around area (e.g. main, ints, others) be used?
		end else if p = 'plugin-output-combined-use' then begin
			plugin_output_combined_use := str_to_bool(v);

		// should a single output plugin oriented around area (e.g. main, ints, others) be esm flagged?
		end else if p = 'plugin-output-combined-esm' then begin
			plugin_output_combined_esm := str_to_bool(v);

		// should plugin output files be generated at all?
		end else if p = 'plugin-output-use' then begin
			plugin_output_use := str_to_bool(v);

		// should plugin output files be esm flagged?
		end else if p = 'plugin-output-esm' then begin
			plugin_output_esm := str_to_bool(v);

		// force a prefix to be added to generated output plugin names?
		end else if p = 'plugin-output-cell-prefix' then begin
			plugin_output_cell_prefix := v;

		// force a prefix to be added to generated output plugin names?
		end else if p = 'plugin-output-each-prefix' then begin
			plugin_output_each_prefix := v;

		// force a prefix to be added to generated output plugin names?
		end else if p = 'plugin-output-combined-prefix' then begin
			plugin_output_combined_prefix := v;

		// force a prefix to be added to generated output plugin names?
		end else if p = 'plugin-output-prefix' then begin
			plugin_output_prefix := v;

		// list of plugins that should be used in 'cell' output mode
		end else if p = 'plugin-output-cell-list' then begin
			comma_split(v, plugin_output_cell_list, true, false);

		// list of plugins that should be used in 'each' output mode
		end else if p = 'plugin-output-each-list' then begin
			comma_split(v, plugin_output_each_list, true, false);

		// list of plugins that should be used in 'combined' output mode
		end else if p = 'plugin-output-combined-list' then begin
			comma_split(v, plugin_output_combined_list, true, false);

		// list of plugins that should be used in any mode
		end else if p = 'plugin-output-list' then begin
			comma_split(v, plugin_output_list, true, false);

		// emit output plugin names to this log file?
		end else if p = 'plugin-output-log' then begin
			plugin_output_log := v;

		// emit output plugin names to this log file?
		end else if p = 'plugin-output-log-prefix' then begin
			plugin_output_log_prefix := v;

		// emit output plugin names to this log file?
		end else if p = 'plugin-output-log-use' then begin
			plugin_output_log_use := str_to_bool(v);

		// should "base" plugins be forced as masters?
		end else if p = 'plugin-base-master-force' then begin
			plugin_base_master_force := str_to_bool(v);

		// should cells only be kept if they fall within x0y0 - x1y1?
		end else if p = 'cell-keep-xy' then begin
			sl := TStringList.create;
			sl.strictdelimiter := true;
			sl.delimiter := ' ';
			sl.delimitedtext := v;

			for j := 0 to Pred(sl.count) do begin
				sl2 := comma_split(sl[j], nil, false, false);

				if sl2.count >= 1 then
					cell_keep_xy[j].x := StrToInt(sl2[0]);
				if sl2.count >= 2 then
					cell_keep_xy[j].y := StrToInt(sl2[1]);

				sl2.free;
			end;

			sl.free;
			cell_keep_use := true;

		// list of "base" masters
		end else if p = 'plugin-master-base-list' then begin
			comma_split(v, plugin_master_base_list, false, false);

		end else if p = 'plugin-master-base-list-add' then begin
			comma_split(v, plugin_master_base_list, false, true);

		// list of masters to force on every output plugin
		end else if p = 'plugin-master-force-list' then begin
			comma_split(v, plugin_master_force_list, false, false);

		end else if p = 'plugin-master-force-list-add' then begin
			comma_split(v, plugin_master_force_list, false, true);

		// list of masters to skip for cell processing; XXX: might be named wrong
		end else if p = 'plugin-master-exclude-list' then begin
			comma_split(v, plugin_master_exclude_list, false, false);

		end else if p = 'plugin-master-exclude-list-add' then begin
			comma_split(v, plugin_master_exclude_list, false, true);

		// list of plugins to exclude from processing
		end else if p = 'plugin-exclude-list' then begin
			plugin_exclude_list := comma_split(v, nil, true, false);

		// list of plugins to only consider for processing
		end else if p = 'plugin-include-list' then begin
			plugin_include_list := comma_split(v, nil, true, false);

		// XXX: fill in
		end else if p = 'plugin-use-list' then begin
			plugin_use_list := comma_split(v, nil, true, false);

		// XXX: fill in
		end else if p = 'plugin-cell-master-exclude-list' then begin
			plugin_cell_master_exclude_list := comma_split(v, nil, true, false);

		end;
	end;

	if Assigned(plugin_output_log_prefix) and not Assigned(plugin_output_log) then begin
		plugin_output_log := Format('%s.%s.%s', [ plugin_output_log_prefix, p_area_to_str(process_area), 'out' ]);
	end;

	AddMessage(Format('%s == %s', [ 'process_mode', p_mode_to_str(process_mode) ]));
	AddMessage(Format('%s == %s', [ 'process_area', p_area_to_str(process_area) ]));
	AddMessage(Format('%s == %s', [ 'cell_clean', bool_to_str(cell_clean) ]));
	AddMessage(Format('%s == %s', [ 'refr_clean', bool_to_str(refr_clean) ]));
	AddMessage(Format('%s == %s', [ 'rfgp_clean', bool_to_str(rfgp_clean) ]));
	AddMessage(Format('%s == %s', [ 'xcri_clean', bool_to_str(xcri_clean) ]));
	AddMessage(Format('%s == %s', [ 'xpri_clean', bool_to_str(xpri_clean) ]));
	AddMessage(Format('%s == %s', [ 'previs_flag_clear', bool_to_str(previs_flag_clear) ]));
	AddMessage(Format('%s == %s', [ 'xcri_clean_master', bool_to_str(xcri_clean_master) ]));
	AddMessage(Format('%s == %s', [ 'xpri_clean_master', bool_to_str(xpri_clean_master) ]));
	AddMessage(Format('%s == %s', [ 'previs_flag_clear_master', bool_to_str(previs_flag_clear_master) ]));
	AddMessage(Format('%s == %s', [ 'cell_check', bool_to_str(cell_check) ]));
	AddMessage(Format('%s == %s', [ 'stat_check', bool_to_str(stat_check) ]));
	AddMessage(Format('%s == %s', [ 'rvis_check', bool_to_str(rvis_check) ]));
	AddMessage(Format('%s == %s', [ 'winning_only', bool_to_str(winning_only) ]));
	AddMessage(Format('%s == %s', [ 'non_winning_only', bool_to_str(non_winning_only) ]));
	AddMessage(Format('%s == %s', [ 'promote_winning_only', bool_to_str(promote_winning_only) ]));
	AddMessage(Format('%s == %s', [ 'stat_promote', bool_to_str(stat_promote) ]));
	AddMessage(Format('%s == %s', [ 'stat_promote_all', bool_to_str(stat_promote_all) ]));
	AddMessage(Format('%s == %s', [ 'stat_promote_marker_prefer', bool_to_str(stat_promote_marker_prefer) ]));
	AddMessage(Format('%s == %s', [ 'stat_promote_marker_door', bool_to_str(stat_promote_marker_door) ]));
	AddMessage(Format('%s == %s', [ 'stat_master_add', bool_to_str(stat_master_add) ]));
	AddMessage(Format('%s == %s', [ 'rvis_master_add', bool_to_str(rvis_master_add) ]));

	AddMessage(Format('%s == %s', [ 'plugin_process_all', bool_to_str(plugin_process_all) ]));
	AddMessage(Format('%s == %s', [ 'plugin_base_esm', bool_to_str(plugin_base_esm) ]));
	AddMessage(Format('%s == %s', [ 'plugin_base_process', bool_to_str(plugin_base_process) ]));
	AddMessage(Format('%s == %s', [ 'plugin_base_master_force', bool_to_str(plugin_base_master_force) ]));

	AddMessage(Format('%s == %s', [ 'plugin_output_base_cell_use', bool_to_str(plugin_output_base_cell_use) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_base_cell_esm', bool_to_str(plugin_output_base_cell_esm) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_base_each_use', bool_to_str(plugin_output_base_each_use) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_base_each_esm', bool_to_str(plugin_output_base_each_esm) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_base_combined_use', bool_to_str(plugin_output_base_combined_use) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_base_combined_esm', bool_to_str(plugin_output_base_combined_esm) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_base_use', bool_to_str(plugin_output_base_use) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_base_esm', bool_to_str(plugin_output_base_esm) ]));

	if Assigned(plugin_output_base_cell_prefix) then begin
		AddMessage(Format('%s == %s', [ 'plugin_output_base_cell_prefix', plugin_output_base_cell_prefix ]));
	end;

	if Assigned(plugin_output_base_each_prefix) then begin
		AddMessage(Format('%s == %s', [ 'plugin_output_base_each_prefix', plugin_output_base_each_prefix ]));
	end;

	if Assigned(plugin_output_base_combined_prefix) then begin
		AddMessage(Format('%s == %s', [ 'plugin_output_base_combined_prefix', plugin_output_base_combined_prefix ]));
	end;

	if Assigned(plugin_output_base_prefix) then begin
		AddMessage(Format('%s == %s', [ 'plugin_output_base_prefix', plugin_output_base_prefix ]));
	end;

	AddMessage(Format('%s == %s', [ 'plugin_output_cell_use', bool_to_str(plugin_output_cell_use) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_cell_esm', bool_to_str(plugin_output_cell_esm) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_each_use', bool_to_str(plugin_output_each_use) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_each_esm', bool_to_str(plugin_output_each_esm) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_combined_use', bool_to_str(plugin_output_combined_use) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_combined_esm', bool_to_str(plugin_output_combined_esm) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_use', bool_to_str(plugin_output_use) ]));
	AddMessage(Format('%s == %s', [ 'plugin_output_esm', bool_to_str(plugin_output_esm) ]));

	if Assigned(plugin_output_cell_prefix) then begin
		AddMessage(Format('%s == %s', [ 'plugin_output_cell_prefix', plugin_output_cell_prefix ]));
	end;

	if Assigned(plugin_output_each_prefix) then begin
		AddMessage(Format('%s == %s', [ 'plugin_output_each_prefix', plugin_output_each_prefix ]));
	end;

	if Assigned(plugin_output_combined_prefix) then begin
		AddMessage(Format('%s == %s', [ 'plugin_output_combined_prefix', plugin_output_combined_prefix ]));
	end;

	if Assigned(plugin_output_prefix) then begin
		AddMessage(Format('%s == %s', [ 'plugin_output_prefix', plugin_output_prefix ]));
	end;

	if Assigned(plugin_output_cell_list) then begin
		for i := 0 to Pred(plugin_output_cell_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_output_cell_list', i, plugin_output_cell_list[i] ]));
		end;
	end;

	if Assigned(plugin_output_each_list) then begin
		for i := 0 to Pred(plugin_output_each_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_output_each_list', i, plugin_output_each_list[i] ]));
		end;
	end;

	if Assigned(plugin_output_combined_list) then begin
		for i := 0 to Pred(plugin_output_combined_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_output_combined_list', i, plugin_output_combined_list[i] ]));
		end;
	end;

	if Assigned(plugin_output_list) then begin
		for i := 0 to Pred(plugin_output_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_output_list', i, plugin_output_list[i] ]));
		end;
	end;

	AddMessage(Format('%s == %s', [ 'plugin_output_log_use', bool_to_str(plugin_output_log_use) ]));

	if Assigned(plugin_output_log_prefix) then begin
		AddMessage(Format('%s == %s', [ 'plugin_output_log_prefix', plugin_output_log_prefix ]));
	end;
	if Assigned(plugin_output_log) then begin
		AddMessage(Format('%s == %s', [ 'plugin_output_log', plugin_output_log ]));
	end;

	if Assigned(plugin_master_base_list) then begin
		for i := 0 to Pred(plugin_master_base_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_master_base_list', i, plugin_master_base_list[i] ]));
		end;
	end;

	if Assigned(plugin_master_force_list) then begin
		for i := 0 to Pred(plugin_master_force_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_master_force_list', i, plugin_master_force_list[i] ]));
		end;
	end;

	if Assigned(plugin_master_exclude_list) then begin
		for i := 0 to Pred(plugin_master_exclude_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_master_exclude_list', i, plugin_master_exclude_list[i] ]));
		end;
	end;

	if Assigned(plugin_exclude_list) then begin
		for i := 0 to Pred(plugin_exclude_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_exclude_list', i, plugin_exclude_list[i] ]));
		end;
	end;

	if Assigned(plugin_include_list) then begin
		for i := 0 to Pred(plugin_include_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_include_list', i, plugin_include_list[i] ]));
		end;
	end;

	if Assigned(plugin_use_list) then begin
		for i := 0 to Pred(plugin_use_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_use_list', i, plugin_use_list[i] ]));
		end;
	end;

	if Assigned(plugin_generated_list) then begin
		for i := 0 to Pred(plugin_generated_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_generated_list', i, plugin_generated_list[i] ]));
		end;
	end;

	if Assigned(plugin_cell_master_exclude_list) then begin
		for i := 0 to Pred(plugin_cell_master_exclude_list.count) do begin
			AddMessage(Format('%s[%d] == %s', [ 'plugin_cell_master_exclude_list', i, plugin_cell_master_exclude_list[i] ]));
		end;
	end;

	if cell_keep_use then begin
		AddMessage(Format('%s == %d,%d', [ 'cell_keep_xy[0]', cell_keep_xy[0].x, cell_keep_xy[0].y ]));
		AddMessage(Format('%s == %d,%d', [ 'cell_keep_xy[1]', cell_keep_xy[1].x, cell_keep_xy[1].y ]));
	end;

	Result := true;
end;

function __is_in_list(sl: THashedStringList; key: string): boolean;
begin
	Result := false;

	if not Assigned(sl) then begin
		Exit;
	end else if sl.indexOf(key) >= 0 then begin
		Result := true;
	end;
end;

function is_root_plugin(plugin: IwbFile): boolean;
var
	idx: integer;
begin
	idx := GetLoadOrder(GetFile(plugin));
	Result := (idx = 0);
end;

function is_plugin_base(plugin: IwbFile): boolean;
begin
	Result := __is_in_list(plugin_master_base_list, GetFileName(plugin));
end;

function is_plugin_excluded(plugin: IwbFile): boolean;
begin
	Result := __is_in_list(plugin_exclude_list, GetFileName(plugin));
end;

function is_plugin_included(plugin: IwbFile): boolean;
begin
	Result := true;

	if not Assigned(plugin_include_list) then begin
		Exit;
	end else if not plugin_include_list.indexOf(GetFileName(plugin)) >= 0 then begin
		Result := false;
	end;
end;

function is_plugin_generated(plugin: IwbFile): boolean;
var
	fstr: string;
	i: integer;
begin
	Result := false;

	if not Assigned(plugin_generated_list) then
		Exit;

	fstr := GetFileName(plugin);
	for i := 0 to Pred(plugin_generated_list.count) do begin
		if Pos(plugin_generated_list[i], fstr) <> 0 then begin
			Result := true;
			Exit;
		end;
	end;
end;

function is_plugin_output_cell(plugin: IwbFile): boolean;
begin
	Result := __is_in_list(plugin_output_cell_list, GetFileName(plugin));
end;

function is_plugin_output_each(plugin: IwbFile): boolean;
begin
	Result := __is_in_list(plugin_output_each_list, GetFileName(plugin));
end;

function is_plugin_output_combined(plugin: IwbFile): boolean;
begin
	Result := __is_in_list(plugin_output_combined_list, GetFileName(plugin));
end;

function is_plugin_output(plugin: IwbFile): boolean;
begin
	Result := __is_in_list(plugin_output_list, GetFileName(plugin));
end;

function override_or_master(m: IInterface; idx: integer): IInterface;
begin
	if idx < 0 then begin
		Result := m;
	end else begin
		Result := OverrideByIndex(m, idx);
	end;
end;

function winning_override(e: IInterface; ignore_generated: boolean): IInterface;
var
	t, m: IInterface;
	i, oc: integer;
begin
	if not ignore_generated then begin
		Result := WinningOverride(e);
		Exit;
	end;

	m := MasterOrSelf(e);
	oc := OverrideCount(m);
	for i := Pred(oc) downto -1 do begin
		t := override_or_master(m, i);

		if not is_plugin_generated(t) then begin
			Result := t;
			Exit;
		end;
	end;

	Result := nil;
end;

function is_winning_override(e: IInterface; ignore_generated: boolean): boolean;
begin
	Result := Equals(e, winning_override(e, ignore_generated));
end;

procedure plugin_master_add(plugin: IwbFile; e: IInterface; parents, sort, ordered: boolean);
var
	mfile, f: IwbFile;
	mfstr, pfstr: string;
	i, m_idx, p_idx: integer;
	mq, sl: THashedStringList;
	tl: TList;
begin
	p_idx := GetLoadOrder(plugin);
	pfstr := GetFileName(plugin);

	mq := TStringList.create;
	mq.sorted := false;
	mq.duplicates := dupIgnore;

	sl := THashedStringList.create;
	sl.sorted := true;
	sl.duplicates := dupIgnore;

	tl := TList.create;
	tl.add(GetFile(e));
	while tl.count <> 0 do begin
		mfile := ObjectToElement(tl[0]);
		tl.delete(0);

		mfstr := GetFileName(mfile);
		m_idx := GetLoadOrder(mfile);

		if sl.indexOf(mfstr) >= 0 then
			continue;
		sl.add(mfstr);

		// dont allow adding self
		if pfstr = mfstr then
			continue;

		// dont add masters to a plugin that is before the master
		if p_idx <= m_idx and ordered then
			continue;

		if parents then begin
			// Add masters of the master being added otherwise
			// CK will emit these after all plugins have been
			// loaded and totally screw up the formid indexes.
			for i := 0 to Pred(MasterCount(mfile)) do begin
				f := MasterByIndex(mfile, i);
				tl.add(f);
			end;
		end;

		// skip if the master has already been added
		if HasMaster(plugin, mfstr) then
			continue;

		// skip any excluded masters
		if plugin_master_exclude_list.indexOf(mfstr) >= 0 then
			continue;

		if Debug then AddMessage(Format('%s: Adding master: %s: %s', [GetFileName(plugin), mfstr, Name(e)]));
		mq.add(mfstr);
	end;

	if MasterUseAddMasters then begin
		if (mq.count <> 0) then
			AddMasters(plugin, mq);
	end else begin
		for i := 0 to Pred(mq.count) do begin
//			AddMasterIfMissing(plugin, mq[i], sort);
			AddMasterIfMissing(plugin, mq[i], false);
		end;
	end;

	if sort then
		SortMasters(plugin);

	tl.free;
	sl.free;
	mq.free;
end;

procedure plugin_master_force(plugin: IwbFile);
begin
	if MasterForceQueue then begin
		__plugin_master_force_queue(plugin);
		Exit;
	end;

	__plugin_master_force(plugin);
end;

procedure __plugin_master_force(plugin: IwbFile);
var
	m: IInterface;
	i: integer;
	pfstr: string;
begin
	pfstr := GetFileName(plugin);

	// Already forced?
	if plugin_master_force_seen.indexOf(pfstr) >= 0 then
		Exit;
	plugin_master_force_seen.add(pfstr);

	if plugin_master_base_list.indexOf(pfstr) >= 0 then
		Exit;
//	if plugin_master_force_list.indexOf(pfstr) >= 0 then
//		Exit;
	if plugin_master_exclude_list.indexOf(pfstr) >= 0 then
		Exit;

	if plugin_base_master_force then begin
		for i := 0 to Pred(plugin_master_base_list.count) do begin
			m := plugin_file_resolve_existing(plugin_master_base_list[i]);
			if Assigned(m) then
				plugin_master_add(plugin, m, true, false, false);
		end;
	end;

	for i := 0 to Pred(plugin_master_force_list.count) do begin
		m := plugin_file_resolve_existing(plugin_master_force_list[i]);
		if Assigned(m) then
			plugin_master_add(plugin, m, true, false, false);
	end;

	SortMasters(plugin);
end;

procedure __plugin_master_force_queue(plugin: IwbFile);
var
	fname: string;
begin
	fname := GetFileName(plugin);

	// Already queued?
	if plugin_master_force_queue.indexOf(fname) >= 0 then
		Exit;

	plugin_master_force_queue.addObject(fname, plugin);
end;

procedure plugin_master_force_queue_proc;
var
	plugin: IwbFile;
	i: integer;
begin
	// Add any explicit masters to each processed plugin and sort their
	// MAST entries for any other added masters (e.g. plugin_master_add,
	// plugin_cell_stat_master_add).
	for i := 0 to Pred(plugin_master_force_queue.count) do begin
		plugin := ObjectToElement(plugin_master_force_queue.Objects[i]);
		__plugin_master_force(plugin);
	end;

	plugin_master_force_queue.clear;
end;

function plugin_file_resolve_existing(pfile: string): IInterface;
var
	t: IInterface;
	i, idx: integer;
begin
	// Attempt to find already created plugin in loaded files
	idx := plugin_file_map.indexOf(pfile);
	if idx >= 0 then begin
		Result := ObjectToElement(plugin_file_map.Objects[idx]);
		Exit;
	end;

	for i := Pred(FileCount) downto 0 do begin
		t := FileByIndex(i);
		if GetFileName(t) = pfile then begin
			plugin_file_map.addObject(pfile, t);
			Result := t;
			Exit;
		end;
	end;

	Result := nil;
end;

function plugin_file_resolve_existing_idx(pfile: string): integer;
var
	t: IInterface;
	idx: integer;
begin
	t := plugin_file_resolve_existing(pfile);
	if not Assigned(t) then begin;
		Result := -1;
		Exit;
	end;

	Result := GetLoadOrder(GetFile(t));
end;

function plugin_output_file_resolve(ofstr: string; mode, area, idx: integer): IInterface;
var
	plugin, m: IInterface;
	b, s, pfile: string;
	i: integer;
begin
	// Attempt to locate existing plugin for the same file or create a new one
	for i := Pred(idx) to Pred(idx + MaxFileAttempts) do begin
		case mode of
		P_MODE_MASTER_CLEAN: begin		b := ofstr; s := InitFileSuffix; end;
		P_MODE_FINAL: begin			b := ofstr; s := FinalFileSuffix; end;
		else
			Exit;
		end;

		if i < idx then begin
			pfile := b + '.' + s + '.' + PluginSuffix;
		end else begin
			pfile := b + '.' + s + '.' + IntToStr(i) + '.' + PluginSuffix;
		end;

		plugin := plugin_file_resolve_existing(pfile);
		if Assigned(plugin) then
			break;

		try
			if FileExists(DataPath + '/' + pfile) then
				continue;

			// create new plugin
			AddMessage('Creating file: ' + pfile);
			plugin := AddNewFileName(pfile);
			if Assigned(plugin) then
				break;
		except
			on Ex: Exception do begin
				if pos('exists already', Ex.Message) <> 0 then
					continue;

				AddMessage('Unable to create new file for ' + pfile);
				Raise Exception.Create(Ex.Message);
			end;
		end;
	end;

	Result := plugin;
end;

function plugin_output_type(e: IInterface): integer;
var
	plugin: IwbFile;
	base: boolean;
begin
	Result := 0;

	plugin := GetFile(e);
	base := is_plugin_base(plugin);

	if plugin_output_base_cell_use and base then begin
		Result := O_TYPE_CELL;
	end else if plugin_output_base_each_use and base then begin
		Result := O_TYPE_EACH;
	end else if plugin_output_base_combined_use and base then begin
		Result := O_TYPE_COMBINED;
	end else if plugin_output_base_use and base then begin
		Result := O_TYPE_DIRECT;
	end else if is_plugin_output_cell(plugin) then begin
		Result := O_TYPE_CELL;
	end else if is_plugin_output_each(plugin) then begin
		Result := O_TYPE_EACH;
	end else if is_plugin_output_combined(plugin) then begin
		Result := O_TYPE_COMBINED;
	end else if is_plugin_output(plugin) then begin
		Result := O_TYPE_DIRECT;
	end else if plugin_output_cell_use then begin
		Result := O_TYPE_CELL;
	end else if plugin_output_each_use then begin
		Result := O_TYPE_EACH;
	end else if plugin_output_combined_use then begin
		Result := O_TYPE_COMBINED;
	end else if plugin_output_use then begin
		if not IsEditable(e) then begin
			Result := O_TYPE_EACH;
		end else begin
			Result := O_TYPE_DIRECT;
		end;
	end;
end;

function plugin_output_file_string(e: IInterface): string;
var
	plugin: IwbFile;
	fname, ofstr, pfx: string;
	base: boolean;
begin
	plugin := GetFile(e);
	fname := GetFileName(plugin);
	base := is_plugin_base(plugin);
	ofstr := fname;
	pfx := '';

	case plugin_output_type(e) of

	O_TYPE_CELL: begin
		if Assigned(plugin_output_base_cell_prefix) and base then begin
			pfx := plugin_output_base_cell_prefix;
		end else if Assigned(plugin_output_cell_prefix) then begin
			pfx := plugin_output_cell_prefix;
		end;
		ofstr := fname + '.' + IntToHex(GetLoadOrderFormID(e), 8);
	end;

	O_TYPE_EACH: begin
		if Assigned(plugin_output_base_each_prefix) and base then begin
			pfx := plugin_output_base_each_prefix;
		end else if Assigned(plugin_output_each_prefix) then begin
			pfx := plugin_output_each_prefix;
		end;
		ofstr := fname;
	end;

	O_TYPE_COMBINED: begin
		if Assigned(plugin_output_base_combined_prefix) and base then begin
			pfx := plugin_output_base_combined_prefix;
		end else if Assigned(plugin_output_combined_prefix) then begin
			pfx := plugin_output_combined_prefix;
		end;
		ofstr := p_area_to_str(process_area);
	end;
{
	O_TYPE_DIRECT: begin
		if Assigned(plugin_output_base_prefix) and base then begin
			pfx := plugin_output_base_prefix;
		end else if Assigned(plugin_output_prefix) then begin
			pfx := plugin_output_prefix;
		end;
	end;
}
	end;

	Result := pfx + ofstr;
end;

function plugin_output_esm_check(e: IInterface): boolean;
var
	plugin: IwbFile;
	base: boolean;
begin
	Result := false;

	plugin := GetFile(e);
	base := is_plugin_base(plugin);

	case plugin_output_type(e) of

	O_TYPE_CELL: begin
		if plugin_output_base_cell_esm and base then begin
			Result := true;
		end else if plugin_output_cell_esm then begin
			Result := true;
		end;
	end;

	O_TYPE_EACH: begin
		if plugin_output_base_each_esm and base then begin
			Result := true;
		end else if plugin_output_each_esm then begin
			Result := true;
		end;
	end;

	O_TYPE_COMBINED: begin
		if plugin_output_base_combined_esm and base then begin
			Result := true;
		end else if plugin_output_combined_esm then begin
			Result := true;
		end;
	end;

	O_TYPE_DIRECT: begin
		if plugin_output_base_esm and base then begin
			Result := true;
		end else if plugin_output_esm then begin
			Result := true;
		end;
	end;

	end;

end;

function plugin_output_resolve(e: IInterface): IwbFile;
var
	plugin, plugin_output: IwbFile;
	fname, ofstr: string;
	i, otype: integer;
begin
	plugin := GetFile(e);

	otype := plugin_output_type(e);
	if otype = O_TYPE_NONE then begin
		Result := nil;
		Exit;
	end else if otype = O_TYPE_DIRECT then begin
		plugin_output := GetFile(e);
	end else begin
		ofstr := plugin_output_file_string(e);
		plugin_output := plugin_output_file_resolve(ofstr, process_mode, process_area, 0);
	end;

	// flag as esm if necessary
	if plugin_output_esm_check(e) then
		plugin_esm_set(plugin_output, true);

	// queue this plugin for processing of any additional masters
	plugin_master_force(plugin_output);

	// add the plugin this was based off of as a master
	plugin_master_add(plugin_output, plugin, true, true, true);

	// Add plugin filename to tracking list so it can be emitted
	// along with all other plugins being operated on.
	if plugin_output_log_use and Assigned(plugin_output_log) then begin
		fname := GetFileName(plugin_output);
		if not plugin_output_log_list.indexOf(fname) >= 0 then
			plugin_output_log_list.add(fname);
	end;

	Result := plugin_output;
end;

procedure plugin_esm_set(plugin: IwbFile; enable: boolean);
var
	flags: cardinal;
begin
	if not (enable xor GetIsESM(plugin)) then
		Exit;

	if enable then begin
		AddMessage(Format('%s: setting ESM flag', [GetFileName(plugin)]));
	end else begin
		AddMessage(Format('%s: removing ESM flag', [GetFileName(plugin)]));
	end;

	SetIsESM(plugin, enable);
end;

procedure plugin_elem_remove(plugin: IwbFile; e: IInterface);
var
	t: IInterface;
	i: integer;
begin
	// XXX: MasterOrSelf?
	for i := Pred(OverrideCount(e)) downto -1 do begin
		t := override_or_master(e, i);

		if not Equals(plugin, GetFile(t)) then
			continue;

		Remove(t);
		Exit;
	end;
end;

function elem_copy_deep(plugin: IwbFile; e: IInterface): IInterface;
begin
	elem_masters_add(plugin, e);

	try
		Result := wbCopyElementToFile(e, plugin, false, true);
	except
		on Ex: Exception do begin
			plugin_elem_remove(plugin, e);
			Raise Exception.Create(Ex.Message);
		end;
	end;
end;

function elem_error_check(e: IInterface): boolean;
var
	i, j: integer;
	t, r: IInterface;
begin
	for i := 0 to Pred(ElementCount(e)) do begin
		t := ElementByIndex(e, i);
		for j := 0 to Pred(ElementCount(t)) do begin
			r := ElementByIndex(t, j);
			if Check(r) <> '' then begin
				if Debug then
//					AddMessage(Format('%s: elem_error_check: failed: %s: %s', [ GetFileName(r), Check(r), Path(r) ]));
				Result := false;
				Exit;
			end;
		end;

		if Check(t) <> '' then begin
			if Debug then
//				AddMessage(Format('%s: elem_error_check: failed: %s: %s', [ GetFileName(t), Check(t), Path(t) ]));
			Result := false;
			Exit;
		end;
	end;

	Result := true;
end;

function elem_cell_check(e: IInterface): boolean;
var
	a, b: integer;
begin
	a := FormID(LinksTo(ElementByPath(MasterOrSelf(e), 'CELL'))) and $00ffffff;
	b := FormID(LinksTo(ElementByPath(e, 'CELL'))) and $00ffffff;
	Result := (a = b);
	if not Result and Debug then begin
		AddMessage(Format('%s: elem_cell_check: mismatch: %s != %s (%0.8x != %0.8x)', [ GetFileName(e), Name(MasterOrSelf(e)), Name(e), a, b ]));
	end;
end;

procedure elem_masters_add(plugin: IwbFile; e: IInterface);
var
	tfile: IwbFile;
	sl: TStringList;
	i: integer;
begin
	if not PerElementMasters then begin
		plugin_master_add(plugin, e, true, true, true);
		Exit;
	end;

	sl := TStringList.create;
	ReportRequiredMasters(e, sl, false, true);
	for i := 0 to Pred(sl.count) do begin
		if sl[i] = GetFileName(plugin) then
			continue;
		if HasMaster(plugin, sl[i]) then
			continue;

		tfile := plugin_file_resolve_existing(sl[i]);
		plugin_master_add(plugin, tfile, true, false, true);
	end;
	sl.free;

	SortMasters(plugin);
end;

procedure elem_previs_flag_clear(e: IInterface);
var
	m: IInterface;
	flags, mflags: cardinal;
begin
	if not (PrevisFlagRemove or PrevisFlagForceRemove) then
		Exit;

	m := MasterOrSelf(e);

	flags := GetElementNativeValues(e, 'Record Header\Record Flags');
	mflags := GetElementNativeValues(m, 'Record Header\Record Flags');

	// If record has 'no previs' set but master does not, remove it
	if ((flags and F_NOPREVIS) <> 0) and (PrevisFlagForceRemove or ((mflags and F_NOPREVIS) = 0)) then begin
		if not PrevisFlagForceRemove then
			AddMessage(Format('%s: Warning: clearing explicitly set "no previs" flag: %s', [GetFileName(e), Name(e)]));
		SetElementNativeValues(e, 'Record Header\Record Flags', flags and not F_NOPREVIS);
	end;
end;

function elem_marker_check(e: IInterface): Boolean;
var
	flags: cardinal;
begin
	flags := GetElementNativeValues(e, 'Record Header\Record Flags');
	if (flags and F_MARKER) <> 0 then begin
		Result := true;
		Exit;
	end;

	Result := false;
end;

function elem_deleted_check(e: IInterface): Boolean;
var
	flags: cardinal;
begin
	flags := GetElementNativeValues(e, 'Record Header\Record Flags');
	if (flags and F_DELETED) <> 0 then begin
		Result := true;
		Exit;
	end;

	Result := false;
end;

procedure elem_sync(e, r: IInterface; s: string);
begin
	if ElementExists(e, s) then begin
		if not ElementExists(r, s) then
			Add(r, s, true);
		ElementAssign(ElementBySignature(r, s), LowInteger, ElementBySignature(e, s), false);
	end else if ElementExists(r, s) then begin
		RemoveElement(r, s);
	end;
end;

procedure elem_pc_sync(e, r: IInterface);
var
	i: integer;
	s: string;
begin
	// Copy precombine records from e to r
	for i := 0 to Pred(length(pc_sig_tab)) do begin
		s := pc_sig_tab[i];
		elem_sync(e, r, s);
	end;
end;

procedure elem_pv_sync(e, r: IInterface);
var
	i: integer;
	s: string;
begin
	// Copy previs records from e to r
	for i := 0 to Pred(length(pv_sig_tab)) do begin
		s := pv_sig_tab[i];
		elem_sync(e, r, s);
	end;
end;

procedure elem_version_sync(e, r: IInterface);
begin
	SetFormVersion(r, GetFormVersion(e));
	SetFormVCS1(r, GetFormVCS1(e));
	SetFormVCS2(r, GetFormVCS2(e));
end;

function cell_cache_key(e: IInterface): string;
var
	cxy: TwbGridCell;
	ws: string;
begin
	// XXX: Error check this
	ws := cell_world_edid(e);
	cxy := GetGridCell(e);
	Result := ws + ',' + IntToStr(cxy.x) + ',' + IntToStr(cxy.y);
end;

function cell_cache_resolve(ws: string; x, y: integer): IInterface;
var
	key: string;
	idx: integer;
begin
	key := ws + ',' + IntToStr(x) + ',' + IntToStr(y);
	idx := cell_cache.indexOf(key);
	if idx >= 0 then begin
		if Profile then Inc(cell_cache_hits);
		Result := ObjectToElement(cell_cache.Objects[idx]);
	end else begin
		if Profile then Inc(cell_cache_misses);
		Result := nil;
	end;
end;

function cell_cache_add_ws(ws: string; x, y: integer; e: IInterface): boolean;
var
	key: string;
begin
	Result := false;

	key := ws + ',' + IntToStr(x) + ',' + IntToStr(y);
//	if not cell_cache.indexOf(key) >= 0 then begin
		cell_cache.addObject(key, e);
		Result := true;
//	end;
end;

function cell_cache_add(e: IInterface): boolean;
var
	key: string;
begin
	Result := false;

	key := cell_cache_key(e);
//	if not cell_cache.indexOf(key) >= 0 then begin
		cell_cache.addObject(key, e);
		Result := true;
//	end;
end;

function cell_cache_remove(e: IInterface): boolean;
var
	key: string;
	idx: integer;
begin
	Result := false;

	key := cell_cache_key(e);
	idx := cell_cache.indexOf(key);
	if idx >= 0 then begin
		cell_cache.delete(idx);
		Result := true;
	end;
end;

function cell_queue_add(e: IInterface): boolean;
var
	tl: TList;
	key: string;
	idx: integer;
begin
	// XXX: is cell_queue_seen even needed as a separate list?
	// XXX: why wont cell_queue.indexOf directly work?
	key := GetFileName(e) + ',' + IntToStr(GetLoadOrderFormID(e));
	if cell_queue_seen.indexOf(key) >= 0 then begin
		Result := false;
		Exit;
	end;
	cell_queue_seen.add(key);

	idx := GetLoadOrder(GetFile(e));
	if idx >= cell_queue.count then
		cell_queue.count := idx + 1;

	if not Assigned(cell_queue[idx]) then begin
		tl := Tlist.create;
		cell_queue[idx] := tl;
	end else begin
		tl := TList(cell_queue[idx]);
	end;

	tl.add(e);

	Result := true;
end;

function cell_queue_remove(e: IInterface): boolean;
var
	tl: TList;
	key: string;
	idx: integer;
begin
	Result := false;

	// XXX: is cell_queue_seen even needed as a separate list?
	// XXX: why wont cell_queue.indexOf directly work?
	key := GetFileName(e) + ',' + IntToStr(GetLoadOrderFormID(e));
	idx := cell_queue_seen.indexOf(key);
	if idx >= 0 then begin
		cell_queue_seen.delete(idx);
	end;

	idx := GetLoadOrder(GetFile(e));
	if idx < cell_queue.count then begin
		if Assigned(cell_queue[idx]) then begin
			tl := TList(cell_queue[idx]);
if not Assigned(tl) then
Raise Exception.create('cell_queue_remove: tl is NOT assigned');
			idx := tl.indexOf(e);
			if idx >= 0 then
				tl.delete(idx);
			Result := true;
		end;
	end;
end;

procedure cell_remove(e: IInterface);
begin
	cell_rvis_grid_cache_remove(e);
	cell_rvis_cache_remove(e);
	cell_cache_remove(e);
	cell_queue_remove(e);

	if Debug then
		AddMessage(Format('%s: Removing: %s', [GetFileName(e), Name(e)]));
	RemoveNode(e);

	Inc(cell_clean_cnt);
end;

function cell_refr_stat_check(e: IInterface): boolean;
begin
	Result := Assigned(cell_refr_stat_first(e, false, false));
end;

function cell_refr_rvis_check(e: IInterface): boolean;
begin
	Result := Assigned(cell_refr_rvis_first(e, false, false));
end;

function cell_navm_check(e: IInterface): boolean;
begin
	Result := Assigned(cell_navm_first(e, false, false));
end;

function cell_navm_ent_filter(e: IInterface; error_check, cell_check: boolean): IInterface;
var
	t: IInterface;
	i: integer;
begin
	for i := 0 to Pred(ElementCount(e)) do begin
		t := ElementByIndex(e, i);
		if not Assigned(t) then
			continue;

		if Signature(t) <> 'NAVM' then
			continue;

		// deleted references should be considered matching
		if elem_deleted_check(t) then
			t := MasterOrSelf(t);

		// ignore refs with problems
		if error_check then begin
			if not elem_error_check(t) then
				continue;
		end;

		// ignore refs outside of the cell xedit thinks they should be in
		if cell_check then begin
			if not elem_cell_check(t) then
				continue;
		end;

		Result := t;
		Exit;
	end;

	Result := nil;
end;

function cell_refr_stat_all(e: IInterface; ref_check, cell_check: boolean): IInterface;
var
	cg, r, t, b: IInterface;
	i, j: integer;
begin
	if Signature(e) <> 'CELL' then
		Exit;

	cg := ChildGroup(e);
	if not Assigned(cg) then
		Exit;
//	AddMessage('cg: ' + FullPath(cg));

	for i := 0 to Pred(ElementCount(cg)) do begin
		r := ElementByIndex(cg, i);
		if not Assigned(r) then
			continue;

//		AddMessage('r: ' + FullPath(r));

		for j := 0 to Pred(ElementCount(r)) do begin
			t := ElementByIndex(r, j);
			if not Assigned(t) then
				continue;

			s := Signature(t);
			if not pc_keep_map.indexOf(s) >= 0 then
				continue;

			// deleted references should be considered matching
			if elem_deleted_check(t) then
				t := MasterOrSelf(t);

			b := BaseRecord(t);
			s := Signature(b);
			if not pc_base_keep_map.indexOf(s) >= 0 then
				continue;

			// ignore markers entirely
			if elem_marker_check(b) then
				continue;

			// ignore refs with problems
			if ref_check then begin
				if not elem_error_check(t) then
					continue;
			end;

			// ignore refs outside of the cell xedit thinks they should be in
			if cell_check then begin
				if not elem_cell_check(t) then
					continue;
			end;

			AddMessage('t: ' + FullPath(t));

//			XXX: TList?
//			Result := t;
//			Exit;
		end;
	end;
end;

function cell_refr_ent_filter(e: IInterface; filter, base_filter: THashedStringList; error_check, cell_check, precombined_only: boolean): IInterface;
var
	t, b: IInterface;
	i: integer;
	s: string;
begin
	for i := 0 to Pred(ElementCount(e)) do begin
		t := ElementByIndex(e, i);
		if not Assigned(t) then
			continue;

		s := Signature(t);
		if not filter.indexOf(s) >= 0 then
			continue;

		// deleted references should be considered matching
		if elem_deleted_check(t) then
			t := MasterOrSelf(t);

		b := BaseRecord(t);
		s := Signature(b);
		if not base_filter.indexOf(s) >= 0 then
			continue;

		// ignore markers entirely
		if elem_marker_check(b) then
			continue;

		// ignore non-precombined refs
		if precombined_only then begin
			if not HasPrecombinedMesh(t) then
				continue;
		end;

		// ignore refs with problems
		if error_check then begin
			if not elem_error_check(t) then
				continue;
		end;

		// ignore refs outside of the cell xedit thinks they should be in
		if cell_check then begin
			if not elem_cell_check(t) then
				continue;
		end;

		Result := t;
		Exit;
	end;

	Result := nil;
end;

function cell_refr_rvis_first(e: IInterface; error_check, cell_check: boolean): IInterface;
var
	cg, r, t: IInterface;
	i, j: integer;
	children: array[0..1] of IInterface;
	filter, bfilter: THashedStringList;
	precombined_only: boolean;
begin
	if Signature(e) <> 'CELL' then
		Exit;

	cg := ChildGroup(e);
	if not Assigned(cg) then
		Exit;
//	AddMessage('cg: ' + FullPath(cg));

	children[0] := nil;
	children[1] := nil;

	// Prioritize temporary references over persistent ones
	for i := 0 to Pred(ElementCount(cg)) do begin
		r := ElementByIndex(cg, i);
		case GroupType(r) of
		9: children[0] := r; // temporary
		8: children[1] := r; // persistent
		end;
	end;

	// Prioritize statics references over non-statics
	for i := 0 to Pred(length(children)) do begin
		r := children[i];
		if not Assigned(r) then
			continue;
//		AddMessage('r: ' + FullPath(r));

		for j := 0 to 2 do begin
			case j of
			0: begin filter := pc_keep_map; bfilter := pc_base_keep_map; precombined_only :=  true; end;
			1: begin filter := pc_keep_map; bfilter := pc_base_keep_map; precombined_only := false; end;
			2: begin filter := pv_keep_map; bfilter := pv_base_keep_map; precombined_only := false; end;
			end;

			t := cell_refr_ent_filter(r, filter, bfilter, error_check, cell_check, precombined_only);
			if Assigned(t) then begin
//				if i = 1 then
//					AddMessage('PERSISTENT: ' + FullPath(t));
//				AddMessage('t: ' + FullPath(t));
				Result := t;
				Exit;
			end;
		end;
	end;

	Result := nil;
end;

function cell_refr_stat_first(e: IInterface; error_check, cell_check: boolean): IInterface;
var
	cg, r, t: IInterface;
	i, j: integer;
	children: array[0..1] of IInterface;
	filter, bfilter: THashedStringList;
	precombined_only: boolean;
begin
	if Signature(e) <> 'CELL' then
		Exit;

	cg := ChildGroup(e);
	if not Assigned(cg) then
		Exit;
//	AddMessage('cg: ' + FullPath(cg));

	children[0] := nil;
	children[1] := nil;

	// Prioritize temporary references over persistent ones
	for i := 0 to Pred(ElementCount(cg)) do begin
		r := ElementByIndex(cg, i);
		case GroupType(r) of
		9: children[0] := r; // temporary
		8: children[1] := r; // persistent
		end;
	end;

	// Prioritize statics references over non-statics
	for i := 0 to Pred(length(children)) do begin
		r := children[i];
		if not Assigned(r) then
			continue;
//		AddMessage('r: ' + FullPath(r));

		for j := 0 to 1 do begin
			case j of
			0: begin filter := pc_keep_map; bfilter := pc_base_keep_map; precombined_only :=  true; end;
			1: begin filter := pc_keep_map; bfilter := pc_base_keep_map; precombined_only := false; end;
			end;

			t := cell_refr_ent_filter(r, filter, bfilter, error_check, cell_check, precombined_only);
			if Assigned(t) then begin
//				if i = 1 then
//					AddMessage('PERSISTENT: ' + FullPath(t));
//				AddMessage('t: ' + FullPath(t));
				Result := t;
				Exit;
			end;
		end;
	end;

	Result := nil;
end;

function cell_navm_first(e: IInterface; error_check, cell_check: boolean): IInterface;
var
	cg, r, t: IInterface;
	i: integer;
begin
	if Signature(e) <> 'CELL' then
		Exit;

	cg := ChildGroup(e);
	if not Assigned(cg) then
		Exit;
//	AddMessage('cg: ' + FullPath(cg));

	for i := 0 to Pred(ElementCount(cg)) do begin
		r := ElementByIndex(cg, i);
		if not Assigned(r) then
			continue;
//		AddMessage('r: ' + FullPath(r));

		t := cell_navm_ent_filter(r, error_check, cell_check);
		if Assigned(t) then begin
//			if i = 1 then
//				AddMessage('PERSISTENT: ' + FullPath(t));
//			AddMessage('t: ' + FullPath(t));
			Result := t;
			Exit;
		end;
	end;

	Result := nil;
end;

function cell_world_edid(e: IInterface): string;
var
	t, w: IInterface;
begin
	// Note: Psuedo-record 'Worldspace' is only present in exterior cells
	t := ElementByPath(e, 'Worldspace');
	if not Assigned(t) then begin
		Result := 'none';
		Exit;
	end;

	w := LinksTo(t);
	if (not Assigned(w)) or (Signature(w) <> 'WRLD') then begin
		// Workaround for a bug in xedit that corrupts the worldspace
		// value on master change.
		w := ChildrenOf(GetContainer(GetContainer(GetContainer(e))));
		AddMessage('cell_world_edid (workaround): w: ' + FullPath(w));
	end;

	Result := GetElementEditValues(w, 'EDID');
end;

function cell_resolve_world(world_str: string): IInterface;
var
	plugin, wg, w: IInterface;
	i, j: integer;
begin
	Result := nil;

	// Plugins
	for i := 0 to Pred(FileCount) do begin
		plugin := FileByIndex(i);

		wg := GroupBySignature(plugin, 'WRLD');
		if not Assigned(wg) then continue;

		// Worldspaces
		for j := 0 to Pred(ElementCount(wg)) do begin
			w := ElementByIndex(wg, j);
			if GetElementEditValues(w, 'EDID') <> world_str then
				continue;

			Result := w;
			Exit;
		end;
	end;
end;

function cell_group_coord_check(g: IInterface; x, y: integer): Boolean;
var
	gl: cardinal;
	gx, gy: word;
begin
	// Extract sub-block x,y from group label (y,x on disk)
	gl := GroupLabel(g);
	gx := Word((gl and $ffff0000) shr 16);
	gy := Word(gl and $0000ffff);

	Result := (gx = x) and (gy = y);
end;

function cell_resolve(world_str: string; x, y: integer): IInterface;
var
	plugin, wg, bg, sg, w, t: IInterface;
	cxy: TwbGridCell;
	i, j: integer;
	bx, by, sbx, sby: integer;
begin
	// Check cell cache first and return early if found
	if CacheCells then begin
		t := cell_cache_resolve(world_str, x, y);
		if Assigned(t) then begin
			Result := t;
			Exit;
		end;
	end;

	// Resolve x,y to block/sub-block
	bx := x div 32; if (x < 0) and (x mod 32 <> 0) then dec(bx);
	by := y div 32; if (y < 0) and (y mod 32 <> 0) then dec(by);

	sbx := x div 8; if (x < 0) and (x mod 8 <> 0) then dec(sbx);
	sby := y div 8; if (y < 0) and (y mod 8 <> 0) then dec(sby);

//	AddMessage(Format('xy: %d,%d | bxy: %d,%d | sbxy: %d,%d', [x,y,bx,by,sbx,sby]));

	// Plugins
	for i := 0 to Pred(FileCount) do begin
		plugin := FileByIndex(i);

		wg := GroupBySignature(plugin, 'WRLD');
		if not Assigned(wg) then continue;

		// Worldspaces
		w := nil; for j := 0 to Pred(ElementCount(wg)) do begin
			t := ElementByIndex(wg, j);
			if GetElementEditValues(t, 'EDID') = world_str then begin
				w := t;
				break;
			end;
		end;
		if not Assigned(w) then continue;

		// World children
		wg := ChildGroup(w);
		bg := nil; for j := 0 to Pred(ElementCount(wg)) do begin
			// Blocks
			t := ElementByIndex(wg, j);

			// Exterior Cell Blocks only (ignore persistent worldspace cells)
			if GroupType(t) <> 4 then continue;

			// Check if the cell is within this block.
			if cell_group_coord_check(t, bx, by) then begin
				bg := t;
				break;
			end;
		end;
		if not Assigned(bg) then continue;

		sg := nil; for j := 0 to Pred(ElementCount(bg)) do begin
			// Sub-blocks
			t := ElementByIndex(bg, j);

			// Check if the cell is within this block.
			if cell_group_coord_check(t, sbx, sby) then begin
				sg := t;
				break;
			end;
		end;
		if not Assigned(sg) then continue;

		for j := 0 to Pred(ElementCount(sg)) do begin
			// Cells
			t := ElementByIndex(sg, j);

			// Ignore GRUPs (children of cells)
			if Signature(t) <> 'CELL' then continue;

			// Get coordinates of cell and compare it against target
			cxy := GetGridCell(t);
			if (cxy.x = x) and (cxy.y = y) then begin
				// Return only the original source of the CELL
				t := MasterOrSelf(t);
				if CacheCells then begin
					if NegativeCaching or Assigned(t) then
						cell_cache_add_ws(world_str, x, y, t);
				end;

				Result := t;
				Exit;
			end;
		end;
	end;

	Result := nil;
end;

function cell_rvis_grid_cache_resolve(e: IInterface): TList;
var
	tl: TList;
	key: string;
	idx: integer;
begin
	key := IntToStr(GetLoadOrderFormID(e));
	idx := cell_rvis_grid_cache.indexOf(key);
	if idx >= 0 then begin
		if Profile then Inc(cell_rvis_grid_cache_hits);
		Result := TList(cell_rvis_grid_cache.Objects[idx]);
	end else begin
		if Profile then Inc(cell_rvis_grid_cache_misses);
		Result := nil;
	end;
end;

function cell_rvis_grid_cache_add(e: IInterface; tl: TList): boolean;
var
	key: string;
begin
	Result := false;

	key := IntToStr(GetLoadOrderFormID(e));
//	if not cell_rvis_grid_cache.indexOf(key) >= 0 then begin
		cell_rvis_grid_cache.addObject(key, tl);
		Result := true;
//	end;
end;

function cell_rvis_grid_cache_remove(e: IInterface): boolean;
var
	r: IInterface;
	tl: TList;
	key: string;
	idx, j: integer;
begin
	Result := false;

	key := IntToStr(GetLoadOrderFormID(e));
	idx := cell_rvis_grid_cache.indexOf(key);
	if idx >= 0 then begin
		tl := TList(cell_rvis_grid_cache.Objects[idx]);
		tl.free;

		cell_rvis_grid_cache.delete(idx);
		Result := true;
	end;

	// Remove any entries which might be referencing this cell
	// XXX: This wont have good performance without another map
	for idx := Pred(cell_rvis_grid_cache.count) downto 0 do begin
		tl := TList(cell_rvis_grid_cache.Objects[idx]);
		if not Assigned(tl) then
			continue;
		for j := Pred(tl.count) downto 0 do begin
			r := ObjectToElement(cell_rvis_grid_cache.Objects[j]);
			if Assigned(r) and Equals(r, e) then
				tl.delete(j);
		end;
	end;
end;

function cell_rvis_cache_resolve(e: IInterface): IInterface;
var
	key: string;
	idx: integer;
begin
	key := IntToStr(GetLoadOrderFormID(e));
	idx := cell_rvis_cache.indexOf(key);
	if idx >= 0 then begin
		if Profile then Inc(cell_rvis_cache_hits);
		Result := ObjectToElement(cell_rvis_cache.Objects[idx]);
	end else begin
		if Profile then Inc(cell_rvis_cache_misses);
		Result := nil;
	end;
end;

function cell_rvis_cache_add(e, r: IInterface): boolean;
var
	key: string;
begin
	Result := false;

	key := IntToStr(GetLoadOrderFormID(e));
//	if not cell_rvis_cache.indexOf(key) >= 0 then begin
		cell_rvis_cache.addObject(key, r);
		Result := true;
//	end;
end;

function cell_rvis_cache_remove(e: IInterface): boolean;
var
	r: IInterface;
	key: string;
	idx: integer;
begin
	Result := false;

	key := IntToStr(GetLoadOrderFormID(e));
	idx := cell_rvis_cache.indexOf(key);
	if idx >= 0 then begin
		cell_rvis_cache.delete(idx);
		Result := true;
	end;

	// Remove any entries which might be referencing this cell
	// XXX: This wont have good performance without another map
	for idx := Pred(cell_rvis_cache.count) downto 0 do begin
		r := ObjectToElement(cell_rvis_cache.Objects[idx]);
		if Assigned(r) and Equals(r, e) then
			cell_rvis_cache.delete(idx);
	end;
end;

// Determine rvis cell for a given cell based on either the
// value of the RVIS element or, if missing, coordinates.
function cell_rvis_cell(e: IInterface): IInterface;
var
	r, t: IInterface;
	rxy: TwbGridCell;
	cxy: array[0..1] of TwbGridCell;
	xy: array[0..1,0..1] of integer;
	m, i: integer;
	ws: string;
begin
	// Non-persistent exterior cells only
	if not cell_filter(e, true, true, false, false) then begin
		Exit;
	end;

//	AddMessage('cell_rvis_cell: ' + FullPath(e));

	if CacheRvisCells then begin
		r := cell_rvis_cache_resolve(e);
		if Assigned(r) then begin
			Result := r;
			Exit;
		end;
	end;

	r := ElementBySignature(e, 'RVIS');
	if Assigned(r) then begin
		r := LinksTo(r);
		if Signature(r) = 'CELL' then begin
			if CacheRvisCells then
				cell_rvis_cache_add(e, r);
			Result := r;
			Exit;
		else
			// bad RVIS data
			r := nil;
		end;
	end;

	// No RVIS element found, attempt to calculate the
	// 3x3 grid with RVIS cell at center and no overlap.
	// For coordinates that are only 1 away from the RVIS
	// center, consider it inside of that vis grid. If more
	// than 2 away, it must be within an adjacent vis grid.
	//
	// +---+---+---+---+---+---+
	// |2,4|3,4|4,4|5,4|6,4|7,4|
	// +---/---\---+---/---\---+
	// |2,3|3,3|4,3|5,3|6,3|7,3|
	// +---\---/---+---\---/---+
	// |2,2|3,2|4,2|5,2|6,2|7,2|
	// +---+---+---+---+---+---+
	//
	// In the above, 3,3 and 6,3 are RVIS cells whereas
	// 4,3 and 5,3 are part of each 3v3 grid respectively.

	// GetGridCell returns objects with 'x' and 'y' members
	// but due to the way the for loop works, its harder
	// to work with things in that manner. Reorient x,y
	// into an array like so: xy[x,y][in,out]
	cxy[0] := GetGridCell(e);
	xy[0,0] := cxy[0].x;
	xy[1,0] := cxy[0].y;

	for i := 0 to Pred(length(cxy)) do begin
		m := abs(xy[i,0]) mod VIS_WIDTH;
		if m = 0 then begin
			xy[i,1] := xy[i,0];
		end else if m <= VIS_WIDTH div 2 then begin
			// within the same vis grid (e.g. vis: -24,-3, xy: -25,-4)
			if xy[i,0] < 0 then begin
				xy[i,1] := xy[i,0] + m;
			end else begin
				xy[i,1] := xy[i,0] - m;
			end;
		end else begin
			// within an adjacent vis grid (e.g. vis: -24,-3, xy: -26,-2)
			if xy[i,0] < 0 then begin
				xy[i,1] := xy[i,0] - (VIS_WIDTH - m);
			end else begin
				xy[i,1] := xy[i,0] + (VIS_WIDTH - m);
			end;
		end;
	end;

	// copy calculation back out, but keep original
	cxy[1].x := xy[0,1];
	cxy[1].y := xy[1,1];

	// XXX: this is not being hit here due to the early exit for RVIS above.
	// Cross check calculated value against coordinates of RVIS value if present
	if Assigned(r) then begin
		rxy := GetGridCell(r);
		if (rxy.x <> cxy[1].x) or (rxy.y <> cxy[1].y) then begin
			AddMessage('Computed coordinates do not match RVIS');
			AddMessage(FullPath(e));
			AddMessage(FullPath(r));
			AddMessage(Format('cxy[0]: %d,%d | cxy[1]: %d,%d | rxy: %d,%d | xm: %d, ym: %d',
				[cxy[0].x, cxy[0].y, cxy[1].x, cxy[1].y, rxy.x, rxy.y, cxy[0].x mod 3, cxy[0].y mod 3]));
			Exit;
		end;
	end;

	// Resolve cell by coordinates relative to worldspace
	ws := cell_world_edid(e);
	r := cell_resolve(ws, cxy[1].x, cxy[1].y);
	if CacheRvisCells then begin
		if NegativeCaching or Assigned(r) then
			cell_rvis_cache_add(e, r);
	end;

{
	if Assigned(r) then begin
		AddMessage('cell_rvis_cell: resolved (calculated): ' + FullPath(r));
	end else begin
		AddMessage('cell_rvis_cell: unable to resolve RVIS cell: ' + FullPath(e));
	end;
}

	Result := r;
end;

// Return a list of all rvis cells for a given input cell. Since CK
// calculates +/-1,1 for each input cell, border cells may result in
// the generation of up to 4 rvis cells, even though the cell itself
// is only part of a single rvis cell.
function cell_rvis_rvis_grid(e: IInterface; offset: integer): TList;
var
	tl: TList;
	r, t: IInterface;
	seen: THashedStringList;
	cxy: TwbGridCell;
	ix, iy: integer;
	ws, key: string;
begin
	// Ensure only unique cells are returned
	seen := THashedStringList.create;
	seen.sorted := true;
	seen.duplicates := dupIgnore;

	tl := TList.create;
	ws := cell_world_edid(e);
	cxy := GetGridCell(e);
	for ix := -offset to offset do begin
		for iy := -offset to offset do begin
			t := cell_resolve(ws, cxy.x + ix, cxy.y + iy);
			if not Assigned(t) then
				continue;

			r := cell_rvis_cell(t);
			if not Assigned(r) then
				continue;

			// Filter out duplicate RVIS cells
			key := IntToStr(GetLoadOrderFormID(r));
			if seen.indexOf(key) >= 0 then
				continue;
			seen.add(key);

			tl.add(r);
		end;
	end;

	seen.free;

	Result := tl;
end;

// For all rvis cells involved with a given input cell, resolve every
// cell within each 3x3 rvis grid.
function cell_rvis_cell_grid(e: IInterface): TList;
var
	tl, rgl, rvl: TList;
	r, t: IInterface;
	cxy: TwbGridCell;
	i, jx, jy, k: integer;
	x, y: integer;
	ws: string;
	key: string;
begin
	ws := cell_world_edid(e);
	rvl := cell_rvis_rvis_grid(e, VIS_OFFSET);
	rgl := TList.create;

	for i := 0 to Pred(rvl.count) do begin
		r := ObjectToElement(rvl[i]);
		if not Assigned(r) then
			continue;

		if CacheRvisGridCells then begin
			tl := cell_rvis_grid_cache_resolve(r);
			if Assigned(tl) then begin
				rgl.add(tl);
				continue;
			end;
		end;

		// Add the RVIS cell to the front of the list
		// so that it can be predictably referenced at
		// index 0 by client code.
		tl := TList.create;
		tl.add(r);

		// Get the coordinates of the RVIS cell and find all
		// directly and 1 greater adjacent cells in the grid.
		// Cells 1 cell outside of the given RVIS cell are
		// considered involved due to the way CK considers
		// which RVIS cells to generate (see cell_rvis_rvis_grid).
		cxy := GetGridCell(r);
		for jx := (-1 - VIS_OFFSET) to (1 + VIS_OFFSET) do begin
			for jy := (-1 - VIS_OFFSET) to (1 + VIS_OFFSET) do begin
				x := cxy.x + jx;
				y := cxy.y + jy;
				t := cell_resolve(ws, x, y);
				if not Assigned(t) then begin
//					AddMessage(Format('cell_rvis_cell_grid: %s: rvxy(%d,%d): %d,%d :: %s', [FullPath(r),cxy.x,cxy.y,x,y,'nil']));
					continue;
				end;

				// Since the RVIS cell already occupies the first slot
				// ignore the relative 0,0 offset as it is the same cell.
				if (jx = 0) and (jy = 0) then begin
//					if GetLoadOrderFormID(r) <> GetLoadOrderFormID(t) then begin
					if not Equals(r, t) then begin
						AddMessage('cell_rvis_cell_grid: r != t!');
						AddMessage(Format('cell_rvis_cell_grid: ws: %s, x: %d, y: %d', [ws,x,y]));
						AddMessage(Format('cell_rvis_cell_grid: e: %s', [FullPath(e)]));
						AddMessage(Format('cell_rvis_cell_grid: r: %s', [FullPath(r)]));
						AddMessage(Format('cell_rvis_cell_grid: t: %s', [FullPath(t)]));

						Raise Exception.Create('r != t');
					end;
					continue;
				end;

//				AddMessage(Format('cell_rvis_cell_grid: %s: rvxy(%d,%d): %d,%d :: %s', [FullPath(r),cxy.x,cxy.y,x,y,FullPath(t)]));
				tl.add(t);
			end;
		end;

		rgl.add(tl);

		if CacheRvisGridCells then
			cell_rvis_grid_cache_add(r, tl);
	end;

	Result := rgl;
end;

function cell_filter(e: IInterface; main_allow, other_allow, interior_allow, persistent_allow: boolean): boolean;
var
	t: IInterface;
	cxy: TwbGridCell;
	is_main, is_interior, is_persistent: boolean;
	ws: string;
	flags: cardinal;
	i: integer;
begin
	Result := false;

	// Skip non-cells
	if Signature(e) <> 'CELL' then
		Exit;

	if elem_deleted_check(e) then
		e := MasterOrSelf(e);

	// Skip persistent worldspace cells (which never have precombines/previs)
	flags := GetElementNativeValues(e, 'Record Header\Record Flags');
	is_persistent := ((flags and F_PERSISTENT) <> 0);
	if is_persistent and not persistent_allow then
		Exit;

	is_interior := (GetElementEditValues(e, 'DATA\Is Interior Cell') = '1');
	if not is_interior then begin
		ws := cell_world_edid(e);
		is_main := (ws = 'Commonwealth');
		if is_main and not main_allow then
			Exit;
		if not is_main and not other_allow then
			Exit;

		if cell_keep_use then begin
			// Filter by coordinates
			//              +96
			//               |
			//               |
			//               |
			//               |
			// -96 ----------0---------- +96
			//               |
			//               |
			//               |
			//               |
			//              -96

			cxy := GetGridCell(e);
			if cxy.x < cell_keep_xy[0].x then
				Exit;
			if cxy.x > cell_keep_xy[1].x then
				Exit;
			if cxy.y < cell_keep_xy[0].y then
				Exit;
			if cxy.y > cell_keep_xy[1].y then
				Exit;
//			AddMessage(Format('%d,%d: cell passed coord check', [ cxy.x, cxy.y ]));
		end;
	end else if not interior_allow then begin
		Exit;
	end;

	Result := true;
end;

procedure cell_xcri_clean(e: IInterface);
var
	i: integer;
begin
	for i := 0 to Pred(length(pc_sig_tab)) do begin
		if ElementExists(e, pc_sig_tab[i]) then
			RemoveElement(e, ElementBySignature(e, pc_sig_tab[i]));
	end;
end;

procedure cell_xpri_clean(e: IInterface);
var
	i: integer;
begin
	for i := 0 to Pred(length(pv_sig_tab)) do begin
		if ElementExists(e, pv_sig_tab[i]) then
			RemoveElement(e, ElementBySignature(e, pv_sig_tab[i]));
	end;
end;

function plugin_cell_copy_safe(plugin: IwbFile; e: IInterface; xcri_clean, xpri_clean, previs_flag_clear: boolean): IInterface;
var
	t: IInterface;
begin
	// do not allow copying over self
	if Equals(plugin, GetFile(e)) then begin
		Result := e;
		Exit;
	end;

	t := plugin_cell_find(plugin, e);
	if Assigned(t) then begin
		if not CellCopyOverwrite then begin
			Result := t;
			Exit;
		end;

		Remove(t);
	end;

	t := form_copy_safe(plugin, e, (not xcri_clean), (not xpri_clean));
	if xcri_clean then
		cell_xcri_clean(t);
	if xpri_clean then
		cell_xpri_clean(t);
	if previs_flag_clear then
		elem_previs_flag_clear(t);

	Result := t;
end;

procedure dmarker_refr_promote(plugin: IwbFile; e: IInterface);
var
	t, r, b: IInterface;
	i: integer;
begin
	t := plugin_cell_copy_safe(plugin, e, true, true, true);
	r := Add(t, 'REFR', true);
	b := Add(r, 'NAME', true);
	SetNativeValue(b, DMarker_FID);

//	AddMessage(FullPath(r));
end;

procedure xmarker_refr_promote(plugin: IwbFile; e: IInterface);
var
	t, r, b: IInterface;
	i: integer;
begin
	t := plugin_cell_copy_safe(plugin, e, true, true, true);
	r := Add(t, 'REFR', true);
	b := Add(r, 'NAME', true);
	SetNativeValue(b, XMarker_FID);

//	AddMessage(FullPath(r));
end;

procedure marker_refr_promote(plugin: IwbFile; e: IInterface);
begin
	if stat_promote_marker_door then begin
		dmarker_refr_promote(plugin, e);
	end else begin
		xmarker_refr_promote(plugin, e);
	end;
end;

procedure stat_refr_promote(plugin: IwbFile; e: IInterface; marker_fallback: boolean);
var
	t, r, m: IInterface;
	i, e_idx, t_idx, oc: integer;
begin
	// Grab the 1st refr in the cell (from the overrides or master) and dupe as an override
	// This is purely to get -generateprevisdata or -generateprecombined to generate data
	// for the cell without actually duplicating the entire plugin being overridden. The
	// reason for this is that the automated commands will only generate data for cells
	// which define a REFR. It is not enough to simply override the CELL itself. Once
	// data is generated these duplicated REFRs are no longer needed and will not be used
	// in the final generated plugin containing both precombine and previs data.
	// If the references were not duplicated then all dependent data would have to be
	// merged back into each plugin before it could be used with -generateprevisdata.

	if marker_fallback and stat_promote_marker_prefer then begin
//		AddMessage('stat_refr_promote: marker_fallback: ' + FullPath(e));
		marker_refr_promote(plugin, e);
		Exit;
	end;

	m := MasterOrSelf(e);
	oc := OverrideCount(m);
	e_idx := GetLoadOrder(GetFile(e));
	for i := Pred(oc) downto -1 do begin
		t := override_or_master(m, i);

//		AddMessage('stat_refr_promote: ' + FullPath(t));
//		AddMessage('stat_refr_promote: ' + FullPath(e));

		// Do not go past the current plugin for this element
		t_idx := GetLoadOrder(GetFile(t));
		if t_idx > e_idx then
			continue;

		r := cell_refr_rvis_first(t, true, true);
//		AddMessage('stat_refr_promote: r: ' + FullPath(r));
		if not Assigned(r) then begin
			continue;
		end else if not Equals(GetFile(t), plugin) then begin
			if Debug then begin
//				AddMessage(Format('%s: Copying: %s', [GetFileName(e), Name(r)]))
			end;

			// Note: e is used as the CELL source rather than t
			// because t is only used to find a STAT ref if e
			// does not have any of its own. The actual CELL data
			// should still come from e in all cases.

			// Guard against xedit corrupting CELL parents (XXX: still valid?)
			plugin_cell_copy_safe(plugin, e, true, true, true);
			form_copy_safe(plugin, r, false, false);
		end;

		Exit;
	end;

	// If no static or otherwise refr found, synthesize one from a
	// known marker.
	if marker_fallback then begin
//		AddMessage('stat_refr_promote: marker_fallback: ' + FullPath(e));
		marker_refr_promote(plugin, e);
	end;
end;

function plugin_cell_find(plugin: IwbFile; e: IInterface): IInterface;
var
	t, m: IInterface;
	i: integer;
begin
	m := MasterOrSelf(e);
	for i := Pred(OverrideCount(m)) downto -1 do begin
		t := override_or_master(m, i);

		if Equals(plugin, GetFile(t)) then begin
			Result := t;
			Exit;
		end;
	end;

	Result := nil;
end;

function form_copy_safe(plugin: IwbFile; e: IInterface; pc_copy, pv_copy: boolean): IInterface;
var
	r, d, t, v: IInterface;
	i, j: integer;
	s: string;
begin
	try
		// XXX: xEdit will choke on delocalized plugins containing strings like '$Farm05Location'
		// XXX: due to it wrongly interpreting it as a hex/integer value and will also disallow copying
		// XXX: an element with busted references. Attempt a normal deepcopy first and if it does not
		// XXX: succeed then attempt an element by element copy whilst avoiding bogus XPRI data.

		r := elem_copy_deep(plugin, e);
	except
		// Deep copy failed, most likely due to bad XPRI data, attempt a per-element copy.
		// The vast majority of the time this branch will only be taken for XPRI data.
		on Ex: Exception do begin
			plugin_elem_remove(plugin, e);

			if Debug then begin
				AddMessage('Failed to deep copy: ' + FullPath(e));
				AddMessage('             reason: ' + Ex.Message);
				AddMessage('Attempting per element copy');
			end;

			try
				elem_masters_add(plugin, e);

				r := wbCopyElementToFile(e, plugin, false, false);
				SetElementNativeValues(r, 'Record Header\Record Flags', GetElementNativeValues(e, 'Record Header\Record Flags'));

				for i := 0 to Pred(ElementCount(e)) do begin
					t := ElementByIndex(e, i);
					if not Assigned(t) then
						continue;

					s := Signature(t);
					if not Assigned(s) then
						continue;

					if not pc_copy then begin
						// If the previous deep copy failed it is extremely likely
						// it was due to these elements and they will be copied
						// from the prior override (see comment below).
						if pc_sig_tab.indexOf(s) >= 0 then
							continue;
					end;

					if not pv_copy then begin
						// If the previous deep copy failed it is extremely likely
						// it was due to these elements and they will be copied
						// from the prior override (see comment below).
						if pv_sig_tab.indexOf(s) >= 0 then
							continue;
					end;

					if not ElementExists(r, s) then
						Add(r, s, true);
					ElementAssign(ElementBySignature(r, s), LowInteger, t, false);
				end;
			except
				on Ex: Exception do begin
					plugin_elem_remove(plugin, e);
					Raise Exception.Create(Ex.Message);
				end;
			end;
		end;
	end;

	try
{
		// Only applies to CELLs, preserved from precombine_split

		// Always defer to the previs data of the preceding override due to a CK bug
		// when >2 masters are used for precombine generation. 99% of the time the most
		// recent overridden refs are the actual refs used and these values will be
		// overwritten by previs generation anyway.
		elem_pv_sync(o, r);

		// Ensure any 'no previs' flags are removed if master also does not have
		elem_previs_flag_clear(r);
}

		// Copy form version info
		elem_version_sync(e, r);
	except
		on Ex: Exception do begin
			plugin_elem_remove(plugin, e);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := r;
end;

function previs_merge(plugin: IwbFile; e, o: IInterface): Boolean;
begin
	if Debug then
		AddMessage(Format('%s: previs_merge: %s', [GetFileName(plugin), Name(e)]));

	try
		elem_masters_add(plugin, e);

		// Copy previs data from current element to plugin
		elem_pv_sync(e, o);

		// Copy form version info
		elem_version_sync(e, o);

		// Ensure any 'no previs' flags are removed if master also does not have
		elem_previs_flag_clear(o);
	except
		on Ex: Exception do begin
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := true;
end;

function precombine_merge(plugin: IwbFile; e, o: IInterface): Boolean;
var
	r, t: IInterface;
begin
	if Debug then
		AddMessage(Format('%s: precombine_merge: %s', [GetFileName(plugin), Name(e)]));

	try
		elem_masters_add(plugin, e);

		// Merge precombine data from current element to overridden plugin
		elem_pc_sync(e, o);

		// Copy form version info
		elem_version_sync(e, o);

		// Ensure any 'no previs' flags are removed if master also does not have
		elem_previs_flag_clear(o);
	except
		on Ex: Exception do begin
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := true;
end;

// Note: this copies to a plugin rather than merging back into the master/override
function previs_extract(plugin: IwbFile; e, o: IInterface): Boolean;
var
	r: IInterface;
begin
	if Debug then
		AddMessage(Format('%s: previs_extract: %s', [GetFileName(plugin), Name(e)]));

	try
		// Copy overridden plugin data as a starting base
		r := form_copy_safe(plugin, o, true, true);

		previs_merge(plugin, e, r);
	except
		on Ex: Exception do begin
			plugin_elem_remove(plugin, r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := true;
end;

// Note: this copies to a plugin rather than merging back into the master/override
function precombine_extract(plugin: IwbFile; e, o: IInterface): Boolean;
var
	r: IInterface;
begin
	if Debug then
		AddMessage(Format('%s: precombine_extract: %s', [GetFileName(plugin), Name(e)]));

	try
		// Copy overridden plugin data as a starting base
		r := form_copy_safe(plugin, o, true, true);

		precombine_merge(plugin, e, r);
	except
		on Ex: Exception do begin
			plugin_elem_remove(plugin, r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := true;
end;

function ts_to_int(ts: string): integer;
begin
	Result := 0;
	if Assigned(ts) and (length(ts) >= 5) then begin
//		AddMessage('ts: ' + ts);
		Result := StrToInt('$' + ts[4] + ts[5] + ts[1] + ts[2]);
//		AddMessage('result: ' + IntToStr(Result));
	end;
end;

function override_timestamp_latest(e: IInterface; s: signature): IInterface;
var
	m, t: IInterface;
	i, oc: integer;
	nv: string;
	ts, ts_max: integer;
	efname, tfname: string;
begin
	Result := nil;

	ts := 0;
	ts_max := 0;
	m := MasterOrSelf(e);
	oc := OverrideCount(m);
	for i := Pred(oc) downto -1 do begin
		t := override_or_master(m, i);

		tfname := GetFileName(t);
		efname := GetFileName(e);

		// For overrides which have mixed timestamps for the same cell
		// attempt to figure out the most recent one. This sometimes
		// happens when generating so-called sharded data for the same
		// plugin when using CKs command line options.
		if ElementExists(t, s) then begin
			nv := GetElementEditValues(t, s);
			ts := ts_to_int(nv);
		end else begin
			ts := 0;
		end;

		if (ts = 0) or (ts > ts_max) then begin
			if ts_max <> 0 then
				AddMessage(Format('%s: Plugin with greater %s: %s (%s > %s)', [ efname, tfname, s, IntToHex(ts, 8), IntToHex(ts_max, 8) ]));
			ts_max := ts;
			Result := t;
		end;
	end;
end;

function group_desc(g: IInterface; s: string): Boolean;
var
	cg, r, t: IInterface;
	i, j: integer;
begin
	AddMessage(FullPath(g));

	for i := 0 to Pred(ElementCount(g)) do begin
		r := ElementByIndex(g, i);
		AddMessage(FullPath(r));

		if Signature(r) = 'CELL' then
			continue;

		cg := ChildGroup(r);
		if Assigned(cg) then begin
			group_desc(cg);
			continue;
		end;

		for j := 0 to Pred(ElementCount(r)) do begin
			t := ElementByIndex(r, j);
			if (not Assigned(s)) or (Signature(t) = s) then
				AddMessage(FullPath(t));
		end;
	end;
end;

function cell_rvis_overlap_list(e: IInterface; parents, children, require_static, nearest_only: boolean): TList;
var
	out, tl, rgl: TList;
	cxy: TwbGridCell;
	t, r, m: IInterface;
	i, j, k, k_min, k_max, e_idx, r_idx, oc: integer;
begin
	rgl := cell_rvis_cell_grid(e);
	if not Assigned(rgl) then begin
		Result := nil;
		Exit;
	end;

	out := TList.create;
	e_idx := GetLoadOrder(GetFile(e));
	for i := 0 to Pred(rgl.count) do begin
		tl := TList(rgl[i]);
		if not Assigned(tl) then
			continue;

		for j := 0 to Pred(tl.count) do begin
			t := ObjectToElement(tl[j]);
			if not Assigned(t) then
				continue;

			m := MasterOrSelf(t);
			oc := OverrideCount(m);

			if children then begin k := -1;
			end else if parents then begin k := Pred(oc);
			end else break;

			while (k >= -1) and (k <= Pred(oc)) do begin
				r := override_or_master(m, k);
				r_idx := GetLoadOrder(GetFile(r));

				if children then begin
					Inc(k);
					if r_idx <= e_idx then continue;
				end else if parents then begin
					Dec(k);
					if r_idx >= e_idx then continue;
				end;

//				cxy := GetGridCell(r);
//				AddMessage(Format('%d,%d %s', [cxy.x,cxy.y,FullPath(r)]));

				if require_static then begin
					// Do not go past the current plugin for this element
					// as that means this plugin (r) is dependent on a cell
					// from plugin (e) within the rvis grid data. This is
					// specifically for masters a plugin would be dependent
					// on as if the load order of the last override is the
					// same as the plugin (e) then it is data within that
					// plugin specifically.
					//
					// Essentially what is going on here is that if an override
					// later in the load order were to generate a vis grid
					// for the same set of cells for a plugin earlier in the
					// load order, then this plugin must be a master for that
					// plugin. Otherwise the later plugin will override the
					// vis data from the earlier one. As a result this loop
					// looks for any cell coming from a plugin later in the load
					// order and if it finds one it prevents removal of this cell.

					if not cell_refr_rvis_check(r) then
						continue;
				end;

				if children then begin
//						AddMessage(Format('%s: cell_rvis_overlap_list: child: %s: %s', [ GetFileName(e), GetFileName(r), Name(r) ]));
				end else if parents then begin
//						AddMessage(Format('%s: cell_rvis_overlap_list: parent: %s: %s', [ GetFileName(e), GetFileName(r), Name(r) ]));
				end;

				out.add(r);

				if nearest_only then break;
			end;
		end;

		// Should not be freed if caching is in use
		if not CacheRvisGridCells then
			tl.free;
	end;

	rgl.free;

	Result := out;
end;

function cell_rvis_overlap_check(e: IInterface; parents, children, require_static: boolean): boolean;
var
	tl: TList;
begin
	Result := false;

	tl := cell_rvis_overlap_list(e, parents, children, require_static);
	if not Assigned(tl) then
		Exit;
	if (tl.count <> 0) then
		Result := true;

	tl.free;
end;

procedure plugin_cell_rvis_master_add(plugin: IwbFile; e: IInterface; require_static, sort: boolean);
var
	rgl, tl: TList;
	m, t, r, rvis: IInterface;
	cxy: TwbGridCell;
	rvx, rvy, i, j, k, e_idx, r_idx: integer;
begin
	// Non-persistent exterior cells only
	if not cell_filter(e, true, true, false, false) then
		Exit;

	rgl := cell_rvis_cell_grid(e);
	if not Assigned(rgl) then
		Exit;

//	AddMessage('plugin_cell_rvis_master_add: e: ' + FullPath(e));

	e_idx := GetLoadOrder(GetFile(e));
	for i := 0 to Pred(rgl.count) do begin
		tl := TList(rgl[i]);
		if not Assigned(tl) then
			continue;

		for j := 0 to Pred(tl.count) do begin
			t := ObjectToElement(tl[j]);
			if not Assigned(t) then
				continue;

			m := MasterOrSelf(t);
			for k := -1 to Pred(OverrideCount(m)) do begin
				r := override_or_master(m, k);

//				AddMessage('plugin_cell_rvis_master_add: r: ' + FullPath(r));

				// Do not go past the current plugin for this element
				r_idx := GetLoadOrder(GetFile(r));
				if r_idx >= e_idx then
					break;
				if HasMaster(plugin, GetFileName(r)) then
					continue;

				if require_static then begin
					// Account for more than just stat objects as previs
					// takes other things into account for physics.
					if not cell_refr_rvis_check(r) then
						continue;
				end;

{
				// XXX: figure out why cell_rvis_overlap_check + stat_refr_promote produces different results
				// XXX: TEMPORARY
				if stat_promote then
					stat_refr_promote(plugin, r, stat_promote_all);
}

				// Check for masters that would be added but are not
				// present in the plugin to indicate what would be
				// added. XXX: Try this with and without STAT only?

				// RVIS cell is always at the head of the list
				rvis := ObjectToElement(tl[0]);
				cxy := GetGridCell(rvis);
				AddMessage(Format('VIS: [%d][%d][%d] %s needs master: %s (rvis: %d,%d :: e: %s :: r: %s)', [i,j,k+1,GetFileName(plugin),GetFileName(r),cxy.x,cxy.y,Name(e),Name(r)]));

				plugin_master_add(plugin, r, true, false, true);

//				AddMessage(Format('[%d][%d][%d] %s', [i,j,k+1,FullPath(r)]));
			end;
		end;

		// Should not be freed if caching is in use
		if not CacheRvisGridCells then
			tl.free;
	end;

	rgl.free;

	if sort then
		SortMasters(plugin);
end;

function cell_stat_check(e: IInterface): boolean;
begin
	Result := cell_refr_rvis_check(e);
end;

function cell_stat_overlap_check(e: IInterface): boolean;
var
	tl: TList;
begin
	Result := false;

	tl := cell_stat_overlap_list(e);
	if not Assigned(tl) then
		Exit;
	if (tl.count <> 0) then
		Result := true;

	tl.free;
end;

function cell_stat_overlap_list(e: IInterface): TList;
var
	out: TList;
	m, t, r: IInterface;
	i, j, oc: integer;
begin
	// Non-persistent cells only
	if not cell_filter(e, true, true, true, false) then begin
		Result := nil;
		Exit;
	end;

	// Find this actual element and consider it the highest override so
	// that additional overrides in the load order are ignored. This is
	// done so that the masters added to the plugin represent masters
	// which have been overridden only from the perspective of the
	// plugin being modified.
	m := MasterOrSelf(e);
	oc := OverrideCount(m);
	out := TList.create;
	for i := Pred(oc) downto -1 do begin
		t := override_or_master(m, i);
		if Equals(e, t) then
			break;
		if not cell_refr_rvis_check(t) then
			continue;

		out.add(t);
	end;

	Result := out;
end;

procedure plugin_cell_stat_master_add(plugin: IwbFile; e: IInterface; require_static, sort: boolean);
var
	m, t, r: IInterface;
	i, j, oc: integer;
begin
	// Non-persistent cells only
	if not cell_filter(e, true, true, true, false) then
		Exit;

	// Find this actual element and consider it the highest override so
	// that additional overrides in the load order are ignored. This is
	// done so that the masters added to the plugin represent masters
	// which have been overridden only from the perspective of the
	// plugin being modified.
	m := MasterOrSelf(e);
	oc := OverrideCount(m);
	for i := -1 to Pred(oc) do begin
		t := override_or_master(m, i);
		if Equals(e, t) then
			break;
		if HasMaster(plugin, GetFileName(t)) then
			continue;

		if require_static then begin
			// If the overridden cell does not have any STAT or SCOL
			// references then it should not be considered a master
			// candidate because it will not affect precombines. Note:
			// this is only checked if the parent cell does not have
			// any statics of its own. If it does then the master
			// will be added regardless to guard against generation
			// of previs data not taking into account the override.
			if not cell_refr_rvis_check(t) then
				continue;
		end;

		plugin_master_add(plugin, t, true, false, true);
	end;

	if sort then
		SortMasters(plugin);
end;

function refr_referenced_by_type(e: IInterface; s: string): boolean;
var
	r: IInterface;
	i: integer;
begin
	for i := 0 to Pred(ReferencedByCount(e)) do begin
		r := ReferencedByIndex(e, i);
//AddMessage('e: ' + FullPath(e));
//AddMessage('r: ' + FullPath(r));
		if Signature(r) = s then begin
			Result := true;
			Exit;
		end;
	end;

	Result := false;
end;

procedure cell_refr_clean(e: IInterface);
var
	cg, b, r, t: IInterface;
	s: string;
	i, j: integer;
	rl: TList;
	flags: cardinal;
begin
	if Signature(e) <> 'CELL' then
		Exit;

	cg := ChildGroup(e);
	if not Assigned(cg) then
		Exit;
//	AddMessage('cg: ' + FullPath(cg));

	rl := TList.create;

	// Prioritize temporary references over persistent ones
	for i := 0 to Pred(ElementCount(cg)) do begin
		r := ElementByIndex(cg, i);
		if not Assigned(r) then
			continue;
//		AddMessage('r: ' + FullPath(r));

		for j := 0 to Pred(ElementCount(r)) do begin
			t := ElementByIndex(r, j);
			if not Assigned(t) then
				continue;
//			AddMessage('t: ' + FullPath(t));

//			s := Signature(t);
//			if (pc_keep_map.indexOf(s) < 0) and (pv_keep_map.indexOf(s) < 0) then
//				continue;

			if elem_deleted_check(t) then begin
				b := BaseRecord(MasterOrSelf(t));
			end else begin
				b := BaseRecord(t);
			end;

//			if not Assigned(b) then
//				continue;
//			AddMessage('b: ' + FullPath(b));

			s := Signature(b);
			if (pc_base_keep_map.indexOf(s) < 0) and (pv_base_keep_map.indexOf(s) < 0) then begin
				flags := GetElementNativeValues(e, 'Record Header\Record Flags');

				// Delete only if record is not referenced and does not have
				// 'initially disabled' or 'visible when distant' flags.
				if ((flags and (F_INIT_DISABLED or F_VISIBLE_DISTANT)) = 0) and not refr_referenced_by_type(t, 'REFR') then
					rl.add(t);
			end;
		end;
	end;

	for i := 0 to Pred(rl.count) do begin
		t := ObjectToElement(rl[i]);
		AddMessage(Format('%s: Removing: %s', [GetFileName(e), Name(t)]));
		RemoveNode(t);

		Inc(refr_clean_cnt);
	end;

	rl.free;
end;

procedure master_clean(e: IInterface; main_allow, other_allow, interior_allow, persistent_allow, cell_check, stat_check, rvis_check, require_static, winning_only, non_winning_only, cell_clean, refr_clean: boolean);
var
	master: IInterface;
	winning, editable: boolean;
begin
	if Signature(e) <> 'CELL' then
		Exit;

	editable := IsEditable(e);
	winning := is_winning_override(e, true);
	master := MasterOrSelf(e);

	if cell_check then begin
		if not cell_filter(e, main_allow, other_allow, interior_allow, persistent_allow) then begin
			if editable and cell_clean then begin
//				AddMessage('master_clean: cell_clean: cell_filter');
				cell_remove(e);
			end;
			Exit;
		end;
	end;

	if stat_check then begin
		if not cell_stat_check(e) then begin
			if editable and cell_clean then begin
//				AddMessage('master_clean: cell_clean: stat_check');
				cell_remove(e);
			end;
			Exit;
		end;
	end;

	if rvis_check then begin
		if not cell_rvis_overlap_check(e, false, true, require_static) then begin
			if editable and cell_clean then begin
//				AddMessage('master_clean: cell_clean: rvis_check');
				cell_remove(e);
			end;
			Exit;
		end;
	end;

	if winning then begin
		if non_winning_only then begin
			// XXX: This really means keep only non-winning overrides,
			// XXX: aka preparing as a master for generation only.
			if editable and cell_clean then begin
//				AddMessage('master_clean: cell_clean: non-winning-only');
//				cell_remove(e);
			end;
			Exit;
		end;
	end else begin
		if winning_only then begin
			// XXX: This really means only *add* winning overrides,
			// XXX: aka preparing for generated esps per plugin.
			if editable and cell_clean then begin
//				AddMessage('master_clean: cell_clean: winning-only');
//				cell_remove(e);
			end;
			Exit;
		end else if promote_winning_only then begin
			e := winning_override(e, true);
		end;
	end;

	// Pre-clean precombined and previs data from cells
	if editable then begin
		if refr_clean then
			cell_refr_clean(e);
		if xcri_clean_master then
			cell_xcri_clean(e);
		if xpri_clean_master then
			cell_xpri_clean(e);
		if previs_flag_clear_master then
			elem_previs_flag_clear(e);
	end;

	if Assigned(plugin_use_list) then begin
		if not plugin_use_list.indexOf(GetFileName(e)) >= 0 then begin
//			AddMessage('exit: plugin_use_list');
			Exit;
		end;
	end;

	if Assigned(plugin_cell_master_exclude_list) then begin
		if plugin_cell_master_exclude_list.indexOf(GetFileName(master)) >= 0 then begin
//			AddMessage('exit: plugin_cell_master_exclude_list');
			Exit;
		end;
	end;

	cell_queue_add(e);
end;

function precombine_previs_merge(e: IInterface): boolean;
var
	o, m, t, r, w, plugin: IInterface;
	ol, ml: TList;
	merge: boolean;
	tfname, efname, efoname: string;
	ts, pcmb_max, visi_max: integer;
	idx, i, j, oc: integer;
begin
	// XXX: verify this is a CELL?

	case process_mode of
	P_MODE_PRECOMBINE_MERGE: begin
		efname := GetFileName(e);
		idx := pos('.precombine', efname);
		if idx = 0 then
			Exit;

		// plugin minus .precombine.*
		efoname := copy(efname, 1, idx - 1);
	end;

	P_MODE_PREVIS_MERGE: begin
		efname := GetFileName(e);
		idx := pos('.previs', efname);
		if idx = 0 then
			Exit;

		// plugin minus .previs.*
		efoname := copy(efname, 1, idx - 1);
	end;

	end;

	// | [0] master | [1] override | [2] *override* | [3] element | ...
	m := MasterOrSelf(e);
	oc := OverrideCount(m);
	ol := TList.create;
	ml := TList.create;

	for i := Pred(oc) downto -1 do begin
		t := override_or_master(m, i);

		tfname := GetFileName(t);
		efname := GetFileName(e);

		// XXX: consider allowing precombine_merge files in previs mode
		// XXX: consider restricting pos check to = 1 (must start with)
		if IsEditable(t) and (tfname <> efname) and (pos(tfname, efname) <> 0) then begin
			// source plugin data was generated for
			ol.add(t);
		end else if (pos('.precombine', tfname) = 0) and (pos('.previs', tfname) = 0) then begin
			// other overriding plugin or master
			ml.add(t);
		end;
	end;

	// No matching overrides found to merge into
	if ol.count = 0 then begin
		// Find plugin which would be the originator of this CELL, based on name
		plugin := plugin_file_resolve_existing(efoname);
		if not Assigned(plugin) then begin
			AddMessage('Unable to resolve plugin for: ' + efoname);
			ml.free;
			ol.free;
			Exit;
		end else if ml.count = 0 then begin
			AddMessage('Unable to resolve parent cell for: ' + FullPath(e));
			ml.free;
			ol.free;
			Exit;
		end;

		// Find the last master instead (note: ml is in reverse order of masters)
		for i := 0 to Pred(ml.count) do begin
			t := ObjectToElement(ml[i]);
			if GetLoadOrder(GetFile(t)) < GetLoadOrder(plugin) then
				break;
		end;

//		if Debug then
//			AddMessage(Format('%s: cloning parent cell: :%s', [ efname, FullPath(t) ]));

		if Assigned(plugin_cell_find(plugin, t)) then begin
			AddMessage('Assertion failed: plugin already contains cell');
			ml.free;
			ol.free;
			Exit;
		end;

		// Copy CELL data from last master into plugin
		t := plugin_cell_copy_safe(plugin, t, false, false, false);
{
		if (process_mode = PRECOMBINE_MERGE) then begin
			t := override_timestamp_latest(e, 'PCMB');
		end else if (process_mode = PREVIS_MERGE) then begin
			t := override_timestamp_latest(e, 'VISI');
		end;
}
		ol.add(t);
	end;

	ml.free;

	// XXX: Clean up the isEditable() stuff (e.g. Fallout4.esm).
	for i := 0 to Pred(ol.count) do begin
		o := ObjectToElement(ol[i]);
		merge := (MergeIntoOverride and IsEditable(o));
{
		if Debug then begin
			if merge then begin
				AddMessage(Format('%s: m == %s, o == %s, oc == %d, merge == %d: %s',
					[GetFileName(e), GetFileName(m), GetFileName(o), oc, 1, Name(e)]));
			end else begin
				AddMessage(Format('%s: m == %s, o == %s, t == %s, oc == %d, merge == %d: %s',
					[GetFileName(e), GetFileName(m), GetFileName(o), oc, 0, Name(e)]));
			end;
		end;
}

		// XXX: clean this up?
		if merge then begin
			plugin := GetFile(o);
		end else begin
			plugin := plugin_output_resolve(o);
		end;

		if not Assigned(plugin) then begin
			ol.free;
			Raise Exception.Create(Format('Unable to find plugin for: plugin: %s, o: %s', [FullPath(plugin),FullPath(o)]));
			Exit;
		end;

		try
			case process_mode of
			P_MODE_PRECOMBINE_MERGE: begin
				precombine_merge(plugin, e, o);
			end;

			P_MODE_PREVIS_MERGE: begin
				previs_merge(plugin, e, o);
			end;

			P_MODE_PRECOMBINE_EXTRACT: begin
				precombine_extract(plugin, e, o);
			end;

			P_MODE_PREVIS_EXTRACT: begin
				previs_extract(plugin, e, o);
			end;

			end;
		except
			on Ex: Exception do begin
				AddMessage('Failed to proc: ' + FullPath(e));
				AddMessage('        reason: ' + Ex.Message);

				ol.free;
				Result := StopOnError;
				Exit;
			end;
		end;
	end;

	ol.free;
end;

function cell_finalize(e: IInterface): boolean;
var
	main_allow, other_allow, interior_allow, persistent_allow: boolean;
begin
	// Non-persistent cells only (ignore and do not modify)
	if not cell_filter(e, true, true, true, false) then
		Exit;

	// direct cleaning calls

	case process_mode of
	// master clean

	P_MODE_MASTER_CLEAN: begin
		main_allow := false;
		other_allow := false;
		interior_allow := false;
		persistent_allow := false;

		case process_area of
		P_AREA_MAIN:
			main_allow := true;
		P_AREA_OTHER:
			other_allow := true;
		P_AREA_INTS:
			interior_allow := true;
		P_AREA_EXTS:
			begin
			main_allow := true;
			other_allow := true;
			end;
		P_AREA_ALL:
			begin
			main_allow := true;
			other_allow := true;
			interior_allow := true;
			end;
		end;

		master_clean(e, main_allow, other_allow, interior_allow, persistent_allow, cell_check, stat_check, rvis_check, require_static, winning_only, non_winning_only, cell_clean, refr_clean);
		Exit;
	end;

	P_MODE_PRECOMBINE_MERGE: begin
		Result := precombine_previs_merge(e);
		Exit;
	end;

	P_MODE_PREVIS_MERGE: begin
		Result := precombine_previs_merge(e);
		Exit;
	end;

	P_MODE_FINAL: begin
		e := winning_override(e, false);

		// XXX: reexamine if this is actually correct
		if is_plugin_base(GetFile(e)) then
			Exit;
		if cell_queue_add(e) then
			AddMessage(Format('%s: %s', [GetFileName(e), Name(e)]));

		Exit;
	end;

	// XXX: this looks old/crufty
	P_MODE_INIT: begin
		Result := plugin_cell_stat_master_add(GetFile(e), e, true, true);
		Exit;
	end;

	// XXX: this looks old/crufty
	P_MODE_STATS: begin
		plugin_cell_stat_master_add(GetFile(e), e, true, true);
		plugin_cell_rvis_master_add(GetFile(e), e, true, true);
		Exit;
	end;

	// XXX: this looks old/crufty
	P_MODE_INIT_ALT: begin
		Result := plugin_init(mode);
		Exit;
	end;

	end;

end;

function plugin_stat_list(plugin: IwbFile): TList;
var
	e, t, g: IInterface;
	i: integer;
	tq: TList;
begin
	// Process STATs to identify plugins overriding STATs
	tq := TList.create;

	g := GroupBySignature(plugin, 'STAT');
	if Assigned(g) then begin
		for i := 0 to Pred(ElementCount(g)) do begin
			e := ElementByIndex(g, i);
//			AddMessage('e: ' + FullPath(e));
			t := winning_override(e, true);
			if not Equals(e, t) then begin
				AddMessage('t: ' + FullPath(t));
			end;
		end;
	end;

	if tq.count = 0 then begin
		tq.free;
		Result := nil;
		Exit;
	end;

	Result := tq;
end;

function plugin_scol_list(plugin: IwbFile): TList;
var
	e, t, g: IInterface;
	i: integer;
	sq: TList;
begin
	// Process SCOLs so that the output plugin can be used as a
	// direct target for SCOL generation.
	sq := TList.create;

	g := GroupBySignature(plugin, 'SCOL');
	if Assigned(g) then begin
		for i := 0 to Pred(ElementCount(g)) do begin
			e := ElementByIndex(g, i);
//			AddMessage('e: ' + FullPath(e));
			t := winning_override(e, true);
			if not Equals(e, t) then begin
				AddMessage('t: ' + FullPath(t));
			end;
		end;
	end;

	if sq.count = 0 then begin
		sq.free;
		Result := nil;
		Exit;
	end;

	Result := sq;
end;

function plugin_wrld_list(plugin: IwbFile): TList;
var
	w, g: IInterface;
	wq: TList;
	i: integer;
begin
	// Pre-process all cells in plugin (cleaning, etc) and add to queue
	wq := TList.create;

	// World groups
	g := GroupBySignature(plugin, 'WRLD');
	if Assigned(g) then begin
		for i := 0 to Pred(ElementCount(g)) do begin
			w := ElementByIndex(g, i);
			if Signature(w) <> 'WRLD' then
				continue;
			wq.add(w);
		end;
	end;

	if wq.count = 0 then begin
		wq.free;
		Result := nil;
		Exit;
	end;

	Result := wq;
end;

function plugin_cell_list(plugin: IwbFile): TList;
var
	e, t, r, w, g, cg: IInterface;
	i, j, k, l: integer;
	cq: TList;
begin
	// Pre-process all cells in plugin (cleaning, etc) and add to queue
	cq := TList.create;

	// Interior cells
	g := GroupBySignature(plugin, 'CELL');
	if Assigned(g) then begin
		for i := 0 to Pred(ElementCount(g)) do begin
			e := ElementByIndex(g, i);
//			AddMessage('e: ' + Name(e));
			for j := 0 to Pred(ElementCount(e)) do begin
				t := ElementByIndex(e, j);
//				AddMessage('t: ' + Name(t));
				for k := 0 to Pred(ElementCount(t)) do begin
					r := ElementByIndex(t, k);
					if Signature(r) <> 'CELL' then
						continue;
//					AddMessage('r: ' + Name(r));
					cq.add(r);
				end;
			end;
		end;
	end;

	// Exterior cells
	g := GroupBySignature(plugin, 'WRLD');
	if Assigned(g) then begin
		for i := 0 to Pred(ElementCount(g)) do begin
			w := ElementByIndex(g, i);
			if Signature(w) <> 'WRLD' then
				continue;

			cg := ChildGroup(w);
//			AddMessage('w: ' + FullPath(w));
//			AddMessage('cg: ' + FullPath(cg));

			for j := 0 to Pred(ElementCount(cg)) do begin
				e := ElementByIndex(cg, j);
//				AddMessage('e: ' + FullPath(e));

				// Persistent cells
				if Signature(e) = 'CELL' then begin
					cq.add(e);
					continue;
				end else if Signature(e) = 'GRUP' then begin
					if GroupType(e) < 2 then
						continue;
					if GroupType(e) > 5 then
						continue;
				end;

				for k := 0 to Pred(ElementCount(e)) do begin
					t := ElementByIndex(e, k);
//					AddMessage('t: ' + FullPath(t));

					for l := 0 to Pred(ElementCount(t)) do begin
						r := ElementByIndex(t, l);
						if Signature(r) <> 'CELL' then
							continue;

//						AddMessage('r: ' + FullPath(r));
						cq.add(r);

						// Add to cell cache for later use by
						// cell_resolve. Note: only the original
						// source of the CELL is what is being cached
						// as that is what cell_resolve returns in
						// a deterministic fashion. Normally cache
						// modification only happens within a function
						// using that cache, but this is already doing
						// the vast majority of the work of cell_resolve.
						if CacheCells then
							cell_cache_add(MasterOrSelf(r));
					end;
				end;
			end;
		end;
	end;

	if cq.count = 0 then begin
		cq.free;
		Result := nil;
		Exit;
	end;

	Result := cq;
end;

procedure plugin_finalize(plugin: IwbFile);
var
	e, t, r, w, g, cg: IInterface;
	i, j, k: integer;
	ws, fname: string;
	cq, sq, tq, wq: TList;
	main_allow, interior_allow, other_allow, is_main: boolean;
	editable: boolean;
begin
	fname := GetFileName(GetFile(plugin));
	editable := IsEditable(plugin);

	case process_mode of
	P_MODE_MASTER_CLEAN: begin
		if is_plugin_generated(plugin) then begin
			Exit;
		end else if is_plugin_excluded(plugin) then begin
			Exit;
		end else if not is_plugin_included(plugin) then begin
			Exit;
		end else if is_plugin_base(plugin) then begin
			if not plugin_base_process then
				Exit;
			if plugin_base_esm then
				plugin_esm_set(plugin, true);
		end;

		// Remove RFGPs
		if rfgp_clean then begin
			if editable then begin
				g := GroupBySignature(plugin, 'RFGP');
				if Assigned(g) then begin
					AddMessage(Format('%s: Removing: %s', [fname, Name(g)]));
					RemoveNode(g);
				end;
			end;
		end;
	end;

	P_MODE_PRECOMBINE_MERGE: begin
		if pos('.precombine', fname) = 0 then
			Exit;
	end;

	P_MODE_PREVIS_MERGE: begin
		if pos('.previs', fname) = 0 then
			Exit;
	end;

	end;

{
	tq := plugin_stat_list(plugin);
	sq := plugin_scol_list(plugin);
}

{
	case process_area of
	P_AREA_MAIN:
		begin
		main_allow := true;
		interior_allow := false;
		other_allow := false;
		end;
	P_AREA_OTHER:
		begin
		main_allow := false;
		interior_allow := false;
		other_allow := true;
		end;
	P_AREA_INTS:
		begin
		main_allow := false;
		interior_allow := true;
		other_allow := false;
		end;
	P_AREA_EXTS:
		begin
		main_allow := true;
		interior_allow := false;
		other_allow := true;
		end;
	P_AREA_ALL:
		begin
		main_allow := true;
		other_allow := true;
		interior_allow := true;
		end;
	end;

	wq := plugin_wrld_list(plugin);
	if Assigned(wq) then begin
		if (not main_allow) and (not other_allow) then begin
			g := GroupBySignature(plugin, 'WRLD');
			if Assigned(g) then
				RemoveNode(g);
		end else if (not main_allow) or (not other_allow) then begin
			for i := 0 to Pred(wq.count) do begin
				w := ObjectToElement(wq[i]);
				ws := cell_world_edid(w);
				is_main := (ws = 'Commonwealth');
				if is_main and not main_allow then begin
					RemoveNode(w);
				end else if not is_main and not other_allow then begin
					RemoveNode(w);
				end;
			end;
		end;

		wq.free;
	end;

	if not interior_allow then begin
		g := GroupBySignature(plugin, 'CELL');
		if Assigned(g) then
			RemoveNode(g);
	end;
}

	cq := plugin_cell_list(plugin);
	if not Assigned(cq) then
		Exit;

	AddMessage(Format('%s: Processing %d cells', [ fname, cq.count ]));
	for i := 0 to Pred(cq.count) do begin
		e := ObjectToElement(cq[i]);

		if process_mode = P_MODE_FORMID_DUMP then begin
			ws := cell_world_edid(e);
			AddMessage(Format('formid | %s | %s | %s | %s | %s | %s | %s', [ GetFileName(e), IntToHex(formid(e), 8), IntToHex(fixedformid(e), 8), IntToHex(GetLoadOrderFormID(e), 8), ws, Name(e), FullPath(e) ]));
			continue;
		end;

		cell_finalize(e);

		if ((i + 1 = cq.count) or ((i + 1) mod (trunc(cq.count / 10) + 1) = 0)) then
			AddMessage(Format('%s: Remain: %d cells (%d/%d)', [ fname, cq.count - (i + 1), i + 1, cq.count ]));
	end;

	cq.free;

end;

procedure plugin_output(plugin: IwbFile; tl: TList);
var
	t, r, plugin_out: IInterface;
	i, j: integer;
	fname, fname_out: string;
	sort: boolean;
begin
	fname := GetFileName(plugin);
	sort := (not MasterForceQueue);

	case process_mode of

	P_MODE_FINAL: begin
		if not plugin_output_cell_use then begin
			plugin_out := plugin_output_resolve(plugin);
			if not Assigned(plugin_out) then
				Exit;
			fname_out := GetFileName(plugin_out);

			AddMessage(Format('%s: Adding cell masters for %d cells into %s', [ fname, tl.count, fname_out ]));
		end else begin
			AddMessage(Format('%s: Adding cell masters for %d cells', [ fname, tl.count ]));
		end;

		// XXX: Add masters before copying due to an xedit issue
		// XXX: with formid corruption when intermixed.
		for i := 0 to Pred(tl.count) do begin
			t := ObjectToElement(tl[i]);
			if not Assigned(t) then
				continue;

			if plugin_output_cell_use then begin
				plugin_out := plugin_output_resolve(t);
				if not Assigned(plugin_out) then
					continue;
			end;

			plugin_master_add(plugin_out, t, true, sort, true);

			if ((i + 1 = tl.count) or ((i + 1) mod (trunc(tl.count / 10) + 1) = 0)) then
				AddMessage(Format('Remain: %d cells (%d/%d)', [ tl.count - (i + 1), i + 1, tl.count ]));
		end;

		if not plugin_output_cell_use then begin
			AddMessage(Format('%s: Copying %d cells into %s', [ fname, tl.count, fname_out ]));
		end else begin
			AddMessage(Format('%s: Copying %d cells', [ fname, tl.count ]));
		end;

		for i := 0 to Pred(tl.count) do begin
			t := ObjectToElement(tl[i]);
			if not Assigned(t) then
				continue;

			if plugin_output_cell_use then begin
				plugin_out := plugin_output_resolve(t);
				if not Assigned(plugin_out) then
					continue;
			end;

			plugin_cell_copy_safe(plugin_out, t, false, false, false);

			if ((i + 1 = tl.count) or ((i + 1) mod (trunc(tl.count / 10) + 1) = 0)) then
				AddMessage(Format('Remain: %d cells (%d/%d)', [ tl.count - (i + 1), i + 1, tl.count ]));
		end;

		Exit;
	end;

	P_MODE_MASTER_CLEAN: begin
		// Force masters on source plugin?
		if MasterForcePlugin then
			plugin_master_force(plugin);

		if not plugin_output_cell_use then begin
			plugin_out := plugin_output_resolve(plugin);
			if not Assigned(plugin_out) then
				Exit;
			fname_out := GetFileName(plugin_out);

			AddMessage(Format('%s: Adding cell masters for %d cells into %s', [ fname, tl.count, fname_out ]));
		end else begin
			AddMessage(Format('%s: Adding cell masters for %d cells', [ fname, tl.count ]));
		end;

		for i := 0 to Pred(tl.count) do begin
			t := ObjectToElement(tl[i]);
			if not Assigned(t) then
				continue;

//			if Debug then AddMessage(Format('tl[%d]: %s', [i,FullPath(t)]));

			if plugin_output_cell_use then begin
				plugin_out := plugin_output_resolve(t);
				if not Assigned(plugin_out) then
					continue;
			end;

			// if this cell has STAT refrs, promote them to the output
			// plugin so they will be generated by CK.
			if stat_promote then begin
				stat_refr_promote(plugin_out, t, stat_promote_all);
				plugin_master_add(plugin_out, t, true, sort, true);
			end;

			// check for stat or rvis involved cells before this plugin
			if not is_root_plugin(t) then begin
{
				// XXX: experimental section to add RVIS related cells as stat promote
//				AddMessage(Format('t: %s', [FullPath(t)]));
				tl := cell_rvis_overlap_list(t, true, false, true, true);

				for j := 0 to Pred(tl.count) do begin
					r := ObjectToElement(tl[j]);
					if not Assigned(r) then
						continue;
//					AddMessage(Format('r: %s', [FullPath(r)]));
					stat_refr_promote(plugin_out, r, stat_promote_all);
					plugin_master_add(plugin_out, r, true, sort, true);
					end;
				end;

				tl.free;

				continue;
}

				// if this cell has STAT refrs in earlier plugins before this one,
				// add those plugins as masters to the output plugin
				if stat_master_add then begin
					plugin_cell_stat_master_add(plugin_out, t, true, sort);
				end;

				// if earlier plugins for this cell have STAT refrs that would overlap
				// the RVIS grid, add those plugins as masters to the output plugin
				if rvis_master_add then begin
					plugin_cell_rvis_master_add(plugin_out, t, true, sort);
				end;
			end;

			if ((i + 1 = tl.count) or ((i + 1) mod (trunc(tl.count / 10) + 1) = 0)) then
				AddMessage(Format('%s: Remain: %d cells (%d/%d)', [ fname, tl.count - (i + 1), i + 1, tl.count ]));
		end;
	end;

	end;
end;

function Finalize: integer;
var
	tl: TList;
	t, r, plugin: IInterface;
	i, j: integer;
	fname: string;
begin
	for i := 0 to Pred(FileCount) do begin
		plugin := FileByLoadOrder(i);
		if not Assigned(plugin) then
			continue;

		plugin_finalize(plugin);
	end;

	for i := 0 to Pred(FileCount) do begin
		plugin := FileByLoadOrder(i);
		if not Assigned(plugin) then
			continue;

		tl := TList(cell_queue[i]);
		if not Assigned(tl) then
			continue;

		plugin_output(plugin, tl);
	end;

	if MasterForceQueue then
		plugin_master_force_queue_proc;

	// XXX: only relevant during master_clean mode
	AddMessage(Format('Removed %d cells', [ cell_clean_cnt ]));
	AddMessage(Format('Removed %d refs', [ refr_clean_cnt ]));

	if Profile then begin
		AddMessage(Format('cell_rvis_grid_cache (hits/misses): %d/%d', [ cell_rvis_grid_cache_hits, cell_rvis_grid_cache_misses ]));
		AddMessage(Format('cell_rvis_cache (hits/misses): %d/%d', [ cell_rvis_cache_hits, cell_rvis_cache_misses ]));
		AddMessage(Format('cell_cache (hits/misses): %d/%d', [ cell_cache_hits, cell_cache_misses ]));
	end;

	if CacheRvisGridCells then begin
		for i := 0 to Pred(cell_rvis_grid_cache.count) do begin
			tl := TList(cell_rvis_grid_cache.Objects[i]);
			if not Assigned(tl) then
				continue;
			tl.free;
		end;
	end;

	cell_rvis_grid_cache.free;
	cell_rvis_cache.free;

	for i := 0 to Pred(cell_queue.count) do begin
		tl := TList(cell_queue[i]);

		// cell_queue is sparse
		if Assigned(tl) then
			tl.free;
	end;

	cell_queue.free;

	cell_queue_seen.free;
	cell_cache.free;

	pc_keep_map.free;
	pc_base_keep_map.free;

	pv_keep_map.free;
	pv_base_keep_map.free;

	plugin_file_map.free;

	plugin_master_base_list.free;
	plugin_master_exclude_list.free;

	plugin_master_force_queue.free;
	plugin_master_force_seen.free;
	plugin_master_force_list.free;

	plugin_output_cell_list.free;
	plugin_output_each_list.free;
	plugin_output_combined_list.free;
	plugin_output_list.free;

	if Assigned(plugin_exclude_list) then
		plugin_exclude_list.free;
	if Assigned(plugin_include_list) then
		plugin_include_list.free;
	if Assigned(plugin_use_list) then
		plugin_use_list.free;
	if Assigned(plugin_generated_list) then
		plugin_generated_list.free;
	if Assigned(plugin_cell_master_exclude_list) then
		plugin_cell_master_exclude_list.free;

	if plugin_output_log_use and Assigned(plugin_output_log) then
		plugin_output_log_list.savetofile(plugin_output_log);
	plugin_output_log_list.free;

//	frmMain.Close;

end;

end.

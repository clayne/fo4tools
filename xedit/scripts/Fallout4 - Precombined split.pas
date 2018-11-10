{
	1. Split precombines into separate plugins based on their master.
	2. Recombine precombine/previs of loaded plugins into a final plugin.

	Hotkey: Ctrl+Shift+P
}

unit FO4_Precombined_Split;
const
	Debug = true;
//	Debug = false;
	StopOnError = true;
	MergeIntoOverride = true;
	PerElementMasters = true;
	InitFileSuffix = 'pcv';
	PrecombineFileBase = 'precombine';
	PrecombineFileSuffix = 'precombine_split';
	PrevisFileBase = 'previs';
	PrevisFileSuffix = 'previs_split';
	FinalFileBase = 'pcv-final2';
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
var
	process_mode: string;
	plugin_combined_use, plugin_each_use, plugin_cell_use, stat_promote: boolean;
	cell_remove_cnt, ref_remove_cnt: integer;

	pc_sig_tab: array [0..1] of TString;
	pv_sig_tab: array [0..2] of TString;
	pc_keep_map: THashedStringList;
	pv_keep_map: THashedStringList;

	rvis_cell_cache: THashedStringList;
	rvis_cell_grid_cache: THashedStringList;

	cell_cache: THashedStringList;
	cell_queue: Tlist;

	plugin_ignore_list: TStringList;

	plugin_file_map: THashedStringList;
	plugin_master_queue: THashedStringList;

	base_master_list: THashedStringList;

	master_force: TStringList;
	master_force_seen: THashedStringList;

function Initialize: integer;
var
	i: integer;
begin
//	process_mode := 'init_master_refr_clean';
//	process_mode := 'init_master_cell_rvis_clean';

//	process_mode := 'init_cell_all_master_clean';
//	process_mode := 'init_cell_exts_master_clean';
//	process_mode := 'init_cell_main_master_clean';
//	process_mode := 'init_cell_ints_master_clean';
//	process_mode := 'init_cell_other_master_clean';

//	process_mode := 'init_cell_all_master_add';
//	process_mode := 'init_cell_exts_master_add';
//	process_mode := 'init_cell_main_master_add';
//	process_mode := 'init_cell_ints_master_add';
//	process_mode := 'init_cell_other_master_add';

//	process_mode := 'precombine_merge';
	process_mode := 'previs_merge';
//	process_mode := 'precombine_extract';
//	process_mode := 'previs_extract';
//	process_mode := 'precombine_split';
//	process_mode := 'previs_split';

//	process_mode := 'final_all';
//	process_mode := 'final_exts';
//	process_mode := 'final_main';
//	process_mode := 'final_ints';
//	process_mode := 'final_other';

//	process_mode := 'final';
//	process_mode := 'stats';

	plugin_combined_use := false;
	plugin_each_use := false;
	plugin_cell_use := false;
	stat_promote := true;

	base_master_list := THashedStringList.create;
	base_master_list.sorted := true;
	base_master_list.duplicates := dupIgnore;
	base_master_list.add('Fallout4.esm');
	base_master_list.add('DLCRobot.esm');
	base_master_list.add('DLCworkshop01.esm');
	base_master_list.add('DLCCoast.esm');
	base_master_list.add('DLCworkshop02.esm');
	base_master_list.add('DLCworkshop03.esm');
	base_master_list.add('DLCNukaWorld.esm');
	base_master_list.add('DLCUltraHighResolution.esm');

	master_force := TStringList.create;
	master_force.sorted := false;
	master_force.duplicates := dupIgnore;
	master_force.add('Fallout4.esm');
	master_force.add('DLCRobot.esm');
	master_force.add('DLCworkshop01.esm');
	master_force.add('DLCCoast.esm');
	master_force.add('DLCworkshop02.esm');
	master_force.add('DLCworkshop03.esm');
	master_force.add('DLCNukaWorld.esm');
	master_force.add('DLCUltraHighResolution.esm');
	master_force.add('Unofficial Fallout 4 Patch.esp');
	master_force.add('ReGrowth Overhaul 10.esp');
	master_force.add('rgo_tree_noocclude.esp');
	master_force.add('pcv-final.ints.esp');
	master_force.add('pcv-final.main.esp');
	master_force.add('pcv-final.other.esp');

	master_force_seen := THashedStringList.create;
	master_force_seen.sorted := true;
	master_force_seen.duplicates := dupIgnore;

	// Precombine specific signatures
	pc_sig_tab[0] := 'XCRI';
	pc_sig_tab[1] := 'PCMB';

	// Previs specific signatures
	pv_sig_tab[0] := 'XPRI';
	pv_sig_tab[1] := 'RVIS';
	pv_sig_tab[2] := 'VISI';

	pc_keep_map := THashedStringList.create;
	pc_keep_map.Sorted := true;
//	pc_keep_map.add('CELL');
//	pc_keep_map.add('LAND');
//	pc_keep_map.add('LAYR');
//	pc_keep_map.add('RFGP');
//	pc_keep_map.add('MSWP');
//	pc_keep_map.add('NAVM');
	pc_keep_map.add('REFR');
	pc_keep_map.add('SCOL');
	pc_keep_map.add('STAT');
//	pc_keep_map.add('TES4');
//	pc_keep_map.add('WRLD');

	pv_keep_map := THashedStringList.create;
	pv_keep_map.Sorted := true;
	pv_keep_map.add('ACTI');
	pv_keep_map.add('CONT');
	pv_keep_map.add('FLOR');
	pv_keep_map.add('FURN');
	pv_keep_map.add('HAZD');
	pv_keep_map.add('MSTT');
	pv_keep_map.add('PHZD');
	pv_keep_map.add('PMIS');
	pv_keep_map.add('PROJ');
	pv_keep_map.add('SCOL');
	pv_keep_map.add('STAT');
	pv_keep_map.add('TACT');
	pv_keep_map.add('TERM');

	rvis_cell_cache := THashedStringList.create;
	rvis_cell_cache.Sorted := true;
	rvis_cell_cache.Duplicates := dupIgnore;

	rvis_cell_grid_cache := THashedStringList.create;
	rvis_cell_grid_cache.Sorted := true;
	rvis_cell_grid_cache.Duplicates := dupIgnore;

	cell_cache := THashedStringList.create;
	cell_cache.Sorted := true;
	cell_cache.Duplicates := dupIgnore;

	cell_queue := TList.create;

	plugin_ignore_list := TStringList.create;
	plugin_ignore_list.sorted := true;
	plugin_ignore_list.duplicates := dupIgnore;
	plugin_ignore_list.add(InitFileSuffix);
	plugin_ignore_list.add(PrecombineFileBase);
	plugin_ignore_list.add(PrecombineFileSuffix);
	plugin_ignore_list.add(PrevisFileBase);
	plugin_ignore_list.add(PrevisFileSuffix);
	plugin_ignore_list.add(FinalFileBase);

	plugin_file_map := THashedStringList.create;
	plugin_file_map.sorted := true;
	plugin_file_map.duplicates := dupIgnore;

	plugin_master_queue := THashedStringList.create;
	plugin_master_queue.sorted := false;
	plugin_master_queue.duplicates := dupIgnore;

	for i := 0 to Pred(ParamCount) do begin
		AddMessage(Format('param[%d] == %s', [ i, ParamStr(i) ]));
	end;

	cell_remove_cnt := 0;
	ref_remove_cnt := 0;
end;

function winning_override(e: IInterface; ignore_generated: boolean): IInterface;
var
	t, m: IInterface;
	fstr: string;
	i, oc: integer;
	ignore: boolean;
begin
	if not ignore_generated then begin
		Result := WinningOverride(e);
		Exit;
	end;

	m := MasterOrSelf(e);
	oc := OverrideCount(m);
	for i := Pred(oc) downto -1 do begin
		if i < 0 then begin
			t := m;
		end else begin
			t := OverrideByIndex(m, i);
		end;

		ignore := false;
		fstr := GetFileName(t);
		for j := 0 to Pred(plugin_ignore_list.count) do begin
			if (Pos(plugin_ignore_list[j], fstr) <> 0) then begin
				ignore := true;
				break;
			end;
		end;

		if not ignore then begin
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

procedure plugin_master_add(plugin: IwbFile; e: IInterface; parents, sort: boolean);
var
	efile, mfile: IwbFile;
	efstr, pfstr: string;
	i: integer;
	mq, sl: THashedStringList;
	tl: TList;
begin
	mq := TStringList.create;
	sl := THashedStringList.create;
	tl := TList.create;

	pfstr := GetFileName(plugin);

	tl.add(GetFile(e));
	while tl.count <> 0 do begin
		efile := ObjectToElement(tl[0]);
		tl.delete(0);

		efstr := GetFileName(efile);
		if not sl.indexOf(efstr) < 0 then
			continue;
		sl.add(efstr);

		if parents then begin
			// Add masters of the master being added otherwise
			// CK will emit these after all plugins have been
			// loaded and totally screw up the formid indexes.
			for i := 0 to Pred(MasterCount(efile)) do begin
				mfile := MasterByIndex(efile, i);
				tl.add(mfile);
			end;
		end;

//		if Debug then AddMessage(Format('%s: Adding master: %s: %s', [GetFileName(plugin), efstr, Name(e)]));
		if (efstr <> pfstr) and not HasMaster(plugin, efstr) then begin
			if Debug then AddMessage(Format('%s: Adding master: %s: %s', [GetFileName(plugin), efstr, Name(e)]));
			mq.add(efstr);
//			AddMasterIfMissing(plugin, efstr, false);
		end;
	end;

	if (mq.count <> 0) then
		AddMasters(plugin, mq);
	if sort then
		SortMasters(plugin);

	tl.free;
	sl.free;
	mq.free;
end;

procedure plugin_master_force(plugin: IwbFile; parents, sort: boolean);
var
	m: IInterface;
	i: integer;
	pfstr: string;
begin
	pfstr := GetFileName(plugin);
	if not base_master_list.indexOf(pfstr) < 0 then
		Exit;
	if not master_force.indexOf(pfstr) < 0 then
		Exit;
	if not master_force_seen.indexOf(pfstr) < 0 then
		Exit;
	master_force_seen.add(pfstr);

	for i := 0 to Pred(master_force.count) do begin
		m := plugin_file_resolve_existing(master_force[i]);
		plugin_master_add(plugin, m, parents, false);
	end;

	if sort then
		SortMasters(plugin);
end;

function plugin_file_resolve_existing(pfile: TString): IInterface;
var
	t: IInterface;
	i, idx: integer;
begin
	// Attempt to find already created plugin in loaded files
	idx := plugin_file_map.indexOf(pfile);
	if not idx < 0 then begin
		Result := ObjectToElement(plugin_file_map.Objects[idx]);
		Exit;
	end;

	for i := Pred(FileCount) downto 0 do begin
		t := FileByIndex(i);
		if GetFileName(t) = pfile then begin
			Result := t;
			plugin_file_map.addObject(pfile, t);
			Exit;
		end;
	end;

	Result := nil; Exit;
end;

function plugin_file_resolve_existing_idx(pfile: TString): integer;
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

function plugin_file_resolve(ofstr, mode, area: string; idx: integer): IInterface;
var
	plugin, m: IInterface;
	b, s, pfile: TString;
	i: integer;
begin
	// Attempt to locate existing plugin for the same file or create a new one
	for i := Pred(idx) to Pred(idx + MaxFileAttempts) do begin
		if mode = 'init' then begin
			b := ofstr;
			s := InitFileSuffix;
		end else if mode = 'precombine_split' then begin
			b := ofstr;
			s := PrecombineFileSuffix;
		end else if mode = 'previs_split' then begin
			b := ofstr;
			s := PrevisFileSuffix;
		end else if mode = 'final' then begin
			b := FinalFileBase;
			s := ofstr;
		end else begin
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

function plugin_resolve(e: IInterface): IwbFile;
var
	m: IInterface;
	i: integer;
	idx: integer;
	mode: string;
	ofstr: string;
	area: string;
begin
	if not (plugin_combined_use or plugin_each_use) then begin
		Result := GetFile(e);
		Exit;
	end;

	if process_mode = 'init_cell_all_master_clean' then begin
		mode := 'init'; area := 'all'; idx := 0;
	end else if process_mode = 'init_cell_exts_master_clean' then begin
		mode := 'init'; area := 'exts'; idx := 0;
	end else if process_mode = 'init_cell_ints_master_clean' then begin
		mode := 'init'; area := 'ints'; idx := 0;
	end else if process_mode = 'init_cell_main_master_clean' then begin
		mode := 'init'; area := 'main'; idx := 0;
	end else if process_mode = 'init_cell_other_master_clean' then begin
		mode := 'init'; area := 'other'; idx := 0;
	end else if process_mode = 'final_all' then begin
		mode := 'final'; area := 'all'; idx := 0;
	end else if process_mode = 'final_exts' then begin
		mode := 'final'; area := 'exts'; idx := 0;
	end else if process_mode = 'final_ints' then begin
		mode := 'final'; area := 'ints'; idx := 0;
	end else if process_mode = 'final_main' then begin
		mode := 'final'; area := 'main'; idx := 0;
	end else if process_mode = 'final_other' then begin
		mode := 'final'; area := 'other'; idx := 0;
	end;

	if plugin_combined_use then begin
		ofstr := area;
	end else if plugin_each_use then begin
		ofstr := GetFileName(e);
		if plugin_cell_use then begin
			ofstr := ofstr + '.' + IntToHex(FormID(e), 8);
		end;
	end;

	Result := plugin_file_resolve(ofstr, mode, area, idx);
end;

procedure plugin_elem_remove(plugin: IwbFile; e: IInterface);
var
	t: IInterface;
	i: integer;
begin
	for i := -1 to Pred(OverrideCount(e)) do begin
		if i < 0 then begin
			t := Master(e);
		end else begin
			t := OverrideByIndex(e, i);
		end;

		if GetFileName(t) <> GetFileName(plugin) then
			continue;

		Remove(t);
		Exit;
	end;
end;

function elem_copy_deep(plugin: IwbFile; e: IInterface): IInterface;
begin
	if PerElementMasters then
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
	r: IInterface;
	sl: TStringList;
	rfstr: string;
	i, j: integer;
begin
	sl := TStringList.create;
	sl.Sorted := true;
	sl.Duplicates := dupIgnore;

	ReportRequiredMasters(e, sl, false, true);
	for i := 0 to Pred(sl.Count) do begin
		if sl[i] = GetFilename(plugin) then
			continue;

		tfile := plugin_file_resolve_existing(sl[i]);
		plugin_master_add(plugin, tfile, true, true);
	end;

	sl.free;
end;

procedure elem_previs_flag_clean(e, m: IInterface);
var
	flags, mflags: cardinal;
begin
	flags := GetElementNativeValues(e, 'Record Header\Record Flags');
	mflags := GetElementNativeValues(m, 'Record Header\Record Flags');

	// If record has 'no previs' set but master does not, remove it
	if ((flags and F_NOPREVIS) <> 0) and ((mflags and F_NOPREVIS) = 0) then begin
		AddMessage('Warning: disabling explicitly set "no previs" flag: ' + FullPath(e));
		SetElementNativeValues(e, 'Record Header\Record Flags', flags - F_NOPREVIS);
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

procedure elem_sync(e, r: IInterface; s: TString);
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

function cell_cache_key(world_str: string; x, y: integer): string;
begin
	Result := Format('%s,%d,%d', [ world_str, x, y ]);
end;

procedure cell_remove(e: IInterface);
var
	cxy: TwbGridCell;
	key, s: string;
	idx: integer;
begin
	// XXX: Error check this
	s := cell_world_edid(e);
	cxy := GetGridCell(e);
	key := cell_cache_key(s, cxy.x, cxy.y);
	idx := cell_cache.indexOf(key);
	if not idx < 0 then
		cell_cache.delete(idx);
	idx := cell_queue.indexOf(e);
	if not idx < 0 then
		cell_queue.delete(idx);

	AddMessage(Format('%s: Removing: %s', [GetFileName(e), Name(e)]));
	RemoveNode(e);

	Inc(cell_remove_cnt);
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

function cell_refr_stat_all(e: IInterface; ref_check, cell_check: boolean): IInterface;
var
	cg, rcg, r, t, b: IInterface;
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

//		AddMessage('r: ' + FullPath(r));

		for j := 0 to Pred(ElementCount(r)) do begin
			t := ElementByIndex(r, j);
			s := Signature(t);

			if (s <> 'REFR') and pc_keep_map.indexof(s) < 0 then
				continue;

			// deleted references should be considered matching
			if elem_deleted_check(t) then
				t := MasterOrSelf(t);

			b := BaseRecord(t);
			s := Signature(b);
			if pc_keep_map.indexof(s) < 0 then
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

function cell_refr_ent_filter(e: IInterface; filter: THashedStringList; error_check, cell_check, precombined_only: boolean): IInterface;
var
	t, b: IInterface;
	i: integer;
	s: string;
begin
	for i := 0 to Pred(ElementCount(e)) do begin
		t := ElementByIndex(e, i);
		s := Signature(t);

		if (s <> 'REFR') and (filter.indexof(s) < 0) then
			continue;

		// deleted references should be considered matching
		if elem_deleted_check(t) then
			t := MasterOrSelf(t);

		b := BaseRecord(t);
		s := Signature(b);
		if (filter.indexof(s) < 0) then
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

function cell_navm_ent_filter(e: IInterface; error_check, cell_check: boolean): IInterface;
var
	t, b: IInterface;
	i: integer;
	s: string;
begin
	for i := 0 to Pred(ElementCount(e)) do begin
		t := ElementByIndex(e, i);
		s := Signature(t);

		if (s <> 'NAVM') then
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

function cell_refr_rvis_first(e: IInterface; error_check, cell_check: boolean): IInterface;
var
	cg, rcg, r, t, b: IInterface;
	i, j, k: integer;
	s: string;
	children: array[0..1] of IInterface;
	filter: THashedStringList;
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
			0: begin filter := pc_keep_map; precombined_only :=  true; end;
			1: begin filter := pc_keep_map; precombined_only := false; end;
			2: begin filter := pv_keep_map; precombined_only := false; end;
			end;

			t := cell_refr_ent_filter(r, filter, error_check, cell_check, precombined_only);
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
	cg, rcg, r, t, b: IInterface;
	i, j: integer;
	s: string;
	children: array[0..1] of IInterface;
	filter: THashedStringList;
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
			0: begin filter := pc_keep_map; precombined_only :=  true; end;
			1: begin filter := pc_keep_map; precombined_only := false; end;
			end;

			t := cell_refr_ent_filter(r, filter, error_check, cell_check, precombined_only);
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
	cg, rcg, r, t, b: IInterface;
	i, j, k: integer;
	s: string;
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
	s: string;
begin
	// Note: Psuedo-record 'Worldspace' is only present in exterior cells
	t := ElementByPath(e, 'Worldspace');
	if not Assigned(t) then
		Exit;

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
	plugin, wg, bg, sg, w, c, t: IInterface;
	cxy: TwbGridCell;
	idx, i, j: integer;
	bx, by, sbx, sby: integer;
	key: string;
begin
	// Check cell cache first and return early if found
	key := cell_cache_key(world_str, x, y);
	idx := cell_cache.indexOf(key);
	if not idx < 0 then begin
		t := ObjectToElement(cell_cache.Objects[idx]);
		Result := t;
		Exit;
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

		c := nil; for j := 0 to Pred(ElementCount(sg)) do begin
			// Cells
			t := ElementByIndex(sg, j);

			// Ignore GRUPs (children of cells)
			if Signature(t) <> 'CELL' then continue;

			// Get coordinates of cell and cache it
			cxy := GetGridCell(t);
			key := cell_cache_key(world_str, cxy.x, cxy.y);
			cell_cache.addObject(key, t);

			if (cxy.x = x) and (cxy.y = y) then begin
				c := t;
				break;
			end;
		end;
		if not Assigned(c) then continue;

		// The resolved cell
		Result := c;
		Exit;
	end;
end;

function cell_rvis_cell(e: IInterface): IInterface;
const
	VIS_WIDTH = 3;
var
	r, t, w: IInterface;
	rxy: TwbGridCell;
	cxy: array[0..1] of TwbGridCell;
	xy: array[0..1,0..1] of integer;
	m, i: integer;
	s: string;
	flags: cardinal;
	key: string;
	idx: integer;
begin
	// Non-persistent exterior cells only
	if not cell_filter(e, true, true, false, false) then
		Exit;

//	AddMessage('check: ' + FullPath(e));

	r := ElementBySignature(e, 'RVIS');
	if Assigned(r) then begin
		r := LinksTo(r);
		if Signature(r) = 'CELL' then begin
//			AddMessage('resolved: ' + FullPath(r));
			Result := r;
			Exit;
		end else begin
			key := IntToStr(FormID(e));
			idx := rvis_cell_cache.indexOf(key);
			if not idx < 0 then begin
//				AddMessage(Format('cell_rvis_cell: cached: %s, idx = %d: %s', [ key, idx, Name(e) ]));
				Result := rvis_cell_cache.Objects[idx];
				Exit;
			end;

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

	cxy[1].x := xy[0,1];
	cxy[1].y := xy[1,1];

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
	s := cell_world_edid(e);
	r := cell_resolve(s, cxy[1].x, cxy[1].y);

if false then begin
	if Assigned(r) then begin
		AddMessage('cell_rvis_cell: resolved (calculated): ' + FullPath(r));
	end else begin
		AddMessage('cell_rvis_cell: unable to resolve RVIS cell: ' + FullPath(e));
	end;
end;

	rvis_cell_cache.addObject(key, r);

	Result := r;
end;


function cell_rvis_rvis_grid(e: IInterface; offset: integer): TList;
var
	tl, tll: TList;
	r, t: IInterface;
	seen: THashedStringList;
	cxy: TwbGridCell;
	ix, iy, jx, jy, k: integer;
	x, y: integer;
	ws, key: string;
begin
	ws := cell_world_edid(e);
	tl := TList.create;
	seen := THashedStringList.create;
	seen.sorted := true;

//	AddMessage(Format('cell_rvis_rvis_grid: %s: %s', [GetFileName(e), Name(e)]));

        cxy := GetGridCell(e);
	for ix := -offset to offset do begin
		for iy := -offset to offset do begin
			e := cell_resolve(ws, cxy.x + ix, cxy.y + iy);
			if not Assigned(e) then
				continue;

			r := cell_rvis_cell(e);
			if not Assigned(r) then
				continue;

			key := IntToStr(FormID(r));
			if not seen.indexOf(key) < 0 then
				continue;
			seen.add(key);

//			AddMessage(Format('cell_rvis_rvis_grid: %s: %s', [GetFileName(r), Name(r)]));
			tl.add(r);
		end;
	end;
//	AddMessage(' ');

	seen.free;

	Result := tl;
end;

function cell_rvis_cell_grid(e: IInterface): TList;
const
	RVIS_OFFSET = 1;
var
	tl, rgl, rvl: TList;
	r, t: IInterface;
	cxy: TwbGridCell;
	i, ix, iy, jx, jy, k, idx: integer;
	x, y: integer;
	s, ws, key: string;
begin
	ws := cell_world_edid(e);
	rvl := cell_rvis_rvis_grid(e, RVIS_OFFSET);
	rgl := TList.create;

	for i := 0 to Pred(rvl.count) do begin
		r := ObjectToElement(rvl[i]);
		if not Assigned(r) then
			continue;

if false then begin
		// Attempt to use cached rvis_grid first
		key := IntToStr(FormID(r));
		idx := rvis_cell_grid_cache.indexOf(key);
		if not idx < 0 then begin
			tl := TList(rvis_cell_grid_cache.Objects[idx]);
			if Assigned(tl) then begin
//				AddMessage(Format('cell_rvis_cell_grid: cached: %s, idx = %d: %s', [ key, idx, Name(r) ]));
				rgl.add(tl);
				continue;
			end;
		end;
end;

		// Add the RVIS cell to the front of the list
		// so that it can be predictably referenced at
		// index 0 by client code.
		tl := TList.create;
		tl.add(r);

		// Get the coordinates of the RVIS cell and find all
		// adjacent cells in the grid.
		cxy := GetGridCell(r);
		for jx := -1 to 1 do begin
			for jy := -1 to 1 do begin
				x := cxy.x + jx;
				y := cxy.y + jy;
				t := cell_resolve(ws, x, y);
				if not Assigned(t) then begin
//					AddMessage(Format('%s: rvxy(%d,%d): %d,%d :: %s', [FullPath(r),cxy.x,cxy.y,x,y,'NULL']));
					continue;
				end;

				// Since the RVIS cell already occupies the first slot
				// ignore the relative 0,0 offset as it is the same cell.
				if (jx = 0) and (jy = 0) then
					continue;

//				AddMessage(Format('%s: rvxy(%d,%d): %d,%d :: %s', [FullPath(r),cxy.x,cxy.y,x,y,FullPath(t)]));
				tl.add(t);
			end;
		end;

		rgl.add(tl);

if false then begin
//		AddMessage('cell_rvis_cell_grid: caching: ' + key);
		rvis_cell_grid_cache.addObject(key, tl);
end;
	end;

	Result := rgl;
end;

function cell_filter(e: IInterface; main_allow, other_allow, interior_allow, persistent_allow: boolean): boolean;
var
	t: IInterface;
	is_main, is_interior, is_persistent: boolean;
	ws: string;
	flags: cardinal;
begin
	Result := false;

	// Skip non-cells
	if Signature(e) <> 'CELL' then
		Exit;

	if elem_deleted_check(e) then
		e := MasterOrSelf(e);

	is_interior := (GetElementEditValues(e, 'DATA\Is Interior Cell') = '1');
	if is_interior and not interior_allow then begin
		Exit;
	end else if not is_interior then begin
		ws := cell_world_edid(e);
		is_main := (ws = 'Commonwealth');
		if is_main and not main_allow then
			Exit;
		if not is_main and not other_allow then
			Exit;

		// Skip persistent worldspace cells (which never have precombines/previs)
		flags := GetElementNativeValues(e, 'Record Header\Record Flags');
		is_persistent := ((flags and F_PERSISTENT) <> 0);
		if is_persistent and not persistent_allow then
			Exit;
	end

	Result := true;
end;

procedure cell_pc_clear(e: IInterface);
var
	i: integer;
begin
	for i := 0 to Pred(length(pc_sig_tab)) do begin
		if ElementExists(e, pc_sig_tab[i]) then
			Remove(ElementBySignature(e, pc_sig_tab[i]));
	end;
end;

procedure cell_pv_clear(e: IInterface);
var
	i: integer;
begin
	for i := 0 to Pred(length(pv_sig_tab)) do begin
		if ElementExists(e, pv_sig_tab[i]) then
			Remove(ElementBySignature(e, pv_sig_tab[i]));
	end;
end;

function plugin_cell_copy_safe(plugin: IwbFile; e: IInterface; pc_clear, pv_clear: boolean): IInterface;
var
	t: IInterface;
begin
	t : = plugin_cell_find(plugin, e);
	if not Assigned(t) then begin
		t := form_copy_safe(plugin, e, (not pc_clear), (not pv_clear));
		if pc_clear then
			cell_pc_clear(t);
		if pv_clear then
			cell_pv_clear(t);
	end;

	Result := t;
end;

procedure dmarker_refr_promote(plugin: IwbFile; e: IInterface);
var
	t, r, b: IInterface;
	i: integer;
begin
	// Guard against xedit corrupting CELL parents
	t := plugin_cell_copy_safe(plugin, e, true, true);
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
	// Guard against xedit corrupting CELL parents
	t := plugin_cell_copy_safe(plugin, e, true, true);
	r := Add(t, 'REFR', true);
	b := Add(r, 'NAME', true);
	SetNativeValue(b, XMarker_FID);

//	AddMessage(FullPath(r));
end;

procedure stat_refr_promote(plugin: IwbFile; e: IInterface; marker_fallback: boolean);
var
	t, r, m: IInterface;
	i, oc: integer;
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

	m := MasterOrSelf(e);
	oc := OverrideCount(m);
	for i := Pred(oc) downto -1 do begin
		if i < 0 then begin
			t := m;
		end else begin
			t := OverrideByIndex(m, i);
		end;

//		AddMessage('stat_refr_promote: ' + FullPath(t));
//		AddMessage('stat_refr_promote: ' + FullPath(e));

		// Do not go past the current plugin for this element
		if GetLoadOrder(GetFile(t)) > GetLoadOrder(GetFile(e)) then
			continue;
		if Equals(GetFile(t), GetFile(plugin)) then
			continue;

		r := cell_refr_rvis_first(t, true, true);
//		AddMessage('stat_refr_promote: r: ' + FullPath(r));
		if not Assigned(r) then continue;

		if Debug then begin
//			AddMessage(Format('%s: Copying: %s', [GetFileName(e), Name(r)]))
		end;

		// Guard against xedit corrupting CELL parents
		plugin_cell_copy_safe(plugin, e, true, true);
		form_copy_safe(plugin, r, false, false);

		Exit;
	end;

	// If no static or otherwise refr found, synthesize one from a
	// known marker.
	if marker_fallback then begin
//		AddMessage('stat_refr_promote: marker_fallback: ' + FullPath(e));
		dmarker_refr_promote(plugin, e);
	end;
end;

function plugin_cell_find(plugin: IwbFile; e: IInterface): IInterface;
var
	t: IInterface;
	i: integer;
begin
	for i := 0 to Pred(OverrideCount(e)) do begin
		t := OverrideByIndex(e, i);
		if Equals(GetFile(t), plugin) then begin
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
				if PerElementMasters then
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
						if not pc_sig_tab.indexOf(s) < 0 then
							continue;
					end;

					if not pv_copy then begin
						// If the previous deep copy failed it is extremely likely
						// it was due to these elements and they will be copied
						// from the prior override (see comment below).
						if not pv_sig_tab.indexOf(s) < 0 then
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

function previs_merge(plugin: IwbFile; e, o, m: IInterface): Boolean;
begin
	if Debug then
		AddMessage(Format('%s: previs_merge: %s', [GetFileName(plugin), Name(e)]));

	try
		if PerElementMasters then
			elem_masters_add(plugin, e);

		// Copy previs data from current element to plugin
		elem_pv_sync(e, o);

		// Ensure any 'no previs' flags are removed if master also does not have
		elem_previs_flag_clean(o, m);

		// Copy form version info
		elem_version_sync(e, o);
	except
		on Ex: Exception do begin
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := true;
end;

function precombine_merge(plugin: IwbFile; e, o, m: IInterface): Boolean;
var
	r, t: IInterface;
begin
	if Debug then
		AddMessage(Format('%s: precombine_merge: %s', [GetFileName(plugin), Name(e)]));

	try
		if PerElementMasters then
			elem_masters_add(plugin, e);

		// Merge precombine data from current element to overridden plugin
		elem_pc_sync(e, o);

		// Ensure any 'no previs' flags are removed if master also does not have
		elem_previs_flag_clean(o, m);

		// Copy form version info
		elem_version_sync(e, o);
	except
		on Ex: Exception do begin
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := true;
end;

// Note: this copies to a plugin rather than merging back into the master/override
function previs_extract(plugin: IwbFile; e, o, m: IInterface): Boolean;
var
	r: IInterface;
begin
	if Debug then
		AddMessage(Format('%s: previs_extract: %s', [GetFileName(plugin), Name(e)]));

	try
		// Copy overridden plugin data as a starting base
		r := form_copy_safe(plugin, o, true, true);

		previs_merge(plugin, e, r, m);
	except
		on Ex: Exception do begin
			plugin_elem_remove(plugin, r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := true;
end;

// Note: this copies to a plugin rather than merging back into the master/override
function precombine_extract(plugin: IwbFile; e, o, m: IInterface): Boolean;
var
	r: IInterface;
begin
	if Debug then
		AddMessage(Format('%s: precombine_extract: %s', [GetFileName(plugin), Name(e)]));

	try
		// Copy overridden plugin data as a starting base
		r := form_copy_safe(plugin, o, true, true);

		precombine_merge(plugin, e, r, m);
	except
		on Ex: Exception do begin
			plugin_elem_remove(plugin, r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := true;
end;

function precombine_split(plugin: IwbFile; e, o, m: IInterface): Boolean;
var
	r, t: IInterface;
	s: TString;
	i, j: integer;
begin
	if Debug then
		AddMessage(Format('%s: precombine_split: %s', [GetFileName(plugin), Name(e)]));

	try
		// XXX: xEdit will choke on delocalized plugins containing strings like '$Farm05Location'
		// XXX: due to it wrongly interpreting it as a hex/integer value and will also disallow copying
		// XXX: an element with busted references. Attempt a normal deepcopy first and if it does not
		// XXX: succeed then attempt an element by element copy whilst avoiding bogus XPRI data.

		if PerElementMasters then
			elem_masters_add(plugin, e);

		r := wbCopyElementToFile(e, plugin, false, true);
	except
		// Deep copy failed, most likely due to bad XPRI data, attempt a per-element copy.
		// The vast majority of the time this branch will only be taken for XPRI data.
		on Ex: Exception do begin
			if Debug then begin
				AddMessage('Failed to deep copy: ' + FullPath(e));
				AddMessage('             reason: ' + Ex.Message);
				AddMessage('Attempting per element copy');
			end;

			try
//				if PerElementMasters then
//					elem_masters_add(plugin, e);

				r := wbCopyElementToFile(e, plugin, false, true);
				SetElementNativeValues(r, 'Record Header\Record Flags', GetElementNativeValues(e, 'Record Header\Record Flags'));

				for i := 0 to Pred(ElementCount(e)) do begin
					t := ElementByIndex(e, i);
					if not Assigned(t) then continue;

					s := Signature(t);
					if not Assigned(s) then continue;

					// If the previous deep copy failed it is extremely likely
					// it was due to these elements and they will be copied
					// from the prior override (see comment below).
					if (s = 'XPRI') or (s = 'RVIS') or (s = 'VISI') then
						continue;

					if not ElementExists(r, s) then
						Add(r, s, true);
					ElementAssign(ElementBySignature(r, s), LowInteger, t, false);
				end;
			except
				on Ex: Exception do begin
					Remove(r);
					Raise Exception.Create(Ex.Message);
				end;
			end;
		end;
	end;

	try
		// Always defer to the previs data of the preceding override due to a CK bug
		// when >2 masters are used for precombine generation. 99% of the time the most
		// recent overridden refs are the actual refs used and these values will be
		// overwritten by previs generation anyway.
		elem_pv_sync(o, r);

		// Ensure any 'no previs' flags are removed if master also does not have
		elem_previs_flag_clean(r, m);

		// Copy form version info
		elem_version_sync(e, r);
	except
		on Ex: Exception do begin
			Remove(r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	try
		// temp: nuke xcri/xpri
//		Remove(ElementBySignature(e, 'XCRI'));
//		Remove(ElementBySignature(e, 'XPRI'));

		// Promote static references from any containing cells to generated plugin
		stat_refr_promote(plugin, r, true);
	except
		on Ex: Exception do begin
			Remove(r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := true;
end;

function ts_to_int(ts: string): integer;
begin
	Result := 0;
	if Assigned(ts) and length(ts) >= 5 then begin
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
	m := MasterOrSelf(e);
	oc := OverrideCount(m);
	ts := 0;
	ts_max := 0;

	Result := nil;

	for i := Pred(oc) downto -1 do begin
		if i < 0 then begin
			t := m;
		end else begin
			t := OverrideByIndex(m, i);
		end;

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

		if ts = 0 or ts > ts_max then begin
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

function cell_rvis_overlap_list(e: IInterface; parents, children, require_static: boolean): TList;
var
	out, tl, rgl: TList;
	cxy: TwbGridCell;
	t, r, m: IInterface;
	i, j, k, oc: integer;
begin
	rgl := cell_rvis_cell_grid(e);
	if not Assigned(rgl) then begin
		Result := nil;
		Exit;
	end;

	out := TList.create;
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
			for k := -1 to Pred(oc) do begin
				if k < 0 then begin
					r := m;
				end else begin
					r := OverrideByIndex(m, k);
				end;

//				cxy := GetGridCell(r);
//				AddMessage(Format('%d,%d %s', [cxy.x,cxy.y,FullPath(r)]));

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
				//

				if require_static then begin
					if not cell_refr_rvis_check(e) then
						continue;
				end;

				if GetLoadOrder(GetFile(r)) > GetLoadOrder(GetFile(e)) then begin
					if children then begin
//						AddMessage(Format('%s: cell_rvis_overlap_list: child: %s: %s', [ GetFileName(e), GetFileName(r), Name(r) ]));
						out.add(r);
					end;
				end else if GetLoadOrder(GetFile(r)) <= GetLoadOrder(GetFile(e)) then begin
					if parents then begin
//						AddMessage(Format('%s: cell_rvis_overlap_list: parent: %s: %s', [ GetFileName(e), GetFileName(r), Name(r) ]));
						out.add(r);
					end;
				end

			end;
		end;

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
	rvx, rvy, i, j, k: integer;
	f: string;
begin
	// Non-persistent exterior cells only
	if not cell_filter(e, true, true, false, false) then
		Exit;

	rgl := cell_rvis_cell_grid(e);
	if not Assigned(rgl) then
		Exit;

	for i := 0 to Pred(rgl.count) do begin
		tl := TList(rgl[i]);
		if not Assigned(tl) then
			continue;

		// RVIS cell is always at the head of the list
		rvis := ObjectToElement(tl[0]);
		cxy := GetGridCell(rvis);
		rvx := cxy.x;
		rvy := cxy.y;

		for j := 0 to Pred(tl.count) do begin
			t := ObjectToElement(tl[j]);
			if not Assigned(t) then
				continue;

			m := MasterOrSelf(t);
			for k := -1 to Pred(OverrideCount(m)) do begin
				if k < 0 then begin
					r := m;
				end else begin
					r := OverrideByIndex(m, k);
				end;

				// Do not go past the current plugin for this element
				if GetLoadOrder(GetFile(r)) >= GetLoadOrder(GetFile(e)) then
					break;

				// Account for more than just stat objects as previs
				// takes other things into account for physics.
				if require_static then begin
					if not cell_refr_rvis_check(r) then
						continue;
				end;

				// Check for masters that would be added but are not
				// present in the plugin to indicate what would be
				// added. XXX: Try this with and without STAT only?
				if not HasMaster(plugin, GetFileName(r)) then begin
					AddMessage(Format('VIS: [%d][%d][%d] %s needs master: %s (rvis: %d,%d :: e: %s :: r: %s)', [i,j,k+1,GetFileName(plugin),GetFileName(r),rvx,rvy,Name(e),Name(r)]));
				end;
				plugin_master_add(plugin, r, true, false);

//				AddMessage(Format('[%d][%d][%d] %s', [i,j,k+1,FullPath(r)]));
			end;
		end;

//		tl.free;
	end;

	rgl.free;

	if sort then
		SortMasters(plugin);
end;

procedure plugin_master_cell_rvis_clean(e: IInterface; main_allow, other_allow, interior_allow, require_static: boolean);
var
	tl, rgl: TList;
	cxy: TwbGridCell;
	t, r, m: IInterface;
	i, j, k, oc: integer;
	cell_keep, remove: boolean;
begin
	if (Signature(e) <> 'CELL') then
		Exit;

	remove := false;
	cell_keep := cell_filter(e, main_allow, other_allow, interior_allow, false);
	if not cell_keep then begin
		remove := true;
	end else begin
		tl := cell_rvis_overlap_list(e, false, true, require_static);
		if not Assigned(tl) then begin
			remove := true;
		end else begin
			if tl.count = 0 then
				remove := true;
			tl.free;
		end;
//	end else if IsWinningOverride(e) then begin
//		remove := true;
	end;

	if remove then begin
		cell_remove(e);
//	end else begin
//		cell_queue.add(e);
	end;

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
		if i < 0 then begin
			t := m;
		end else begin
			t := OverrideByIndex(m, i);
		end;

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
		if i < 0 then begin
			t := m;
		end else begin
			t := OverrideByIndex(m, i);
		end;

		if Equals(e, t) then break;

		// If the overridden cell does not have any STAT or SCOL
		// references then it should not be considered a master
		// candidate because it will not affect precombines. Note:
		// this is only checked if the parent cell does not have
		// any statics of its own. If it does then the master
		// will be added regardless to guard against generation
		// of previs data not taking into account the override.
		if require_static and not cell_refr_rvis_check(t) then
			continue;

		plugin_master_add(plugin, t, true, false);
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
AddMessage('e: ' + FullPath(e));
AddMessage('r: ' + FullPath(r));
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
	kl: THashedStringList;
	flags: cardinal;
begin
	if Signature(e) <> 'CELL' then
		Exit;

	cg := ChildGroup(e);
	if not Assigned(cg) then
		Exit;
//	AddMessage('cg: ' + FullPath(cg));

	rl := TList.create;
	kl := THashedStringList.create;

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

			if elem_deleted_check(e) then begin
				b := BaseRecord(MasterOrSelf(t));
			end else begin
				b := BaseRecord(t);
			end;

//			if not Assigned(b) then
//				continue;
//			AddMessage('b: ' + FullPath(b));

			s := Signature(b);
			if (pc_keep_map.indexof(s) < 0) and (pv_keep_map.indexof(s) < 0) then begin
				flags := GetElementNativeValues(e, 'Record Header\Record Flags');

				// Delete only if record does not have 'initially disabled' or
				// 'visible when distant' flags if not referenced.
				if ((flags and $8800) = 0) and not refr_referenced_by_type(t, 'REFR') then
					rl.add(t);
			end;
		end;
	end;

	for i := 0 to Pred(rl.count) do begin
		t := ObjectToElement(rl[i]);
		AddMessage(Format('%s: Removing: %s', [GetFileName(e), Name(t)]));
		RemoveNode(t);

		Inc(ref_remove_cnt);
	end;

	rl.free;
	kl.free;
end;

procedure master_clean(e: IInterface; main_allow, other_allow, interior_allow, persistent_allow, refr_clean, stat_check, rvis_check, require_static, winning_only, non_winning_only, remove: boolean);
var
	winning_override, editable: boolean;
begin
	if Signature(e) <> 'CELL' then
		Exit;

	editable := IsEditable(e);
	winning_override := isWinningOverride(e);

	if not cell_filter(e, main_allow, other_allow, interior_allow, persistent_allow) then begin
		if editable and remove then begin
//			AddMessage('remove: cell_filter');
			cell_remove(e);
		end;
		Exit;
	end;

	if stat_check and not cell_stat_check(e) then begin
		if editable and remove then begin
//			AddMessage('remove: stat_check');
			cell_remove(e);
		end;
		Exit;
	end;

	if rvis_check and not cell_rvis_overlap_check(e, false, true, require_static) then begin
		if editable and remove then begin
//			AddMessage('remove: rvis_check');
			cell_remove(e);
		end;
		Exit;
	end;

	// XXX: This really means keep only non-winning overrides,
	// XXX: aka preparing as a master for generation only.
	if non_winning_only and winning_override then begin
		if editable and remove then begin
//			AddMessage('remove: non-winning-only');
//			cell_remove(e);
		end;
		Exit;
	end;

	// XXX: This really means only *add* winning overrides,
	// XXX: aka preparing for generated esps per plugin.
	if winning_only and not winning_override then begin
		if editable and remove then begin
//			AddMessage('remove: winning-only');
//			cell_remove(e);
		end;
		Exit;
	end;

	if refr_clean then begin
		cell_refr_clean(e);
	end;

	if not base_master_list.indexOf(GetFileName(e)) < 0 then
		Exit;
	if not master_force.indexOf(GetFileName(e)) < 0 then
		Exit;

	// Pre-clean precombined and previs data from cells
	cell_pc_clear(e);
	cell_pv_clear(e);

	cell_queue.add(e);
end;

procedure master_add(e: IInterface; main_allow, other_allow, interior_allow, persistent_allow, promote, remove: boolean);
var
	editable: boolean;
begin
	editable := IsEditable(e);

	if Signature(e) <> 'CELL' then
		Exit;

	// General add masters for all non-persistent cells
	if cell_filter(e, main_allow, other_allow, interior_allow, persistent_allow) then begin
		if editable and promote and not cell_refr_rvis_check(e) then
			stat_refr_promote(GetFile(e), e, true);

		// XXX: only add if has pc/pv refrs?
		cell_queue.add(e);
	end else if editable and remove then begin
		AddMessage('master_add: remove');
		cell_remove(e);
	end;
end;

function Process(e: IInterface): integer;
var
	o, m, t, r, w, plugin: IInterface;
	tfname, efname, efoname: string;
	idx, i, j, oc: integer;
	ts, pcmb_max, visi_max: integer;
	merge: boolean;
	nv: string;
	ol, ml: TList;
	promote, remove, winning_only, non_winning_only, refr_clean, stat_check, rvis_check, require_static: boolean;
begin
	if plugin_combined_use then begin
		remove := false;
		promote := true;
		refr_clean := false;
		stat_check := false;
		rvis_check := false;
		require_static := false;
		winning_only := true;
		non_winning_only := false;
	end else if plugin_each_use then begin
		remove := true;
		promote := true;
		refr_clean := false;
		stat_check := false;
		rvis_check := false;
		require_static := false;
		winning_only := false;
		non_winning_only := false;
	end else begin
		remove := true;
		promote := true;
		refr_clean := false;
		stat_check := false;
		rvis_check := false;
		require_static := false;
		winning_only := false;
		non_winning_only := false;
	end;

	// Add any forced masters
	if Signature(e) = 'TES4' then begin
		if (pos('master', process_mode) <> 0) and not plugin_combined_use then begin
//		if (pos('master', process_mode) <> 0) and not (plugin_combined_use or plugin_each_use) then begin
			if plugin_master_queue.indexof(GetFileName(e)) < 0 then
				plugin_master_queue.addObject(GetFileName(e), GetFile(e));
			Exit;
		end;
	end else if remove and (Signature(e) = 'RFGP') then begin
		AddMessage(Format('%s: Removing: %s', [GetFileName(e), Name(e)]));
		RemoveNode(e);
	end;

	// Non-persistent cells only (ignore not modify)
	if not cell_filter(e, true, true, true, false) then
		Exit;

	// direct cleaning calls

//	if process_mode = 'init_master_cell_rvis_clean' then begin
//		plugin_master_cell_rvis_clean(e, true, true, true, false);
//		Exit;
//	end;

	// master clean

	if process_mode = 'init_cell_all_master_clean' then begin
		master_clean(e, true, true, true, false, refr_clean, stat_check, rvis_check, require_static, winning_only, non_winning_only, remove);
		Exit;
	end else if process_mode = 'init_cell_exts_master_clean' then begin
		master_clean(e, true, true, false, false, refr_clean, stat_check, rvis_check, require_static, winning_only, non_winning_only, remove);
		Exit;
	end else if process_mode = 'init_cell_ints_master_clean' then begin
		master_clean(e, false, false, true, false, refr_clean, stat_check, rvis_check, require_static, winning_only, non_winning_only, remove);
		Exit;
	end else if process_mode = 'init_cell_main_master_clean' then begin
		master_clean(e, true, false, false, false, refr_clean, stat_check, rvis_check, require_static, winning_only, non_winning_only, remove);
		Exit;
	end else if process_mode = 'init_cell_other_master_clean' then begin
		master_clean(e, false, true, false, false, refr_clean, stat_check, rvis_check, require_static, winning_only, non_winning_only, remove);
		Exit;
	end;

	// master add

	if process_mode = 'init_cell_all_master_add' then begin
		master_add(e, true, true, true, false, promote, remove);
		Exit;
	end else if process_mode = 'init_cell_exts_master_add' then begin
		master_add(e, true, true, false, false, promote, remove);
		Exit;
	end else if process_mode = 'init_cell_ints_master_add' then begin
		master_add(e, false, false, true, false, promote, remove);
		Exit;
	end else if process_mode = 'init_cell_main_master_add' then begin
		master_add(e, true, false, false, false, promote, remove);
		Exit;
	end else if process_mode = 'init_cell_other_master_add' then begin
		master_add(e, false, true, false, false, promote, remove);
		Exit;
	end;

	if process_mode = 'stats' then begin
		plugin_cell_stat_master_add(GetFile(e), e, true, true);
		plugin_cell_rvis_master_add(GetFile(e), e, true, true);
		Exit;
	end;

	if process_mode = 'init_alt' then begin
		Result := plugin_init(mode);
		Exit;
	end;

	if process_mode = 'init' then begin
		Result := plugin_cell_stat_master_add(GetFile(e), e, true, true);
		Exit;
	end;

	if process_mode = 'final_main' then begin
		if not base_master_list.indexOf(GetFileName(e)) < 0 then
			Exit;
		plugin := plugin_resolve(e);
		plugin_cell_copy_safe(plugin, WinningOverride(e), false, false);
		Exit;
	end;

	if process_mode = 'precombine_merge' then begin
		efname := GetFileName(e);
		idx := pos('.precombine', efname);
		if idx = 0 then
			Exit;
		efoname := copy(efname, 1, idx - 1);
	end;

	if process_mode = 'previs_merge' then begin
		efname := GetFileName(e);
		idx := pos('.previs', efname);
		if idx = 0 then
			Exit;
		efoname := copy(efname, 1, idx - 1);
	end;

	// | [0] master | [1] override | [2] *override* | [3] element | ...
	m := MasterOrSelf(e);
	oc := OverrideCount(m);
	ol := TList.create;
	ml := TList.create;

	for i := Pred(oc) downto -1 do begin
		if i < 0 then begin
			t := m;
		end else begin
			t := OverrideByIndex(m, i);
		end;

		tfname := GetFileName(t);
		efname := GetFileName(e);

		// XXX: consider allowing precombine_merge files in previs mode
		if (tfname <> efname) and (pos(tfname, efname) <> 0) then begin
			ol.add(t);
		end else if (pos('.precombine', tfname) = 0) and (pos('.previs', tfname) = 0) then begin
			ml.add(t);
		end;
	end;

	if ol.count = 0 then begin
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

		t := plugin_cell_copy_safe(plugin, t, false, false);
		ol.add(t);
	end;

	ml.free;

if false then begin
	if (pos('precombine', process_mode) <> 0) then begin
		t := override_timestamp_latest(e, 'PCMB');
	end else if (pos('previs', process_mode) <> 0) then begin
		t := override_timestamp_latest(e, 'VISI');
	end;
end;

t := e;

	for i := 0 to Pred(ol.count) do begin
		o := ObjectToElement(ol[i]);
		merge := (MergeIntoOverride and IsEditable(o));
if false then begin
		if Debug then begin
			if merge then begin
				AddMessage(Format('%s: m == %s, o == %s, t == %s, oc == %d, merge == %d: %s',
					[GetFileName(e), GetFileName(m), GetFileName(o), GetFileName(t), oc, 1, Name(e)]));
			end else begin
				AddMessage(Format('%s: m == %s, o == %s, t == %s, oc == %d, merge == %d: %s',
					[GetFileName(e), GetFileName(m), GetFileName(o), GetFileName(t), oc, 0, Name(e)]));
			end;
		end;
end;

		if merge then begin
			plugin := GetFile(o);
		end else begin
			plugin := plugin_resolve(o);
		end;

		if not Assigned(plugin) then begin
			ol.free;
			Result := StopOnError;
			Exit;
		end;

		try
			if process_mode = 'precombine_merge' then begin
				precombine_merge(plugin, e, o, m);
			end else if process_mode = 'previs_merge' then begin
				previs_merge(plugin, e, o, m);
			end else if process_mode = 'precombine_extract' then begin
				precombine_extract(plugin, e, o, m);
			end else if process_mode = 'previs_extract' then begin
				previs_extract(plugin, e, o, m);
			end else if process_mode = 'precombine_split' then begin
				precombine_split(plugin, e, o, m);
			end else if process_mode = 'previs_split' then begin
				previs_split(plugin, e, o, m);
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

function Finalize: integer;
var
	t, r, plugin: IInterface;
	i, j, k: integer;
	rc, rct: integer;
begin
	AddMessage(Format('Adding cell masters for %d cells', [ cell_queue.count ]));
	for i := 0 to Pred(cell_queue.count) do begin
		t := ObjectToElement(cell_queue[i]);
		if not Assigned(t) then
			continue;

//		if Debug then AddMessage(Format('cell_queue[%d]: %s', [i,FullPath(t)]));

		plugin := plugin_resolve(t);

		if stat_promote then begin
			stat_refr_promote(plugin, t, true);
			plugin_master_add(plugin, t, true, false);
		end;

		plugin_cell_stat_master_add(plugin, t, true, false);

		if plugin_master_queue.indexof(GetFileName(plugin)) < 0 then
			plugin_master_queue.addObject(GetFileName(plugin), plugin);

		if ((i + 1 = cell_queue.count) or ((i + 1) mod (trunc(cell_queue.count / 10) + 1) = 0)) then
			AddMessage(Format('Remain: %d cells (%d/%d)', [ cell_queue.count - (i + 1), i + 1, cell_queue.count ]));
	end;

	AddMessage(Format('Adding vis grid masters for %d cells', [ cell_queue.count ]));
	for i := 0 to Pred(cell_queue.count) do begin
		t := ObjectToElement(cell_queue[i]);
		if not Assigned(t) then
			continue;

//		if Debug then AddMessage(Format('cell_queue[%d]: %s', [i,FullPath(t)]));

		plugin := plugin_resolve(t);
		plugin_cell_rvis_master_add(plugin, t, true, false);

		if plugin_master_queue.indexof(GetFileName(plugin)) < 0 then
			plugin_master_queue.addObject(GetFileName(plugin), plugin);

		if ((i + 1 = cell_queue.count) or ((i + 1) mod (trunc(cell_queue.count / 10) + 1) = 0)) then
			AddMessage(Format('Remain: %d cells (%d/%d)', [ cell_queue.count - (i + 1), i + 1, cell_queue.count ]));
	end;

	for i := 0 to Pred(plugin_master_queue.count) do begin
		plugin := ObjectToElement(plugin_master_queue.Objects[i]);
		plugin_master_force(plugin, true, false);
		SortMasters(plugin);
	end;

	AddMessage(Format('Removed %d cells', [ cell_remove_cnt ]));
	AddMessage(Format('Removed %d refs', [ ref_remove_cnt ]));

	// XXX: remove tlists referenced in rvis_cell_grid_cache
	rvis_cell_cache.free;
	rvis_cell_grid_cache.free;

	cell_queue.free;
	cell_cache.free;

	master_force_seen.free;
	master_force.free;

	plugin_file_map.free;
	plugin_master_queue.free;

//	frmMain.Close;

end;

end.

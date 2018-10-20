{
	1. Split precombines into separate plugins based on their master.
	2. Recombine precombine/previs of loaded plugins into a final plugin.

	Hotkey: Ctrl+Shift+P
}

unit FO4_Precombined_Split;
const
	Debug = True;
//	Debug = False;
	StopOnError = True;
	VersionInc = False;		// Not implemented
	ConflictOnly = False;		// Not implemented
	MergeIntoOverride = True;
	CopyPerCellStatic = True;
	CopyPerCellStaticAll = False;
	PerElementMasters = True;
	InitFileSuffix = 'precombine_gen';
	PrecombineFileBase = 'precombine';
	PrecombineFileSuffix = 'precombine_split';
	PrevisFileBase = 'previs';
	PrevisFileSuffix = 'previs_split';
	FinalFileBase = 'pcv-final';
	PluginSuffix = 'esp';
	MaxFileAttempts = 8;
var
	// Elements to keep from the most immediate plugin being overridden
	plugin_final: IInterface;
	plugin_map: array [0..255] of IInterface;
	pc_sig_tab: array [0..1] of TString;
	pv_sig_tab: array [0..2] of TString;
	pc_keep_map: THashedStringList;
	pv_keep_map: THashedStringList;
	pc_refr_keep_map: THashedStringList;
	pv_refr_keep_map: THashedStringList;

	cell_cache: THashedStringList;
	cell_queue: Tlist;

	// Experimental
	rmap: array [0..2] of THashedStringList;
	cmap: array [0..255] of THashedStringList;

function Initialize: integer;
var
	i: integer;
begin
	// Precombine specific signatres
	pc_sig_tab[0] := 'XCRI';
	pc_sig_tab[1] := 'PCMB';

	// Previs specific signatures
	pv_sig_tab[0] := 'XPRI';
	pv_sig_tab[1] := 'RVIS';
	pv_sig_tab[2] := 'VISI';

	pc_keep_map := THashedStringList.create;
	pc_keep_map.Sorted := True;
	pc_keep_map.add('CELL');
	pc_keep_map.add('LAYR');
	pc_keep_map.add('RFGP');
	pc_keep_map.add('MSWP');
	pc_keep_map.add('REFR');
	pc_keep_map.add('SCOL');
	pc_keep_map.add('STAT');
	pc_keep_map.add('TES4');
	pc_keep_map.add('WRLD');

//	pc_keep_map.add('NAVM');
//	pc_keep_map.add('LAND');

	pv_keep_map := THashedStringList.create;
	pv_keep_map.Sorted := True;
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

	cell_cache := THashedStringList.create;
	cell_cache.Sorted := True;
	cell_cache.Duplicates := dupIgnore;

	cell_queue := TList.create;

	rmap[0] := THashedStringList.create;
	rmap[0].Sorted := True;
	rmap[0].Duplicates := dupAccept;

	rmap[1] := THashedStringList.create;
	rmap[1].Sorted := True;
	rmap[1].Duplicates := dupAccept;

	rmap[2] := THashedStringList.create;
	rmap[2].Sorted := True;
	rmap[2].Duplicates := dupAccept;

end;

procedure plugin_master_add(plugin: IwbFile; e: IInterface; parents: boolean);
var
	efile, mfile: IwbFile;
	efstr, mfstr: string;
	i: integer;
	sl: THashedStringList;
	tl: TList;
begin
	sl := THashedStringList.create;
	tl := TList.create;

	tl.add(GetFile(e));
	while tl.count <> 0 do begin
		efile := ObjectToElement(tl[0]);
		tl.delete(0);

		efstr := GetFileName(efile);
		if sl.indexOf(efstr) < 0 then begin
			sl.add(efstr);
		end else begin
			continue;
		end;

		if parents then begin
			// Add masters of the master being added otherwise
			// CK will emit these after all plugins have been
			// loaded and totally screw up the formid indexes.
			for i := 0 to Pred(MasterCount(efile)) do begin
				mfile := MasterByIndex(efile, i);
				mfstr := GetFileName(mfile);

				tl.add(mfile);
			end;
		end;

//		if Debug then AddMessage(Format('%s: Adding master: %s: %s', [GetFileName(plugin), efstr, Name(e)]));
		if not HasMaster(plugin, efstr) then begin
			if Debug then AddMessage(Format('%s: Adding master: %s: %s', [GetFileName(plugin), efstr, Name(e)]));
			AddMasterIfMissing(plugin, efstr);
		end;
	end;

	tl.free;
	sl.free;
end;

function plugin_file_resolve_existing(pfile: TString): IInterface;
var
	t: IInterface;
	i: integer;
begin
	// Attempt to find already created plugin in loaded files
	for i := Pred(FileCount) downto 0 do begin
		t := FileByIndex(i);
		if GetFileName(t) = pfile then begin
			Result := t; Exit;
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

function plugin_file_resolve(ofstr: TString; idx: integer; mode: TString): IInterface;
var
	plugin: IInterface;
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
		if Assigned(plugin) then begin
			Result := plugin; Exit;
		end;

		try
			if FileExists(DataPath + '/' + pfile) then
				continue;

			// create new plugin
			AddMessage('Creating file: ' + pfile);
			plugin := AddNewFileName(pfile);
			if Assigned(plugin) then begin
				Result := plugin; Exit;
			end;
		except
			on Ex: Exception do begin
				if pos('exists already', Ex.Message) <> 0 then
					continue;

				AddMessage('Unable to create new file for ' + pfile);
				Raise Exception.Create(Ex.Message);
			end;
		end;
	end;

	Result := nil;
end;

function plugin_resolve(e, o, m: IInterface; mode: TString): IInterface;
var
	t, r, tfile, rfile, ofile, plugin: IInterface;
	s, pfile, mfstr, tfstr, rfstr, ofstr: TString;
	idx, i, j, oc: integer;
begin
	// plugin index in plugin_map is based on the load order index of the overridden plugin
	ofile := GetFile(o);
	idx := GetLoadOrder(ofile);
	plugin := plugin_map[idx];
	if Assigned(plugin) then begin
		Result := plugin; Exit;
	end;

	// Master and immediately preceeding override (if any) of the element being processed
	ofstr := GetFileName(ofile);
	plugin := plugin_file_resolve(ofstr, 0, mode);
	plugin_map[idx] := plugin;

	if Debug then AddMessage('plugin_resolve: processing for ' + ofstr);

	try
		if mode = 'init' then begin
if false then begin
			tfstr := 'Fallout4.esm';
			if not HasMaster(plugin, tfstr) then begin
				if Debug then AddMessage('Adding master: ' + tfstr);
				AddMasterIfMissing(plugin, tfstr);
			end;
end;


			oc := OverrideCount(m);
			for i := -1 to Pred(oc) do begin
				if i < 0 then begin
					t := m;
				end else begin
					t := OverrideByIndex(m, i);
				end;

				tfile := GetFile(t);
				tfstr := GetFileName(t);

if false then begin
				// Masters of master
				for j := 0 to Pred(MasterCount(tfile)) do begin
					r := MasterByIndex(tfile, j);
					rfstr := GetFileName(r);
					if not HasMaster(plugin, rfstr) then begin
						if Debug then AddMessage('Adding master: ' + rfstr);
						AddMasterIfMissing(plugin, rfstr);
					end;
				end;
end;

				if not HasMaster(plugin, tfstr) then begin
					if Debug then AddMessage('Adding master: ' + tfstr);
					AddMasterIfMissing(plugin, tfstr);
				end;

			end;
		end else begin
			// Almost always the main game master (Fallout4.esm), however
			// there are situations with entirely new records where the
			// the actual master is the one originating said records.
			mfstr := GetFileName(m);
			if not HasMaster(plugin, mfstr) then begin
				if Debug then AddMessage('Adding master: ' + mfstr);
				AddMasterIfMissing(plugin, mfstr);
			end;

			// For the overridden master of the element being processed
			// add its masters as an explicit master to the plugin being
			// created. This is necessary due to CKs idea of how the per
			// master plugin should look had it been saved from CK. Not
			// doing this and instead adding only element-required masters
			// will result in CK misnumbering the reference formids when
			// the created plugin is merged back in with version control.
			for j := 0 to Pred(MasterCount(ofile)) do begin
				t := MasterByIndex(ofile, j);
				tfile := GetFileName(t);
				if not HasMaster(plugin, tfile) then begin
					if Debug then AddMessage('Adding master: ' + GetFileName(t));
					AddMasterIfMissing(plugin, tfile);
				end;
			end;

			// The actual override prior to this elements plugin
			if not Equals(o, m) then begin
				if not HasMaster(plugin, ofstr) then begin
					if Debug then AddMessage('Adding master: ' + ofstr);
					AddMasterIfMissing(plugin, ofstr);
				end;
			end;
		end;

		// Sort only, do *not* clean masters or it will wreck CKs idea
		// of how the plugin should look prior to merge.
		if Debug then AddMessage('Sorting masters');
		SortMasters(plugin);
	except
		on Ex: Exception do begin
			AddMessage('Failed to add masters: ' + FullPath(e));
			AddMessage('		reason: ' + Ex.Message);

			Result := nil; Exit;
		end;
	end;

	Result := plugin;
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
		Result := wbCopyElementToFile(e, plugin, False, True);
	except
		on Ex: Exception do begin
			plugin_elem_remove(plugin, e);
			Raise Exception.Create(Ex.Message);
		end;
	end;
end;

function ts_to_int(ts: string): integer;
begin
	Result := 0;
	if Assigned(ts) and length(ts) >= 5 then
		Result := StrToInt('$' + ts[4] + ts[5] + ts[1] + ts[2]);
end;

function elem_error_check(e: IInterface): boolean;
var
	i: integer;
	t: IInterface;
begin
	for i := 0 to Pred(ElementCount(e)) do begin
		t := ElementByIndex(e, i);
		if Check(t) = '' then
			continue;

		if Debug then
			AddMessage(Format('%s: elem_error_check: failed: %s: %s', [ GetFileName(t), Check(t), Path(t) ]));
		Result := false;
		Exit;
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
	sl.Sorted := True;
	sl.Duplicates := dupIgnore;

	ReportRequiredMasters(e, sl, False, True);
	for i := 0 to Pred(sl.Count) do begin
		tfile := plugin_file_resolve_existing(sl[i]);
		for j := 0 to Pred(MasterCount(tfile)) do begin
			r := MasterByIndex(tfile, j);
			rfstr := GetFileName(r);
			if not HasMaster(plugin, rfstr) then begin
				if Debug then
					AddMessage(Format('%s: Adding element master (parent): %s: %s', [GetFileName(plugin), rfstr, Name(e)]));
				AddMasterIfMissing(plugin, rfstr);
			end;
		end;

		if not HasMaster(plugin, sl[i]) then begin
			if Debug then
				AddMessage(Format('%s: Adding element master (parent): %s: %s', [GetFileName(plugin), sl[i], Name(e)]));
			AddMasterIfMissing(plugin, sl[i]);
		end;
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
	if ((flags and $80) <> 0) and ((mflags and $80) = 0) then begin
		AddMessage('Warning: disabling explicitly set "no previs" flag: ' + FullPath(e));
		SetElementNativeValues(e, 'Record Header\Record Flags', flags - $80);
	end;
end;

function elem_marker_check(e: IInterface): Boolean;
var
	flags: cardinal;
begin
	flags := GetElementNativeValues(e, 'Record Header\Record Flags');
	if (flags and $800000) <> 0 then begin
		Result := True;
		Exit;
	end;

	Result := False;
end;

function elem_deleted_check(e: IInterface): Boolean;
var
	flags: cardinal;
begin
	flags := GetElementNativeValues(e, 'Record Header\Record Flags');
	if (flags and $20) <> 0 then begin
		Result := True;
		Exit;
	end;

	Result := False;
end;

procedure elem_sync(e, r: IInterface; s: TString);
begin
	if ElementExists(e, s) then begin
		if not ElementExists(r, s) then
			Add(r, s, True);
		ElementAssign(ElementBySignature(r, s), LowInteger, ElementBySignature(e, s), False);
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

	RemoveNode(e);
end;

function cell_refr_stat_check(e: IInterface): boolean;
begin
	Result := Assigned(cell_refr_stat_first(e, false, false));
end;

function cell_refr_rvis_check(e: IInterface): boolean;
begin
	Result := Assigned(cell_refr_rvis_first(e, false, false));
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
			if elem_deleted_check(t) then begin
				b := BaseRecord(MasterOrSelf(t));
			end else begin
				b := BaseRecord(t);
			end;

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

function cell_refr_ent_filter(e: IInterface; filter: THashedStringList; ref_check, cell_check: boolean): IInterface;
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
		if elem_deleted_check(t) then begin
			b := BaseRecord(MasterOrSelf(t));
		end else begin
			b := BaseRecord(t);
		end;

		s := Signature(b);
		if (filter.indexof(s) < 0) then
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

		Result := t;
		Exit;
	end;

	Result := nil;
end;

function cell_refr_rvis_first(e: IInterface; ref_check, cell_check: boolean): IInterface;
var
	cg, rcg, r, t, b: IInterface;
	i, j, k: integer;
	s: string;
	children: array[0..1] of IInterface;
	filter: array[0..1] of THashedStringList;
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
		9: children[0] := r; //temporary
		8: children[1] := r; // persistent
		end;
	end;

	filter[0] := pc_keep_map;
	filter[1] := pv_keep_map;

	// Prioritize statics references over non-statics
	for i := 0 to Pred(length(children)) do begin
		r := children[i];
		if not Assigned(r) then
			continue;
//		AddMessage('r: ' + FullPath(r));

		for j := 0 to Pred(length(filter)) do begin
			if not Assigned(filter[i]) then
				continue;

			t := cell_refr_ent_filter(r, filter[i], ref_check, cell_check);
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

function cell_refr_stat_first(e: IInterface; ref_check, cell_check: boolean): IInterface;
var
	cg, rcg, r, t, b: IInterface;
	i, j: integer;
	s: string;
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
		9: children[0] := r; //temporary
		8: children[1] := r; // persistent
		end;

	if GroupType(r) = 8 then
		AddMessage(FullPath(r));
	end;

	filter[0] := pc_keep_map;
	filter[1] := nil;

	// Prioritize statics references over non-statics
	for i := 0 to Pred(length(children)) do begin
		r := children[i];
		if not Assigned(r) then
			continue;

//		AddMessage('r: ' + FullPath(r));

		for j := 0 to Pred(length(filter)) do begin
			if not Assigned(filter[i]) then
				continue;

			t := cell_refr_ent_filter(r, filter[i], ref_check, cell_check);
			if Assigned(t) then begin
				Result := t;
				Exit;
			end;
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
	seen.sorted := True;

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
			if seen.indexOf(key) < 0 then begin
				seen.add(key);

//				AddMessage(Format('cell_rvis_rvis_grid: %s: %s', [GetFileName(r), Name(r)]));
				tl.add(r);
			end;
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
	i, ix, iy, jx, jy, k: integer;
	x, y: integer;
	s, ws: string;
begin
	ws := cell_world_edid(e);
	rvl := cell_rvis_rvis_grid(e, RVIS_OFFSET);
	rgl := TList.create;

	for i := 0 to Pred(rvl.count) do begin
		r := ObjectToElement(rvl[i]);
		if not Assigned(r) then
			continue;

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

//				AddMessage(Format('%s: rvxy(%d,%d): %d,%d :: %s', [FullPath(r),cxy.x,cxy.y,x,y,FullPath(t)]));

				// Since the RVIS cell already occupies the first slot
				// ignore the relative 0,0 offset as it is the same cell.
				if (jx = 0) and (jy = 0) then
					continue;

				tl.add(t);
			end;
		end;

		rgl.add(tl);
	end;

	Result := rgl;
end;

function cell_filter(e: IInterface; main_allow, other_allow, interior_allow, persistent_allow: boolean): boolean;
var
	flags: cardinal;
	is_main, is_interior, is_persistent: boolean;
	ws: string;
begin
	Result := false;

	// Skip non-cells
	if Signature(e) <> 'CELL' then
		Exit;

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
		is_persistent := ((flags and $400) <> 0);
		if is_persistent and not persistent_allow then
			Exit;
	end

	Result := true;
end;

procedure stat_refr_promote(plugin: IwbFile; e: IInterface);
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

	if CopyPerCellStatic then begin
		m := MasterOrSelf(e);
		oc := OverrideCount(m);
		for i := Pred(oc) downto -1 do begin
			if i < 0 then begin
				t := m;
			end else begin
				t := OverrideByIndex(m, i);
			end;

			// Do not go past the current plugin for this element
//AddMessage('stat_refr_promote: ' + FullPath(t));
//AddMessage('stat_refr_promote: ' + FullPath(e));
			if GetLoadOrder(GetFile(t)) > GetLoadOrder(GetFile(e)) then
				continue;
			if Equals(GetFile(t), GetFile(plugin)) then
				continue;

			r := cell_refr_rvis_first(t, true, true);
//AddMessage('stat_refr_promote: r: ' + FullPath(r));
			if not Assigned(r) then continue;

			if Debug then begin
//				AddMessage(Format('%s: Copying: %s', [GetFileName(e), Name(r)]))
			end;

			// Guard against xedit corrupting CELL parents
			if not plugin_cell_find(plugin, e) then
				form_copy_safe(plugin, e, true);

			form_copy_safe(plugin, r, true);

			break;
		end;
	end;
end;

function plugin_cell_find(plugin: IwbFile; e: IInterface): Boolean;
var
	t: IInterface;
	i: integer;
begin
	for i := 0 to Pred(OverrideCount(e)) do begin
		t := OverrideByIndex(e, i);
		if Equals(GetFile(t), plugin) then begin
			Result := true;
			Exit;
		end;
	end;

	Result := false;
end;

function form_copy_safe(plugin: IwbFile; e: IInterface; nopv: boolean): IInterface;
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

				r := wbCopyElementToFile(e, plugin, False, False);
				SetElementNativeValues(r, 'Record Header\Record Flags', GetElementNativeValues(e, 'Record Header\Record Flags'));

				for i := 0 to Pred(ElementCount(e)) do begin
					t := ElementByIndex(e, i);
					if not Assigned(t) then Continue;

					s := Signature(t);
					if not Assigned(s) then Continue;

					if nopv then begin
						// If the previous deep copy failed it is extremely likely
						// it was due to these elements and they will be copied
						// from the prior override (see comment below).
						if (s = 'XPRI') or (s = 'RVIS') or (s = 'VISI') then
							Continue;
					end;

					if not ElementExists(r, s) then
						Add(r, s, True);
					ElementAssign(ElementBySignature(r, s), LowInteger, t, False);
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

// XXX: note this copies to a plugin rather than merging back into the master/override
function previs_merge(plugin: IwbFile; e, o, m: IInterface): Boolean;
var
	r, t: IInterface;
begin
	try
		// Copy overridden plugin data as a starting base
		r := wbCopyElementToFile(o, plugin, False, True);

		// Copy previs data from current element to plugin
		elem_pv_sync(e, r);

		// Ensure any 'no previs' flags are removed if master also does not have
		elem_previs_flag_clean(o, m);

		// Copy form version info
		elem_version_sync(e, r);
	except
		on Ex: Exception do begin
			plugin_elem_remove(plugin, o);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := True;
end;

function precombine_merge(plugin: IwbFile; e, o, m: IInterface): Boolean;
var
	r, t: IInterface;
begin
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

	Result := True;
end;

function precombine_split(plugin: IwbFile; e, o, m: IInterface): Boolean;
var
	r, t: IInterface;
	s: TString;
	i, j: integer;
begin
	try
		// XXX: xEdit will choke on delocalized plugins containing strings like '$Farm05Location'
		// XXX: due to it wrongly interpreting it as a hex/integer value and will also disallow copying
		// XXX: an element with busted references. Attempt a normal deepcopy first and if it does not
		// XXX: succeed then attempt an element by element copy whilst avoiding bogus XPRI data.

		if PerElementMasters then
			elem_masters_add(plugin, e);

		r := wbCopyElementToFile(e, plugin, False, True);
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

				r := wbCopyElementToFile(e, plugin, False, True);
				SetElementNativeValues(r, 'Record Header\Record Flags', GetElementNativeValues(e, 'Record Header\Record Flags'));

				for i := 0 to Pred(ElementCount(e)) do begin
					t := ElementByIndex(e, i);
					if not Assigned(t) then Continue;

					s := Signature(t);
					if not Assigned(s) then Continue;

					// If the previous deep copy failed it is extremely likely
					// it was due to these elements and they will be copied
					// from the prior override (see comment below).
					if (s = 'XPRI') or (s = 'RVIS') or (s = 'VISI') then
						Continue;

					if not ElementExists(r, s) then
						Add(r, s, True);
					ElementAssign(ElementBySignature(r, s), LowInteger, t, False);
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
		stat_refr_promote(plugin, r);
	except
		on Ex: Exception do begin
			Remove(r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := True;
end;

function init_gen(plugin: IwbFile; e, o, m: IInterface): Boolean;
var
	r: IInterface;
begin
	try
		r := form_copy_safe(plugin, e, True);

		// temp: nuke xcri/xpri
//		Remove(ElementBySignature(r, 'XCRI'));
//		Remove(ElementBySignature(r, 'XPRI'));

		// Promote static references from any containing cells to generated plugin
		stat_refr_promote(plugin, r);
	except
		on Ex: Exception do begin
			Remove(r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := True;
end;

function plugin_init_refs(t: IInterface; sl: TStringList; rmap: THashedStringList): Boolean;
var
	cell, e, r, rr, rt, rb: IInterface;
	s: array [0..1] of IInterface;
	hsl: THashedStringList;
	key, f, tfile: TString;
	idx, i, j, k, n: integer;
begin
	s[0] := GroupBySignature(t, 'STAT');
	s[1] := GroupBySignature(t, 'SCOL');

	if ((ElementCount(s[0]) <> 0) or (ElementCount(s[1]) <> 0)) then begin
		tfile := GetFileName(t);
		AddMessage(tfile + ' stat count == ' + IntToStr(ElementCount(s[0])) + ' scol count == ' + IntToStr(ElementCount(s[1])));
	end;

	// iterate over records in a plugin
	for i := 0 to Pred(length(s)) do begin
		for j := 0 to Pred(ElementCount(s[i])) do begin
			e := ElementByIndex(s[i], j);

			// ignore markers entirely
			if elem_marker_check(e) then
				continue;

			// referenced by information is available for master records only
			if not IsMaster(e) then
				continue;

			for k := 0 to Pred(ReferencedByCount(e)) do begin
				r := ReferencedByIndex(e, k);
				f := GetFileName(r);

				// Placed objects only
				if (Signature(r) <> 'REFR') then begin
					continue;
				end;

if false then begin
//				AddMessage('r: ' + FullPath(r));
				for n := 0 to Pred(ReferencedByCount(r)) do begin
					rr := ReferencedByIndex(r, n);
					AddMessage('rr: ' + FullPath(rr));
					if Signature(rr) <> 'CELL' then begin
						AddMessage('rr is not a CELL: ' + FullPath(rr));
						continue;
					end;
					cell := rr;
//					AddMessage('cell: ' + FullPath(cell));
					break;
				end;
end;

				if sl.indexOf(f) < 0 then begin
					sl.add(f);

					if Debug then begin
						AddMessage('	Referencing plugin: ' + f + ' (rcount == ' + IntToStr(ReferencedByCount(e)) + ')');
						AddMessage('	  ' + Signature(e) + ' ' + FullPath(e));
						AddMessage('	  ' + Signature(r) + ' ' + FullPath(r));
					end;
if false then begin
					for n := 0 to Pred(ReferencedByCount(r)) do begin
						rt := ReferencedByIndex(r, n);
						f := GetFileName(rt);

						AddMessage('		Referencing plugin: ' + f + ' (rcount == ' + IntToStr(ReferencedByCount(r)) + ')');
						AddMessage('	 	 ' + Signature(rt) + ' ' + FullPath(rt));
						if n > 4 then
							break;
					end;
end;

					AddMessage(' ');
				end;

if false then begin
				key := ShortName(cell);
				idx := rmap.indexOf(key);
				if idx < 0 then begin
					hsl := THashedStringList.create;
					idx := rmap.AddObject(key, hsl);
				end else begin
					hsl := ObjectToElement(rmap.Objects[idx]);
				end;

				AddMessage(Format('Adding "%s" to key "%s"', [f, key]));
				hsl.add(f);
end;
			end;
		end;
	end;

	Result := True;
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

function plugin_init(mode: TString): boolean;
var
	e, r, t, g, rr, rg, rgg, rggg, plugin: IInterface;
	sl: array[0..1] of TStringList;
	hsl, rmap: THashedStringList;
	f, tfile, pfile: TString;
	i, j, k, n: integer;
begin
	// Create a new initial plugin
//	plugin := plugin_file_resolve(nil, 0, mode);
//	if not Assigned(plugin) then begin
//		Result := StopOnError; Exit;
//	end;

//	pfile := GetFileName(plugin);
	sl[0] := TStringList.create;
	sl[0].Sorted := True;
	sl[1] := TStringList.create;
	sl[1].Sorted := False;

	rmap := THashedStringList.create;
	rmap.Duplicates := dupIgnore;

	for i := 0 to Pred(FileCount) do begin
		t := FileByIndex(i);
		tfile := GetFileName(t);

//		if tfile = pfile then
//			continue;
		if Pos('.Hardcoded.', tfile) <> 0 then
			continue;

		// Check if references should be built for plugin
		if ContainerStates(t) and (1 shl csRefsBuild) = 0 then begin
			// Special hack for the main master
			if tfile = 'Fallout4.esm' then begin
				sl[0].Add(tfile);
			end else begin
				AddMessage(Format('Building reference info: %s', [tfile]));
				BuildRef(t);
			end;
		end;

		plugin_init_refs(t, sl[0], rmap);
	end;

	for i := to Pred(rmap.count) do begin
		hsl := ObjectToElement(rmap.Objects[i]);
		AddMessage(Format('rmap[%d] count == %d', [i, hsl.count]));
	end;

	// sl[0] is sorted to speed up indexOf checks, produce another list
	// sl[1] that is ordered by plugin load order.
	j := 0;
	for i := 0 to Pred(FileCount) do begin
		t := FileByIndex(i);
		tfile := GetFileName(t);

		if sl[0].indexOf(tfile) < 0 then
			continue;
//		if not (HasGroup(t, 'CELL') or HasGroup(t, 'WRLD')) then
//			continue;

		AddMessage(Format('Candidate[%d]: %s (pre-add)', [j, tfile]));
		inc(j);

		sl[1].AddObject(tfile, t);
	end;

	AddMessage('s[1] length == ' + IntToStr(sl[1].Count));

	k := 0;
	for i := 0 to Pred(sl[1].Count) do begin
		t := ObjectToElement(sl[1].Objects[i]);
		tfile := GetFileName(t);
		k := k + RecordCount(t);
		AddMessage(Format('Candidate[%d]: %s (nrec == %d, nrec_total == %d)', [i, tfile, RecordCount(t), k]));

		if i <> 14 then
			continue;

		// WRLD
		//	Commonwealth
		//		CELL
		//		Block -1, -1
		//			Sub-Block -1, -1
		//				CELL
		//
		g := GroupBySignature(t, 'WRLD');
		if Assigned(g) then begin
			group_desc(g, nil);
			AddMessage(' ');
		end;
	end;

	sl[0].free;
	sl[1].free;

	Result := True;
end;

procedure plugin_cell_rvis_master_add(e: IInterface; require_static: boolean);
var
	rgl, tl: TList;
	m, t, r, rvis, plugin: IInterface;
	cxy: TwbGridCell;
	rvx, rvy, i, j, k: integer;
	f: string;
begin
	// Non-persistent exterior cells only
	if not cell_filter(e, true, true, false, false) then
		Exit;

	plugin := GetFile(e);
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
				if GetLoadOrder(GetFile(r)) >= GetLoadOrder(plugin) then
					break;

				// Account for more than just stat objects as previs
				// takes other things into account for physics.
				if require_static and not cell_refr_rvis_check(r) then
					continue;

				// Check for masters that would be added but are not
				// present in the plugin to indicate what would be
				// added. XXX: Try this with and without STAT only?
				if not HasMaster(plugin, GetFileName(r)) then begin
					AddMessage(Format('VIS: [%d][%d][%d] %s needs master: %s (rvis: %d,%d :: e: %s :: r: %s)', [i,j,k+1,GetFileName(plugin),GetFileName(r),rvx,rvy,Name(e),Name(r)]));
				end;
				plugin_master_add(plugin, r, true);

//				AddMessage(Format('[%d][%d][%d] %s', [i,j,k+1,FullPath(r)]));
			end;
		end;

		tl.free;
	end;

	rgl.free;
end;

procedure plugin_master_cell_rvis_clean(e: IInterface; main_allow, other_allow, interior_allow: boolean);
var
	tl, rgl: TList;
	cxy: TwbGridCell;
	t, r, m: IInterface;
	i, j, k, oc: integer;
	keep, remove: boolean;
begin
	if (Signature(e) <> 'CELL') then
		Exit;

	rgl := nil;
	remove := true;
	if cell_filter(e, main_allow, other_allow, interior_allow, false) then
		rgl := cell_rvis_cell_grid(e);

	if Assigned(rgl) then begin
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
					if k < 0 then begin
						r := m;
					end else begin
						r := OverrideByIndex(m, k);
					end;

//					cxy := GetGridCell(r);
//					AddMessage(Format('%d,%d %s', [cxy.x,cxy.y,FullPath(r)]));

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
					if GetLoadOrder(GetFile(r)) > GetLoadOrder(GetFile(e)) then begin
//						AddMessage('remove = false: ' + FullPath(r));
						remove := false;
						break;
					end;

//					// XXX: Check for cells that only have things RVIS cares about?
//					if cell_refr_rvis_check(r) then begin
//						continue;
				end;
			end;

			tl.free;
		end;

		rgl.free;
	end else if not IsWinningOverride(e) and cell_filter(e, main_allow, other_allow, interior_allow, false) then begin
		remove := false;
	end;

	if remove then begin
		AddMessage(Format('%s: Removing: %s', [GetFileName(e), Name(e)]));
		cell_remove(e);
//	end else begin
//		cell_queue.add(e);
	end;

end;

procedure plugin_cell_stat_master_add(e: IInterface; require_static: boolean);
var
	plugin, tfile: IwbFile;
	m, t, r: IInterface;
	i, j: integer;
begin
	plugin := GetFile(e);
	m := MasterOrSelf(e);

	if Equals(e, m) then
		Exit;

	// Non-persistent cells only
	if not cell_filter(e, true, true, true, false) then
		Exit;

	// Find this actual element and consider it the highest override so
	// that additional overrides in the load order are ignored. This is
	// done so that the masters added to the plugin represent masters
	// which have been overridden only from the perspective of the
	// plugin being modified.
	for i := 0 to Pred(OverrideCount(m)) do begin
		t := OverrideByIndex(m, i);
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

		plugin_master_add(plugin, t, true);
	end;
end;

procedure plugin_navm_clean(e: IInterface);
var
	s: string;
begin
	s := Signature(e);
	if (s = 'NAVM') or (s = 'LAND') then begin
		AddMessage(Format('%s: Removing: %s', [GetFileName(e), Name(e)]));
		RemoveNode(e);
	end;
end;

procedure plugin_master_refr_clean(e: IInterface; main_allow, other_allow, interior_allow: boolean);
var
	b: IInterface;
	s, ws, gl, fstr: string;
	flags: cardinal;
	remove: boolean;
begin
	remove := false;
	s := Signature(e);

	// XXX: deal with deleted references and/or deleted references within rvis|stat_first calls

	// XXX: made into else if, double check
	if (pc_keep_map.indexof(s) < 0) and (pv_keep_map.indexof(s) < 0) then begin
// XXX: Do not remove top level GRUPs for now
		if Assigned(ElementExists(e, 'Cell')) then
			remove := true;
	end else if (s = 'REFR') then begin
// XXX: Check for initially disabled as well?
		if elem_deleted_check(e) then begin
			b := BaseRecord(MasterOrSelf(e));
		end else begin
			b := BaseRecord(e);
		end;

		s := Signature(b);
		if (pc_keep_map.indexof(s) < 0) and (pv_keep_map.indexof(s) < 0) then begin
			remove := true;
		end;
	end else if (s = 'WRLD') then begin
		ws := GetElementEditValues(e, 'EDID');
		if not other_allow and (ws <> 'Commonwealth') then begin
			remove := true;
		end;
	end else if (s = 'CELL') then begin
		// Non-persistent cells only
		if not cell_filter(e, main_allow, interior_allow, other_allow, false) then begin
			remove := true;
		end else if not cell_refr_rvis_check(e) then begin
			remove := true;
//		end else if not cell_refr_stat_check(e) then begin
//			remove := true;
		end;
	end;

	if remove then begin
		if s = 'CELL' then begin
			AddMessage(Format('%s: Removing: %s', [GetFileName(e), Name(e)]));
			cell_remove(e);
		end else begin
			AddMessage(Format('%s: Removing: %s', [GetFileName(e), Name(e)]));
			RemoveNode(e);
		end;
	end else if s = 'CELL' then begin
		// Add cell for processing of masters (and possibly rvis cells) later
//		cell_queue.add(e);
	end;

end;

procedure master_clean(e: IInterface; main_allow, other_allow, interior_allow, persistent_allow, refr_clean, rvis_clean: boolean);
var
	editable: boolean;
begin
	editable := IsEditable(e);

	if Signature(e) = 'CELL' then begin
		if editable and refr_clean then
			plugin_master_refr_clean(e, main_allow, other_allow, interior_allow);
		if editable and rvis_clean then
			plugin_master_cell_rvis_clean(e, main_allow, other_allow, interior_allow);
	end else begin
		if editable then
//			plugin_navm_clean(e);
		Exit;
	end;

	// General add masters for all non-persistent cells
// XXX: use boolean for winning override
//	if (win_allow or not isWinningOverride(e)) and cell_filter(e, main_allow, other_allow, interior_allow, persistent_allow) then begin
	if cell_filter(e, main_allow, other_allow, interior_allow, persistent_allow) then begin
// XXX: only add if has pc/pv refrs?
		cell_queue.add(e);
	end else if editable then begin
		AddMessage(Format('%s: Removing: %s', [GetFileName(e), Name(e)]));
		cell_remove(e);
	end;
end;

procedure master_add(e: IInterface; main_allow, other_allow, interior_allow, persistent_allow, promote: boolean);
var
	editable: boolean;
begin
	editable := IsEditable(e);

	if Signature(e) <> 'CELL' then begin
		if editable then
//			plugin_navm_clean(e);
		Exit;
	end;

	// General add masters for all non-persistent cells
	if cell_filter(e, main_allow, other_allow, interior_allow, persistent_allow) then begin
		if editable and promote and not cell_refr_rvis_check(e) then
			stat_refr_promote(GetFile(e), e);

// XXX: only add if has pc/pv refrs?
		cell_queue.add(e);
	end else if editable then begin
		AddMessage(Format('%s: Removing: %s', [GetFileName(e), Name(e)]));
		cell_remove(e);
	end;
end;

function Process(e: IInterface): integer;
var
	o, m, t, r, g, plugin: IInterface;
	f, s, cs, mode: TString;
	efile, tfile: string;
	idx, i, j, oc, oc_sub: integer;
	ts, pcmb_max, visi_max: integer;
	merge: boolean;
	xy : TwbGridCell;
begin

//	mode := 'init_master_refr_clean';
//	mode := 'init_master_cell_rvis_clean';

//	mode := 'init_cell_all_master_clean';
//	mode := 'init_cell_exts_master_clean';
//	mode := 'init_cell_main_master_clean';
	mode := 'init_cell_ints_master_clean';
//	mode := 'init_cell_other_master_clean';

//	mode := 'init_cell_all_master_add';
//	mode := 'init_cell_exts_master_add';
//	mode := 'init_cell_main_master_add';
//	mode := 'init_cell_ints_master_add';
//	mode := 'init_cell_other_master_add';

//	mode := 'init_alt';
//	mode := 'init';
//	mode := 'precombine_merge';
//	mode := 'precombine_split';
//	mode := 'previs_merge';
//	mode := 'previs_split';
//	mode := 'final';
//	mode := 'stats';

	// direct cleaning calls

	if mode = 'init_master_refr_clean' then begin
		// Nuke anything not needed for precombines (or previs)
		// XXX: test differences for cleaned vs uncleaned, do not add masters
		plugin_master_refr_clean(e, true, true, true);

		Exit;
	end;

	if mode = 'init_master_cell_rvis_clean' then begin
		plugin_master_cell_rvis_clean(e, true, true, true);

		Exit;
	end;

	if Signature(e) <> 'CELL' then
		Exit;

	// master clean

	if mode = 'init_cell_all_master_clean' then begin
		if not Assigned(plugin_final) then
			plugin_final := plugin_file_resolve('all', 0, 'final');
		master_clean(e, true, true, true, false, false, false);

		Exit;
	end;

	if mode = 'init_cell_exts_master_clean' then begin
		if not Assigned(plugin_final) then
			plugin_final := plugin_file_resolve('exts', 0, 'final');
		master_clean(e, true, true, false, false, false, false);
		Exit;
	end;

	if mode = 'init_cell_ints_master_clean' then begin
		if not Assigned(plugin_final) then
			plugin_final := plugin_file_resolve('ints', 0, 'final');
		master_clean(e, false, false, true, false, false, false);
		Exit;
	end;

	if mode = 'init_cell_main_master_clean' then begin
		if not Assigned(plugin_final) then
			plugin_final := plugin_file_resolve('main', 0, 'final');
		master_clean(e, true, false, false, false, false, false);
		Exit;
	end;

	if mode = 'init_cell_other_master_clean' then begin
		if not Assigned(plugin_final) then
			plugin_final := plugin_file_resolve('other', 0, 'final');
		master_clean(e, false, true, false, false, false, false);
		Exit;
	end;

	// master add

	if mode = 'init_cell_all_master_add' then begin
		master_add(e, true, true, true, false, true);
		Exit;
	end;

	if mode = 'init_cell_exts_master_add' then begin
		master_add(e, true, true, false, false, true);
		Exit;
	end;

	if mode = 'init_cell_ints_master_add' then begin
		master_add(e, false, false, true, false, true);
		Exit;
	end;

	if mode = 'init_cell_main_master_add' then begin
		master_add(e, true, false, false, false, true);
		Exit;
	end;

	if mode = 'init_cell_other_master_add' then begin
		master_add(e, false, true, false, false, true);
		Exit;
	end;

Exit;

	if mode = 'stats' then begin
		plugin_cell_stat_master_add(e, true);
		plugin_cell_rvis_master_add(e, true);
		Exit;
	end;

	if mode = 'init_alt' then begin
		Result := plugin_init(mode);
		Exit;
	end;

	if mode = 'init' then begin
		Result := plugin_cell_stat_master_add(e, true);
		Exit;
	end;

	// Non-persistent cells only
	if not cell_filter(e, true, true, true, false) then
		Exit;

	// operate on the last override
//	e := WinningOverride(e);
	if mode = 'init' then
		e := WinningOverride(e);

	efile := GetFileName(e);

	// skip if this is a plugin file generated by this script
	if (Pos(InitFileSuffix, efile) <> 0) then begin
		if Debug then AddMessage('Element file contains InitFileSuffix: ' + FullPath(e));
		Exit;
	end else if (Pos(PrecombineFileSuffix, efile) <> 0) then begin
		if Debug then AddMessage('Element file contains PrecombineFileSuffix: ' + FullPath(e));
		Exit;
	end else if (Pos(PrevisFileSuffix, efile) <> 0) then begin
		if Debug then AddMessage('Element file contains PrevisFileSuffix: ' + FullPath(e));
		Exit;
	end;

	m := MasterOrSelf(e);
	oc := OverrideCount(m);
	if (mode <> 'init') and (oc = 0 or Equals(e, m)) then
		Exit;

if false then begin
	// Find this actual element and consider it the highest override so
	// that additional overrides are ignored.
	for oc := OverrideCount(m) downto 0 do begin
		if oc = 0 then Exit;

		t := OverrideByIndex(m, oc - 1);
		if Equals(e, t) then break;
	end;
end;

	if Debug then begin
		for i := 0 to Pred(oc) do begin
			t := OverrideByIndex(m, i);
			AddMessage(Format('%s: override[%d] == %s', [GetFileName(e), i, GetFileName(t)]));
		end;
	end;

	// XXX: Reexamine if this is still needed
	// When in precombine or previs mode, Ensure winning override is not
	// the same as the override used for copying authoritative XPRI data.
	// In other words, ignore the plugins created by the script itself.
	if mode = 'init' then begin
		oc_sub := 0;
	end else begin
		oc_sub := 1;
	end;

	// | [0] master | [1] override | [2] *override* | [3] element | ...
	o := m;
	ts := 0;
	pcmb_max := 0;
	visi_max := 0;
	for i := Pred(oc - oc_sub) downto 0 do begin
		t := OverrideByIndex(m, i);
		s := GetFileName(t);

		// For overrides which have mixed timestamps for the same cell
		// attempt to figure out the most recent one. This sometimes
		// happens when generating so-called sharded data for the same
		// plugin when using CKs command line options.
		if ((mode = 'precombine_merge') or (mode = 'precombine_split')) and ElementExists(t, 'PCMB') then begin
			ts := ts_to_int(GetElementEditValues(t, 'PCMB'));
			if ts = 0 or ts > pcmb_max then begin
				if pcmb_max <> 0 then
					AddMessage('Plugin with greater PCMB: ' + s + ' (ts == ' + IntToHex(ts, 8) + ')');
				pcmb_max := ts;
				e := t;
			end;
		end else if ((mode = 'previs_merge') or (mode = 'previs_split')) and ElementExists(t, 'VISI') then begin
			ts := ts_to_int(GetElementEditValues(t, 'VISI'));
			if ts = 0 or ts > visi_max then begin
				if visi_max <> 0 then
					AddMessage('Plugin with greater VISI: ' + s + ' (ts == ' + IntToHex(ts, 8) + ')');
				visi_max := ts;
				e := t;
			end
		end;

		// XXX: consider allowing precombine_merge files in previs mode
		if Pos('precombine_split', s) <> 0 then
			continue;
		if Pos('previs_split', s) <> 0 then
			continue;

		o := t;
		break;
	end;

AddMessage(Format('e: %s', FullPath(e)));
AddMessage(Format('o: %s', FullPath(o)));

Exit;

	merge := (MergeIntoOverride and IsEditable(o));
if false then begin
	if Debug then begin
		if merge then begin
			AddMessage(Format('%s: m == %s, o == %s, oc == %d, merge == 1', [GetFileName(e), GetFileName(m), GetFileName(o), oc]));
		end else begin
			AddMessage(Format('%s: m == %s, o == %s, oc == %d, merge == 0', [GetFileName(e), GetFileName(m), GetFileName(o), oc]));
		end;
	end;
end;

	if merge then begin
		plugin := GetFile(o);
	end else begin
		plugin := plugin_resolve(e, o, m, mode);
	end;

	if not Assigned(plugin) then begin
		Result := StopOnError; Exit;
	end;

	try
		if mode = 'init' then begin
			init_gen(plugin, e, o, m);
		end else if mode = 'precombine_merge' then begin
			precombine_merge(plugin, e, o, m);
		end else if mode = 'precombine_split' then begin
			precombine_split(plugin, e, o, m);
		end else if mode = 'previs_merge' then begin
			previs_merge(plugin, e, o, m);
		end else if mode = 'final' then begin
			precombine_previs_final(plugin, e);
		end;
	except
		on Ex: Exception do begin
			AddMessage('Failed to copy: ' + FullPath(e));
			AddMessage('        reason: ' + Ex.Message);

			Result := StopOnError; Exit;
		end;
	end;
end;

function Finalize: integer;
var
	t, r, plugin: IInterface;
	last, s: string;
	i, j, k, idx: integer;
	hl: THashedStringList;
	tl, sl: TStringList;
	sl_out: array[0..255] of TStringList;
	s_out: array[0..255] of string;
	rc, rct: integer;
begin
//	if mode = 'init' then begin
//		for i := 0 to 255 do begin
//			plugin := plugin_map[i];
//			if not Assigned(plugin) then Continue;
//
//			SortMasters(plugin);
//			CleanMasters(plugin);
//		end;
//	end;

if false then begin
	for i := 0 to Pred(length(rmap)) do begin
		AddMessage(' ');
		if i = 0 then begin
			AddMessage('FORWARD:');
		end else if i = 1 then begin
			AddMessage('REVERSE:');
		end else begin
			AddMessage('COMBINED:');
		end;
		AddMessage(' ');

		hl := rmap[i];
		tl := TStringList.create;
		tl.Delimiter := ':';
		tl.StrictDelimiter := True;

		AddMessage('rmap[i].count == ' + IntToStr(hl.count));
		for j := 0 to Pred(hl.count) do begin
			t := ObjectToElement(hl.Objects[j]);
			tl.DelimitedText := hl[j];

			idx := GetLoadOrder(GetFile(t));
			if not Assigned(sl_out[idx]) then
				sl_out[idx] := TStringList.create;

			if i > 1 then begin
				sl_out[idx].add(hl[j]);
			end else begin
				sl_out[idx].add(tl[1]);
			end;
		end;

		tl.free;

		AddMessage(' ');
		for j := 0 to Pred(FileCount) do begin
			sl := sl_out[j];
			sl_out[j] := nil;

			if not Assigned(sl) then
				continue;

			t := FileByLoadOrder(j);
			for k := 0 to Pred(sl.count) do begin
				r := plugin_file_resolve_existing(sl[k]);
				if Assigned(r) then begin
					AddMessage(Format('[%d] rmap[%d]: %s :: %s (reccnt: %d :: %d)', [j, k, GetFileName(t), sl[k], RecordCount(t), RecordCount(r)]));
				end else begin
					AddMessage(Format('[%d] rmap[%d]: %s :: %s (reccnt: %d)', [j, k, GetFileName(t), sl[k], RecordCount(t)]));
				end;
			end;
			AddMessage(' ');

			sl.free;
		end;

		rmap[i].free;
	end;

	AddMessage(' ');
	AddMessage('CROSS-COMBINED:');
	AddMessage(' ');
	k := 0;
	for i := 0 to Pred(length(cmap)) do begin
		hl := cmap[i];
		if not Assigned(hl) then
			continue;

		rct := 0;
		for j := 0 to Pred(hl.count) do begin
			t := ObjectToElement(hl.Objects[j]);
			idx := GetLoadOrder(GetFile(t));
			s_out[idx] := hl[j];
			rct := rct + RecordCount(GetFile(t));
		end;

		t := FileByLoadOrder(i);
		if rct >= 2000000 then AddMessage(Format('cluster[%d] cmap[%d]: %s (%d)', [k,i,GetFileName(t),rct]));

		for j := 0 to Pred(length(s_out)) do begin
			s := s_out[j];
			s_out[j] := nil;

			if not Assigned(s) then
				continue;

			t := plugin_file_resolve_existing(s);
			rc := RecordCount(t);

			if rct >= 2000000 then AddMessage(Format('cluster[%d] cmap[%d][%d]: %s (%d)', [k,i,j,s,rc]));
		end;
		AddMessage(' ');

		hl.free;
		inc(k);
	end;
	AddMessage(' ');
end;

if true then begin
	AddMessage(Format('Adding cell masters for %d cells', [ cell_queue.count ]));
	for i := 0 to Pred(cell_queue.count) do begin
		t := ObjectToElement(cell_queue[i]);
		if not Assigned(t) then continue;

		if Assigned(plugin_final) then begin
			if Equals(t, WinningOverride(t)) then begin
				stat_refr_promote(plugin_final, t);
				plugin_master_add(plugin_final, t, true);
			end;
		end;

//		if Debug then AddMessage(Format('cell_queue[%d]: %s', [i,FullPath(t)]));
		plugin_cell_stat_master_add(t, true);

		if ((i + 1 = cell_queue.count) or ((i + 1) mod (trunc(cell_queue.count / 10) + 1) = 0)) then
			AddMessage(Format('Remain: %d cells (%d/%d)', [ cell_queue.count - (i + 1), i + 1, cell_queue.count ]));
	end;

	AddMessage(Format('Adding vis grid masters for %d cells', [ cell_queue.count ]));
	for i := 0 to Pred(cell_queue.count) do begin
		t := ObjectToElement(cell_queue[i]);
		if not Assigned(t) then continue;

//		if Debug then AddMessage(Format('cell_queue[%d]: %s', [i,FullPath(t)]));
		plugin_cell_rvis_master_add(t, true);

		if ((i + 1 = cell_queue.count) or ((i + 1) mod (trunc(cell_queue.count / 10) + 1) = 0)) then
			AddMessage(Format('Remain: %d cells (%d/%d)', [ cell_queue.count - (i + 1), i + 1, cell_queue.count ]));
	end;

end;

	cell_queue.free;
	cell_cache.free;

end;

end.

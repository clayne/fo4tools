{
	1. Split precombines into separate plugins based on their master.
	2. Recombine precombine/previs of loaded plugins into a final plugin.
}

unit FO4_Precombined_Split;
const
	Debug = True;
	StopOnError = True;
	VersionInc = False;		// Not implemented
	ConflictOnly = False;		// Not implemented
	MergeIntoOverride = False;
	CopyPerCellStatic = True;
	PerElementMasters = True;
	InitFileBase = 'pcv';
	InitFileSuffix = 'init';
	PrevisFileBase = 'pcv';
	PrevisFileSuffix = 'previs_final';
	PrecombineFileSuffix = 'precombine_merge';
	PluginSuffix = 'esp';
	MaxFileAttempts = 8;
var
	// Elements to keep from the most immediate plugin being overridden
	plugin_map: array [0..255] of IInterface;
	pc_sig_tab: array [0..1] of TString;
	pv_sig_tab: array [0..2] of TString;

function Initialize: integer;
begin
	// Precombine specific signatres
	pc_sig_tab[0] := 'XCRI';
	pc_sig_tab[1] := 'PCMB';

	// Previs specific signatures
	pv_sig_tab[0] := 'XPRI';
	pv_sig_tab[1] := 'RVIS';
	pv_sig_tab[2] := 'VISI';
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

function plugin_file_resolve(ofstr: TString; idx: integer; mode: TString): IInterface;
var
	plugin: IInterface;
	b, s, pfile: TString;
	i: integer;
begin
	// Attempt to locate existing plugin for the same file or create a new one
	for i := idx to Pred(idx + MaxFileAttempts) do begin
		if mode = 'precombine' then begin
			b := ofstr;

			if i = 0 then begin	s := PrecombineFileSuffix;
			end else begin		s := PrecombineFileSuffix + '.' + IntToStr(i);
			end;
		end else if mode = 'previs' then begin
			b := PrevisFileBase;

			if i = 0 then begin	s := PrevisFileSuffix;
			end else begin		s := PrevisFileSuffix + '.' + IntToStr(i);
			end;
		end else if mode = 'init' then begin
			b := InitFileBase;

			if i = 0 then begin	s := InitFileSuffix;
			end else begin		s := InitFileSuffix + '.' + IntToStr(i);
			end;
		end else begin
			Exit;
		end;

		pfile := b + '.' + s + '.' + PluginSuffix;
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
	t, tfile, ofile, plugin: IInterface;
	s, pfile, mfstr, ofstr: TString;
	idx, i, j: integer;
begin
	// plugin index in plugin_map is based on the load order index of the overridden plugin
	ofile := GetFile(o);
	idx := GetLoadOrder(ofile);
	plugin := plugin_map[idx];
	if Assigned(plugin) then begin
		Result := plugin; Exit;
	end;

	// Master and immediately preceeding master (if any) of the element being processed
	ofstr := GetFileName(ofile);
	plugin := plugin_file_resolve(ofstr, 0, mode);
	plugin_map[idx] := plugin;

	if Debug then AddMessage('plugin_resolve: processing for ' + ofstr);

	try
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

procedure elem_masters_add(plugin: IwbFile; e: IInterface);
var
	sl: TStringList;
	i: integer;
begin
	sl := TStringList.create;
	sl.Sorted := True;
	sl.Duplicates := dupIgnore;

	ReportRequiredMasters(e, sl, False, True);
	for i := 0 to Pred(sl.Count) do begin
		if Debug then AddMessage('Element requires master: ' + sl[i]);
		AddMasterIfMissing(plugin, sl[i]);
	end;

	sl.free;
end;

procedure elem_previs_flag_check(e, m: IInterface);
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

procedure elem_version_sync(e, r: IInterface);
begin
	SetFormVersion(r, GetFormVersion(e));
	SetFormVCS1(r, GetFormVCS1(e));
	SetFormVCS2(r, GetFormVCS2(e));
end;

function previs_merge(plugin: IwbFile; e, o, m: IInterface): Boolean;
var
	r, t: IInterface;
	s: string;
	i: integer;
begin
	try
		// Copy overridden plugin data as a starting base
		r := wbCopyElementToFile(o, plugin, False, True);

		// Copy previs data from current element to plugin
		for i := 0 to Pred(length(pv_sig_tab)) do begin
			s := pv_sig_tab[i];
			elem_sync(e, r, s);
		end;

		elem_version_sync(e, r);
	except
		on Ex: Exception do begin
			Remove(r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := True;
end;

function precombine_merge(plugin: IwbFile; e, o, m: IInterface): boolean;
var
	r, t: IInterface;
	s: TString;
	i, j: integer;
	flags, mflags: cardinal;
begin
	try
		if PerElementMasters then
			elem_masters_add(plugin, e);

		// Merge precombine data from current element to overridden plugin
		for i := 0 to Pred(length(pc_sig_tab)) do begin
			s := pc_sig_tab[i];
			elem_sync(e, o, s);
		end;

		elem_previs_flag_check(o, m);
		elem_version_sync(e, o);
	except
		on Ex: Exception do begin
			Raise Exception.Create(Ex.Message);
		end;
	end;
end;

function precombine_split(plugin: IwbFile; e, o, m: IInterface): boolean;
var
	r, t: IInterface;
	a: array[0..1] of IInterface;
	s: TString;
	i, j: integer;
	flags, mflags: cardinal;
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
				if PerElementMasters then
					elem_masters_add(plugin, e);

				r := wbCopyElementToFile(e, plugin, False, False);
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
		for i := 0 to Pred(length(pv_sig_tab)) do begin
			s := pv_sig_tab[i];
			elem_sync(o, r, s);
		end;

		elem_previs_flag_check(r, m);
		elem_version_sync(e, r);
	except
		on Ex: Exception do begin
			Remove(r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	try
		// Grab the 1st refr in the cell (from the override or master) and dupe as an override
		// This is purely to get -generateprevisdata or -generateprecombined to generate data
		// for the cell without actually duplicating the entire plugin being overridden. The
		// reason for this is that the automated commands will only generate data for cells
		// which define a REFR. It is not enough to simply override the CELL itself. Once
		// data is generated these duplicated REFRs are no longer needed and will not be used
		// in the final generated plugin containing both precombine and previs data.

		if CopyPerCellStatic then begin
			a[0] := o; a[1] := m;
			for i := 0 to Pred(length(a)) do begin
				t := cell_refr_first(a[i]);
				if not Assigned(t) then continue;

				wbCopyElementToFile(t, plugin, False, True);
				break;
			end;
		end;
	except
		on Ex: Exception do begin
			Remove(r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := True;
end;

function plugin_init_refs(t: IInterface; sl: TStringList): Boolean;
var
	e, r, rt, rb: IInterface;
	s: array [0..1] of IInterface;
	f, tfile: TString;
	i, j, k, n: integer;
	flags: cardinal;
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
			flags := GetElementNativeValues(e, 'Record Header\Record Flags');
			if (flags and $800000) <> 0 then
				continue;

			// referenced by information is available for master records only
			if not IsMaster(e) then
				continue;

			for k := 0 to Pred(ReferencedByCount(e)) do begin
				r := ReferencedByIndex(e, k);
				f := GetFileName(r);

				if not (Signature(r) = 'REFR') then
					continue;

				if sl.indexOf(f) < 0 then begin
					if Debug then begin
						AddMessage('	Referencing plugin: ' + f + ' (rcount == ' + IntToStr(ReferencedByCount(e)) + ')');
						AddMessage('	  ' + Signature(e) + ' ' + FullPath(e));
						AddMessage('	  ' + Signature(r) + ' ' + FullPath(r));
					end;
					sl.Add(f);

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

					AddMessage('');
				end;
			end;
		end;
	end;

	Result := True;
end;

function cell_refr_first(e: IInterface): IInterface;
var
	cg, rcg, r, t: IInterface;
	i, j: integer;
begin
	cg := ChildGroup(e);
	if not Assigned(cg) then
		Exit;
	AddMessage('cg: ' + FullPath(cg));

	for i := 0 to Pred(ElementCount(cg)) do begin
		r := ElementByIndex(cg, i);
		if Pos('Temporary Children', Name(r)) = 0 then
			continue;

		AddMessage('r: ' + FullPath(r));

		for j := 0 to Pred(ElementCount(r)) do begin
			t := ElementByIndex(r, j);
			if Signature(t) <> 'REFR' then
				continue;

			AddMessage('t: ' + FullPath(t));
			Result := t;
			Exit;
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

function plugin_init(mode: TString): boolean;
var
	e, r, t, g, rr, rg, rgg, rggg, plugin: IInterface;
	sl: array[0..1] of TStringList;
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

	for i := 0 to Pred(FileCount) do begin
		t := FileByIndex(i);
		tfile := GetFileName(t);

//		if tfile = pfile then
//			continue;
		if Pos('.Hardcoded.', tfile) <> 0 then
			continue;

		if ContainerStates(t) and (1 shl csRefsBuild) = 0 then begin
			// Special hack for the main master
			if tfile = 'Fallout4.esm' then begin
				sl[0].Add(tfile);
			end else begin
				AddMessage(Format('Building reference info: %s', [tfile]));
				BuildRef(t);
			end;
		end;

		plugin_init_refs(t, sl[0]);
	end;

	j := 0;
	for i := 0 to Pred(FileCount) do begin
		t := FileByIndex(i);
		tfile := GetFileName(t);

		if sl[0].indexOf(tfile) < 0 then
			continue;
//		if not (HasGroup(t, 'CELL') or HasGroup(t, 'WRLD')) then
//			continue;

//		AddMessage(Format('Candidate[%d]: %s (pre-add)', [j, tfile]));
//		inc(j);

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
			AddMessage('');
		end;
	end;

if false then begin

	for i := 20 to Pred(sl[1].Count) do begin
		plugin := plugin_file_resolve(nil, i, mode);
		if not Assigned(plugin) then begin
			Result := StopOnError; Exit;
		end;

		k := 0;
		for j := 0 to Pred(sl[1].Count) do begin
			t := ObjectToElement(sl[1].Objects[j]);
			tfile := GetFileName(t);
			k := k + RecordCount(t);
			AddMessage(Format('Candidate[%d]: %s (nrec == %d, nrec_total == %d)', [j, tfile, RecordCount(t), k]));

			if j <= i then begin
				AddMasterIfMissing(plugin, tfile);
			end else begin
				break;
			end;
		end;

	end;

end;

	sl[0].free;
	sl[1].free;

	Result := True;
end;

function Process(e: IInterface): integer;
var
	o, m, t, g, plugin: IInterface;
	s, mode: TString;
	nv: string;
	i, j, oc: integer;
	ts, pcmb_max, visi_max: integer;
	merge: boolean;
begin


//	mode := 'init';
	mode := 'precombine';
//	mode := 'previs';

	if mode = 'init' then begin
		Result := plugin_init(mode);
		Exit;
	end;

	// operate on the last override
//	e := WinningOverride(e);

	// skip if this is a plugin file generated by this script
	if (Pos(PrecombineFileSuffix, GetFileName(e)) <> 0) then begin
		if Debug then AddMessage('Element file contains PrecombineFileSuffix');
		Exit;
	end else if (Pos(PrevisFileSuffix, GetFileName(e)) <> 0) then begin
		if Debug then AddMessage('Element file contains PrevisFileSuffix');
		Exit;
	end;

	// Skip non-cells
	if Signature(e) <> 'CELL' then
		Exit;

	// XXX: check existing generated precombined plugins for cells without precombines
	// XXX: but possibly with XPRI data (or vice versa)
	// Skip cells without precombination
	if not (ElementExists(e, 'XCRI') or ElementExists(e, 'PCMB')) then begin
		// XXX: Clean this up
		if mode <> 'previs' then
			Exit;
		if not (ElementExists(e, 'XPRI') or ElementExists(e, 'VISI') or ElementExists(e, 'RVIS')) then
			Exit;
	end;

	m := Master(e);
	oc := OverrideCount(m);
	if (oc = 0 or Equals(e, m)) then
		Exit;

	// Find this actual element and consider it the highest override so
	// that additional overrides are ignored.
	for oc := OverrideCount(m) downto 0 do begin
		if oc = 0 then Exit;

		t := OverrideByIndex(m, oc - 1);
		if Equals(e, t) then break;
	end;

	if Debug then begin
		for i := 0 to Pred(oc) do begin
			t := OverrideByIndex(m, i);
			AddMessage(Format('override[%d] == %s', [i, GetFileName(t)]));
		end;
	end;

	// XXX: precombines: ensure last override is never used (change for loop counter?)
	// | [0] master | [1] override | [2] *override* | [3] element | ...
	o := m;
	ts := 0;
	pcmb_max := 0;
	visi_max := 0;
	for i := Pred(oc - 1) downto 0 do begin
		t := OverrideByIndex(m, i);
		s := GetFileName(t);

		if (mode = 'precombine') and ElementExists(t, 'PCMB') then begin
			nv := GetElementEditValues(t, 'PCMB');
			if Assigned(nv) and length(nv) >= 5 then
				ts := StrToInt('$' + nv[4] + nv[5] + nv[1] + nv[2]);

			if ts = 0 or ts > pcmb_max then begin
				if pcmb_max <> 0 then
					AddMessage('Plugin with greater PCMB: ' + s + ' (ts == ' + IntToHex(ts, 8) + ')');
				pcmb_max := ts;
				e := t;
			end;
		end else if (mode = 'previs') and ElementExists(t, 'VISI') then begin
			nv := GetElementEditValues(t, 'VISI');
			if Assigned(nv) and length(nv) >= 5 then
				ts := StrToInt('$' + nv[4] + nv[5] + nv[1] + nv[2]);

			if ts = 0 or ts > visi_max then begin
				if visi_max <> 0 then
					AddMessage('Plugin with greater VISI: ' + s + ' (ts == ' + IntToHex(ts, 8) + ')');
				visi_max := ts;
				e := t;
			end
		end;

		// XXX: consider allowing precombine_merge files in previs mode
		if Pos('precombine_merge', s) <> 0 then
			continue;
		if Pos('previs_merge', s) <> 0 then
			continue;

		o := t;
		break;
	end;

	merge := (MergeIntoOverride and IsEditable(o));
	if Debug then begin
		if merge then begin
			AddMessage(Format('m == %s, o == %s, oc == %d, merge == 1', [GetFileName(m), GetFileName(o), oc]));
		end else begin
			AddMessage(Format('m == %s, o == %s, oc == %d, merge == 0', [GetFileName(m), GetFileName(o), oc]));
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


if False then begin
	AddMessage(Format('Checking children of element %s using override %s for master %s [TEST]', [GetFileName(e), GetFileName(o), GetFileName(m)]));
//	g := ChildGroup(o);
	cell_refr_first(o);

	Result := True;
	Exit;
end;

	try
		if mode = 'precombine' then begin
			if merge then begin
				precombine_merge(plugin, e, o, m);
			end else begin
				precombine_split(plugin, e, o, m);
			end;
		end else if mode = 'previs' then begin
			previs_merge(plugin, e, o, m);
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
	plugin: IInterface;
	i: integer;
begin
//	for i := 0 to 255 do begin
//		plugin := plugin_map[i];
//		if not Assigned(plugin) then Continue;
//
//		SortMasters(plugin);
//		CleanMasters(plugin);
//	end;
end;

end.

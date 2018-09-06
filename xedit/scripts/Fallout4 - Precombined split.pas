{
	1. Split precombines into separate plugins based on their master.
	2. Recombine precombine/previs of loaded plugins into a final plugin.
}

unit FO4_Precombined_Split;
const
	Debug = False;
	VersionInc = False;
	StopOnError = False;
	ConflictOnly = False;
	PrecombineFileSuffix = 'precombine_merge';
	PrevisFileSuffix = 'previs_final';
	PrevisFileBase = 'pcv';
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

function plugin_file_resolve(ofstr: TString; mode: TString): IInterface;
var
	plugin: IInterface;
	b, s, pfile: TString;
	i: integer;
begin
	// Attempt to locate existing plugin for the same file or create a new one
	for i := 0 to Pred(MaxFileAttempts) do begin
		if mode = 'precombine' then begin
			b := ofstr;

			if i = 0 then begin
				s := PrecombineFileSuffix;
			end else begin
				s := PrecombineFileSuffix + '.' + IntToStr(i);
			end;
		end else begin
			b := PrevisFileBase;

			if i = 0 then begin
				s := PrevisFileSuffix;
			end else begin
				s := PrevisFileSuffix + '.' + IntToStr(i);
			end;
		end;

		pfile := b + '.' + s + '.' + PluginSuffix;
		plugin := plugin_file_resolve_existing(pfile);
		if Assigned(plugin) then begin
			Result := plugin; Exit;
		end;

		try
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
	t, ofile, plugin: IInterface;
	s, pfile, mfstr, ofstr: TString;
	idx, i, j: integer;
begin
	ofile := GetFile(o);
	idx := GetLoadOrder(ofile);
	plugin := plugin_map[idx];
	if Assigned(plugin) then begin
		Result := plugin; Exit;
	end;

	// Master and immediately preceeding master (if any) of the element being processed
	mfstr := GetFileName(m);
	ofstr := GetFileName(ofile);
	plugin := plugin_file_resolve(ofstr, mode);
	plugin_map[idx] := plugin;

	try
		// Almost always the main game master (Fallout4.esm), however
		// there are situations with entirely new records where the
		// the actual master is the one originating said records.
		if Debug then AddMessage('Adding master: ' + mfstr);
		AddMasterIfMissing(plugin, mfstr);

		// For the overridden master of the element being processed
		// add its masters as an explicit master to the plugin being
		// created. This is necessary due to CKs idea of how the per
		// master plugin should look had it been saved from CK. Not
		// doing this and instead adding only element-required masters
		// will result in CK misnumbering the reference formids when
		// the created plugin is merged back in with version control.
		for j := 0 to Pred(MasterCount(ofile)) do begin
			t := MasterByIndex(ofile, j);
			if Debug then AddMessage('Adding master: ' + GetFileName(t));
			AddMasterIfMissing(plugin, GetFileName(t));
		end;

		// The actual override prior to this elements plugin
		if not Equals(o, m) then begin
			if Debug then AddMessage('Adding master: ' + ofstr);
			AddMasterIfMissing(plugin, ofstr);
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

function previs_merge(plugin: IwbFile; e, o, m: IInterface): Boolean;
var
	r, t: IInterface;
	s: string;
	i: integer;
begin
	try
		// It might be safe to simply copy from e rather than
		// the last overridden non-pcv related plugin. This
		// depends on how reliable the XCRI data is in the
		// plugin providing the authoritative XPRI data.
		r := wbCopyElementToFile(o, plugin, False, True);

		for i := 0 to Pred(length(pv_sig_tab)) do begin
			s := pv_sig_tab[i];
			t := ElementBySignature(e, s);
			if Assigned(t) then begin
				if not ElementExists(r, s) then
					Add(r, s, True);
				ElementAssign(ElementBySignature(r, s), LowInteger, t, False);
			end;
		end;

		SetFormVersion(r, GetFormVersion(e));
		SetFormVCS1(r, GetFormVCS1(e));
		SetFormVCS2(r, GetFormVCS2(e));
	except
		on Ex: Exception do begin
			Remove(r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := True;
end;

function precombine_split(plugin: IwbFile; e, o, m: IInterface): boolean;
var
	r, t: IInterface;
	s: TString;
	flags, mflags, i, j, oc: integer;
begin
	try
		// XXX: xEdit will choke on delocalized plugins containing strings like '$Farm05Location'
		// XXX: due to it wrongly interpreting it as a hex/integer value and will also disallow copying
		// XXX: an element with busted references. Attempt a normal deepcopy first and if it does not
		// XXX: succeed then attempt an element by element copy whilst avoiding bogus XPRI data.
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
			if ElementExists(o, s) then begin
				if not ElementExists(r, s) then
					Add(r, s, True);
				ElementAssign(ElementBySignature(r, s), LowInteger, ElementBySignature(o, s), False);
			end else if ElementExists(r, s) then begin
				RemoveElement(r, s);
			end;
		end;

		SetFormVersion(r, GetFormVersion(e));
		SetFormVCS1(r, GetFormVCS1(e));
		SetFormVCS2(r, GetFormVCS2(e));

		flags := GetElementNativeValues(r, 'Record Header\Record Flags');
		mflags := GetElementNativeValues(m, 'Record Header\Record Flags');

		// If record has 'no previs' set but master does not, remove it
		if ((flags and $80) <> 0) and ((mflags and $80) = 0) then begin
			AddMessage('Warning: disabling explicitly set "no previs" flag: ' + FullPath(e));
			SetElementNativeValues(r, 'Record Header\Record Flags', flags - $80);
		end;
	except
		on Ex: Exception do begin
			Remove(r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := True;
end;

function Process(e: IInterface): integer;
var
	o, m, r, t, f, ofile, plugin: IInterface;
	s, mode, mfstr, ofstr, pfile: TString;
	i, j, oc: integer;
	o_visi, o_pcmb: IInterface;
	ts, pcmb_max, visi_max: integer;
	nv: string;
begin
//	mode := 'precombine';
	mode := 'previs';

	// operate on the last override
	e := WinningOverride(e);

	// skip if this is a plugin file generated by this script
	if (Pos(PrecombineFileSuffix, GetFileName(e)) <> 0) then
		Exit;
	if (Pos(PrevisFileSuffix, GetFileName(e)) <> 0) then
		Exit;

	// Skip non-cells
	if Signature(e) <> 'CELL' then
		Exit;

	// XXX: check existing generated precombined plugins for cells without precombines
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
	if (oc = 0 or Equals(e, m)) then begin
		Exit;
	end else if Debug then begin
		for i := 0 to Pred(oc) do begin
			t := OverrideByIndex(m, i);
			AddMessage('override[' + IntToStr(i) + '] == ' + GetFileName(t));
		end;
	end;

	// XXX: ensure last override is never used (change for loop counter?)
	// | [0] master | [1] override | [2] *override* | [3] element | ...
	o := m;
	o_pcmb := nil;
	o_visi := nil;
	pcmb_max := 0;
	visi_max := 0;
	for i := Pred(oc) downto 0 do begin
		t := OverrideByIndex(m, i);
		s := GetFileName(t);

		if ElementExists(t, 'PCMB') then begin
			nv := GetElementEditValues(t, 'PCMB');
			if length(nv) >= 5 then
				ts := StrToInt('$' + nv[4] + nv[5] + nv[1] + nv[2]);
				if ts = 0 or ts > pcmb_max then begin
					if pcmb_max <> 0 then
						AddMessage('Plugin with greater PCMB: ' + s + ' (ts == ' + IntToHex(ts, 8) + ')');
					pcmb_max := ts;
					e := t;
				end
		end;

		if ElementExists(t, 'VISI') then begin
			nv := GetElementEditValues(t, 'VISI');
			if length(nv) >= 5 then
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

	if Debug then
		AddMessage('m == ' + GetFileName(m) + ', o == ' + GetFileName(o) + ', oc == ' + IntToStr(oc));

	plugin := plugin_resolve(e, o, m, mode);
	if not Assigned(plugin) then begin
		Result := StopOnError; Exit;
	end;

	try
		if mode = 'precombine' then begin
			precombine_split(plugin, e, o, m);
		end else begin
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

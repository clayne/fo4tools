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
	OutputFileSuffix = 'precombine_merge.esp';
	FinalFile = 'pcv-final2.esp';
var
	// Elements to keep from the most immediate plugin being overridden
	plugin_map: array [0..255] of IInterface;
	pc_sig_tab: array [0..1] of TString;
	pv_sig_tab: array [0..2] of TString;
function Initialize: integer;
begin
//	plugin_map := THashedStringList.Create;
	pc_sig_tab[0] := 'XCRI';
	pc_sig_tab[1] := 'PCMB';
	pv_sig_tab[0] := 'XPRI';
	pv_sig_tab[1] := 'RVIS';
	pv_sig_tab[2] := 'VISI';
end;

function plugin_resolve(e, o, m: IInterface; mode: TString): IInterface;
var
	t, ofile, plugin: IInterface;
	mfstr, ofstr, pfile: TString;
	i, j: Integer;
begin
	ofile := GetFile(o);
	i := GetLoadOrder(ofile);
	plugin := plugin_map[i];
	if Assigned(plugin) then begin
		Result := plugin;
		Exit;
	end;

	// Master and immediately preceeding master (if any) of the element being processed
	mfstr := GetFileName(m);
	ofstr := GetFileName(ofile);
	if mode = 'precombine' then begin
		pfile := ofstr + '.' +  OutputFileSuffix;
	end else begin
		pfile := FinalFile;	// XXX: Fix this
	end;

	// Attempt to find already created plugin in loaded files
	for j := Pred(FileCount) downto 0 do begin
		t := FileByIndex(j);
		if GetFileName(t) = pfile then begin
			plugin := t;
			Break;
		end;
	end;

	// Otherwise create a new plugin
	if not Assigned(plugin) then begin
		// create new plugin
		AddMessage('Creating file: ' + pfile);

		plugin := AddNewFileName(pfile);
		if not Assigned(plugin) then begin
			AddMessage('Unable to create new file for ' + pfile);

			Result := nil;
			Exit;
		end;
	end;

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

			Result := nil;
			Exit;
		end;
	end;

	plugin_map[i] := plugin;

	Result := plugin;
end;

function precombine_previs_extract(plugin: IwbFile; e, o: IInterface): Boolean;
var
	r, t: IInterface;
	s: string;
	i: integer;
begin
	try
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

function precombine_copy(plugin: IwbFile; e, o: IInterface): Boolean;
var
	r, t: IInterface;
	s: TString;
	flags, mflags, i, j, oc: integer;
begin
	try
		// XXX: xEdit will choke on delocalized plugins containing strings like '$Farm05Location'
		// XXX: due to it wrongly interpreting it as an integer value and will also disallow copying
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
		if ((flags and $80) and not (mflags and $80)); then begin
			AddMessage('Warning: disabling explicitly set "no previs" flag: ' + FullPath(e));
			SetElementNativeValues(r, 'Record Header\Record Flags', flags xor $80);
		end;
	except
		on Ex: Exception do begin
			Remove(r);
			Raise Exception.Create(Ex.Message);
		end;
	end;

	Result := True;
end;

function Process(e: IInterface): Integer;
var
	o, m, r, t, f, ofile, plugin: IInterface;
	s, mode, mfstr, ofstr, pfile: TString;
	i, j, oc: integer;
begin
	// XXX: change to 'final' or something else
//	mode := 'precombine';
	mode := 'previs';

	// operate on the last override
	e := WinningOverride(e);

	// skip if this is the plugin file generated by this script
	if (Pos(OutputFileSuffix, GetFileName(e)) <> 0) then
		Exit;
	if (Pos(FinalFile, GetFileName(e)) <> 0) then
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
	if Debug then begin
		for i := 0 to Pred(oc) do begin
			t := OverrideByIndex(m, i);
			AddMessage('override[' + IntToStr(i) + '] == ' + GetFileName(t));
		end;
	end;

	// XXX: Use same method for both
	// XXX: ensure last override is never used (change for loop counter?)
	if mode = 'precombine' then begin
		if (oc = 0 or Equals(e, m)) then begin
			Exit;
		end else if oc = 1 then begin
			o := m;
		end else begin
			// | [0] master | [1] override | [2] *override* | [3] element (oc == 3)
			o := OverrideByIndex(m, oc - 2);
		end;
	end else if mode = 'previs' then begin
		if (oc = 0 or Equals(e, m)) then begin
			Exit;
		end else begin
			// | [0] master | [1] override | [2] *override* | [3] element | ...
			o := m;
			for i := Pred(oc) downto 0 do begin
				t := OverrideByIndex(m, i);
				s := GetFileName(t);

				// XXX: consider allowing precombine_merge files in previs mode
				if Pos('precombine_merge', s) <> 0 then
					continue;
				if Pos('previs_merge', s) <> 0 then
					continue;
				o := t;
				break;
			end;
//			if not Assigned(o) then begin
//				AddMessage('Unable to find originating record: ' + FullPath(e));
//				Exit;
//			end;
		end;
	end else begin
		AddMessage('Unknown mode: ' + mode);
		Result := 1;
		Exit;
	end;

	if Debug then
		AddMessage('m == ' + GetFileName(m) + ', o == ' + GetFileName(o) + ', oc == ' + IntToStr(oc));

	plugin := plugin_resolve(e, o, m, mode);
	if not Assigned(plugin) then begin
		Result := StopOnError;
		Exit;
	end;

	try
		if mode = 'precombine' then begin
			precombine_copy(plugin, e, o);
		end else begin
			precombine_previs_extract(plugin, e, o);
		end;
	except
		on Ex: Exception do begin
			AddMessage('Failed to copy: ' + FullPath(e));
			AddMessage('        reason: ' + Ex.Message);

			Result := StopOnError;
			Exit;
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

{
	Disable PreVis in selected exterior worldspaces/cells.
	Supports Fallout 4 only.
}
unit FO4_Precombined_Split;
const
	Debug = False;
	VersionInc = False;
	StopOnError = False;
	ConflictOnly = False;
	OutputFileSuffix = 'precombine_merge.esp';
var
	// Elements to keep from the most immediate plugin being overridden
	defer_tab: array [0..2] of TString;
	plugin_map: array [0..255] of IInterface;
function Initialize: integer;
begin
//	plugin_map := THashedStringList.Create;
	defer_tab[0] := 'XPRI';
	defer_tab[1] := 'RVIS';
	defer_tab[2] := 'VISI';
end;

function plugin_resolve(e, o, m: IInterface): IInterface;
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
	pfile := ofstr + '.' +  OutputFileSuffix;

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
		// the created plugin is merged back in (version control).
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

function precombine_copy(plugin: IwbFile; e, o: IInterface): Boolean;
var
	r, t: IInterface;
	s: TString;
	i, j, oc: integer;
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
		for i := 0 to Pred(length(defer_tab)) do begin
			s := defer_tab[i];
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
	s, mfstr, ofstr, pfile: TString;
	i, j, oc: integer;
begin
	// operate on the last override
	e := WinningOverride(e);

	// skip if this is the plugin file generated by this script
	if (Pos(OutputFileSuffix, GetFileName(e)) <> 0) then
		Exit;

	// skip non-cells
	if Signature(e) <> 'CELL' then
		Exit;

	// skip cells without precombination
	if not (ElementExists(e, 'XCRI') or ElementExists(e, 'PCMB')) then
		Exit;

	m := Master(e);
	oc := OverrideCount(m);
	if Debug then begin
		for i := 0 to Pred(oc) do begin
			t := OverrideByIndex(m, i);
			AddMessage('override[' + IntToStr(i) + '] == ' + GetFileName(t));
		end;
	end;

	if (oc = 0 or Equals(e, m)) then begin
		Exit;
	end else if oc = 1 then begin
		o := m;
	end else begin
		// | [0] master | [1] override | [2] *override* | [3] element (oc == 3)
		o := OverrideByIndex(m, oc - 2);
	end;

	if Debug then
		AddMessage('m == ' + GetFileName(m) + ', o == ' + GetFileName(o) + ', oc == ' + IntToStr(oc));

	plugin := plugin_resolve(e, o, m);
	if not Assigned(plugin) then begin
		Result := StopOnError;
		Exit;
	end;

	try
		precombine_copy(plugin, e, o);
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

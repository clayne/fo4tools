function fo4tools_prof_name() {
	local pwd="${1:-$PWD}"

        [[ "$pwd" =~ Fallout\ ?4 ]] || return
        local p="${pwd/Fallout 4\/*/Fallout 4}"; p="${p/Fallout4\/*/Fallout4}"
        local fo4prof=$(readlink.exe -en "$p"); fo4prof=${fo4prof#*.}; fo4prof=${fo4prof/\/*}

	echo "$fo4prof"
}

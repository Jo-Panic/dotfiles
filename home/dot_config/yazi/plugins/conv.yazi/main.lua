--- conv.yazi — menu de conversion des fichiers sélectionnés (E puis c).
--- Toute la logique est dans ~/.local/bin/conv : le plugin demande au script
--- les presets applicables, les affiche (ya.which), lance la conversion
--- et notifie le bilan (dernière ligne de la sortie du script).

local CONV = os.getenv("HOME") .. "/.local/bin/conv"

--- Récupère les fichiers sélectionnés, ou le fichier survolé (contexte sync, accès à cx)
local get_selected = ya.sync(function()
	local paths = {}
	for _, file in pairs(cx.active.selected) do
		paths[#paths + 1] = tostring(file.url)
	end
	if #paths == 0 then
		local hovered = cx.active.current.hovered
		if hovered then
			paths[1] = tostring(hovered.url)
		end
	end
	return paths
end)

local function notify(content, level, timeout)
	ya.notify({ title = "Conversion", content = content, level = level, timeout = timeout or 3 })
end

--- Lance conv avec les options données, puis les chemins après « -- »
local function run(opts, paths)
	local cmd = Command(CONV)
	for _, opt in ipairs(opts) do
		cmd = cmd:arg(opt)
	end
	cmd = cmd:arg("--")
	for _, path in ipairs(paths) do
		cmd = cmd:arg(path)
	end
	return cmd:output()
end

local function last_line(text)
	return text:match("([^\n]+)\n*$")
end

return {
	entry = function()
		local paths = get_selected()
		if #paths == 0 then
			return notify("Aucun fichier sélectionné", "warn")
		end

		local list, err = run({ "--presets" }, paths)
		if not list then
			return notify("Lancement de conv impossible : " .. tostring(err), "error", 5)
		end
		-- Script arrêté avant de lister (bash trop ancien, coreutils absent…) :
		-- afficher sa raison plutôt que « Aucune conversion possible »
		if not list.status.success then
			return notify(last_line(list.stderr) or "conv --presets a échoué", "error", 8)
		end

		-- Une ligne par preset : touche, identifiant, libellé (séparés par des tabulations)
		local cands, ids = {}, {}
		for line in list.stdout:gmatch("[^\n]+") do
			local key, id, label = line:match("^([^\t]+)\t([^\t]+)\t(.+)$")
			if key then
				cands[#cands + 1] = { on = key, desc = label }
				ids[#ids + 1] = id
			end
		end
		if #cands == 0 then
			return notify("Aucune conversion possible pour cette sélection", "warn")
		end

		local idx = ya.which({ cands = cands })
		if not idx then
			return
		end

		notify("Conversion en cours : " .. #paths .. " fichier(s)…", "info", 2)
		local out, err2 = run({ "-p", ids[idx] }, paths)
		if not out then
			return notify("Lancement de conv impossible : " .. tostring(err2), "error", 5)
		end

		local summary = last_line(out.stdout) or "Terminé"
		if out.status.success then
			notify(summary, "info")
		else
			local detail = last_line(out.stderr)
			notify(summary .. (detail and ("\n" .. detail) or ""), "error", 8)
		end
	end,
}

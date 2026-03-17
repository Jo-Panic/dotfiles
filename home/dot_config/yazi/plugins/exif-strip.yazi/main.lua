--- Récupère les fichiers sélectionnés (contexte sync, accès à cx)
local get_selected = ya.sync(function()
	local paths = {}
	for _, url in pairs(cx.active.selected) do
		paths[#paths + 1] = tostring(url)
	end
	if #paths == 0 then
		local hovered = cx.active.current.hovered
		if hovered then
			paths[1] = tostring(hovered.url)
		end
	end
	return paths
end)

return {
	entry = function()
		local paths = get_selected()

		if #paths == 0 then
			ya.notify({ title = "EXIF Strip", content = "Aucun fichier sélectionné", level = "warn", timeout = 3 })
			return
		end

		local cmd = Command("exiftool"):arg("-overwrite_original"):arg("-all=")
		for _, path in ipairs(paths) do
			cmd = cmd:arg(path)
		end

		local output, err = cmd:output()

		if output and output.status.success then
			ya.notify({
				title = "EXIF Strip",
				content = #paths .. " fichier(s) nettoyé(s)",
				level = "info",
				timeout = 3,
			})
		else
			ya.notify({
				title = "EXIF Strip",
				content = "Erreur : " .. (err or "inconnue"),
				level = "error",
				timeout = 5,
			})
		end
	end,
}

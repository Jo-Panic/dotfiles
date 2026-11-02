--- Récupère les fichiers sélectionnés (contexte sync, accès à cx)
local get_selected = ya.sync(function()
	local paths = {}
	for _, file in pairs(cx.active.selected) do
		local path = tostring(file.url)
		if path:match("%.pdf$") or path:match("%.PDF$") then
			paths[#paths + 1] = path
		end
	end
	if #paths == 0 then
		local hovered = cx.active.current.hovered
		if hovered then
			local path = tostring(hovered.url)
			if path:match("%.pdf$") or path:match("%.PDF$") then
				paths[1] = path
			end
		end
	end
	return paths
end)

return {
	entry = function()
		local paths = get_selected()

		if #paths == 0 then
			ya.notify({
				title = "PDF Compress",
				content = "Aucun fichier PDF sélectionné",
				level = "warn",
				timeout = 3,
			})
			return
		end

		local ok_count = 0
		local err_count = 0

		for _, path in ipairs(paths) do
			local dir = path:match("(.*/)")
			local base = path:match("([^/]+)%.pdf$") or path:match("([^/]+)%.PDF$")
			local output = dir .. base .. "_compressed.pdf"

			local child, err = Command("gs")
				:arg("-sDEVICE=pdfwrite")
				:arg("-dCompatibilityLevel=1.4")
				:arg("-dPDFSETTINGS=/printer")
				:arg("-dNOPAUSE")
				:arg("-dBATCH")
				:arg("-dQUIET")
				:arg("-sOutputFile=" .. output)
				:arg(path)
				:output()

			if child and child.status.success then
				ok_count = ok_count + 1
			else
				err_count = err_count + 1
			end
		end

		if err_count == 0 then
			ya.notify({
				title = "PDF Compress",
				content = ok_count .. " fichier(s) compressé(s)",
				level = "info",
				timeout = 3,
			})
		else
			ya.notify({
				title = "PDF Compress",
				content = ok_count .. " OK, " .. err_count .. " erreur(s)",
				level = "error",
				timeout = 5,
			})
		end
	end,
}

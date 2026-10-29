-- Project Launcher · arranque silencioso de REAPER
--
-- REAPER en evaluación abre su ventana de licencia ("About REAPER…") alrededor
-- de un segundo después de arrancar, encima de todo. Este vigilante la manda
-- fuera de pantalla antes de que se vea, espera a que el botón se habilite
-- (la cuenta atrás sólo corre con REAPER al frente) y la descarta sola.
-- Al terminar devuelve el foco al launcher.
--
-- Uso: osascript quiet-reaper.applescript [segundos_de_espera]

on run argv
	set presupuesto to 15
	try
		set presupuesto to (item 1 of argv) as integer
	end try

	-- marca vieja de un arranque anterior
	try
		set marca0 to ((system attribute "HOME") & "/Library/Application Support/Project Launcher/quiet-done")
		do shell script "rm -f " & quoted form of marca0
	end try

	set deadline to (current date) + presupuesto
	set visto to false

	tell application "System Events"
		if not (exists process "REAPER") then return "REAPER no está corriendo"
		tell process "REAPER"
			-- Fase 1: esperar la ventana de arranque, sin tocar el foco
			repeat until (current date) > deadline
				repeat with w in windows
					try
						if (name of w) starts with "About REAPER" then
							set visto to true
							exit repeat
						end if
					end try
				end repeat
				if visto then exit repeat
				delay 0.2
			end repeat

			if not visto then return "sin ventana de arranque"

			-- Fase 2: esconderla antes de que el usuario la vea
			repeat with w in windows
				try
					if (name of w) starts with "About REAPER" then
						set position of w to {-4000, -4000}
						exit repeat
					end if
				end try
			end repeat

			-- Fase 3: la cuenta atrás avanza sólo con REAPER al frente
			set frontmost to true
			set sub to (current date) + 40
			repeat until (current date) > sub
				set objetivo to missing value
				repeat with w in windows
					try
						if (name of w) starts with "About REAPER" then
							set objetivo to contents of w
							exit repeat
						end if
					end try
				end repeat
				if objetivo is missing value then exit repeat
				try
					set b to button 1 of objetivo
					if (enabled of b) is true then
						click b
						delay 0.4
						exit repeat
					end if
				end try
				delay 0.25
			end repeat
		end tell
	end tell

	-- Avisar al launcher para que recupere el foco (una app de agente no puede
	-- activarse desde AppleScript; ella misma se activa al ver la marca).
	try
		set marca to ((system attribute "HOME") & "/Library/Application Support/Project Launcher/quiet-done")
		do shell script "touch " & quoted form of marca
	end try
	return "listo"
end run

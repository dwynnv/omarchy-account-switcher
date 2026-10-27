-- Hyprland event handlers for the mode switcher, registered again on every config load.
local W = {}

-- Hyprland is rearranging monitors and the workspaces on them.
local TOPOLOGY = { "monitor.added", "monitor.removed", "monitor.layout_changed", "workspace.move_to_monitor" }

function W.register(desk, logic)
  -- A monitor showing a workspace of the other mode that the switcher didn't ask for.
  -- Nothing happens inside the event, as Hyprland may be halfway through moving workspaces:
  -- on the focused monitor it is the user's landing, which the rest of the desk follows
  -- shortly; anywhere else, or while monitors are rearranged, settle puts it back.
  hl.on("workspace.active", function(ws)
    if not ws.id or desk.is_busy() then return end
    local mon = ws.monitor
    local decision = logic.decide_landing({
      current = desk.current(),
      ws_mode = logic.mode_of(ws.id),
      on_focused_monitor = mon ~= nil and mon.focused == true,
      peeking = desk.is_peeking(),
    })
    if decision == "complete" then
      desk.land()
    elseif decision == "fix_monitor" then
      desk.settle()
    end
  end)
  for _, name in ipairs(TOPOLOGY) do
    hl.on(name, function()
      if not desk.is_busy() then desk.settle() end
    end)
  end

  hl.on("window.open", function(w)
    if not desk.place_expected(w) then desk.place_new(w) end
    desk.tag_window(w)
  end)
  hl.on("window.move_to_workspace", function(w) desk.tag_window(w) end)
  -- A blocked request to come forward: a toast click (see desk.toast_clicked), else an alert.
  hl.on("window.urgent", function(w)
    if not desk.take_click(w) then desk.add_alert(w) end
  end)
  hl.on("window.close", function(w)
    desk.remember_place(w)
    desk.drop_alert(w)
  end)

  -- Fires at the end of every load, including the first one before any monitor exists.
  hl.on("config.reloaded", function()
    if #hl.get_monitors() > 0 then
      desk.first_run()
      desk.retag_all()
      desk.settle()
    end
  end)

  hl.on("hyprland.start", function() desk.restore() end)
end

return W

---
--- Start switcher ui
---
    awful.key({modkey}, "/", function () machi.switcher.start(client.focus).ui() end),

---
--- Tab through overlapping clients
---
    awful.key({modkey}, "Tab", function () machi.switcher.start(client.focus).tab() end),

---
--- Move by direction
---
    awful.key({modkey, "Shift"}, "h", function() machi.switcher.start(client.focus).move("left") end),
    awful.key({modkey, "Shift"}, "j", function() machi.switcher.start(client.focus).move("down") end),
    awful.key({modkey, "Shift"}, "k", function() machi.switcher.start(client.focus).move("up") end),
    awful.key({modkey, "Shift"}, "l", function() machi.switcher.start(client.focus).move("right") end),

--
-- Cycle predefined layouts
--
    awful.key({ modkey, }, "z", function() nextMachiLayout() end),

    function setMachiLayout(cmd)
        local screen = awful.screen.focused()
        local tag = screen.selected_tags[1]
        machi_layout.machi_set_cmd(cmd, tag, true)
    end

    local machi_layouts = {
        "v1,4t3h1,4,1-h1,1cct3h1,4,1-t3v2.",
        "v13h1221h1331.",
    }
    local machi_layout_n = 0

    function nextMachiLayout()
        machi_layout_n = machi_layout_n + 1
        if machi_layout_n > #machi_layouts then
            machi_layout_n = 1
        end
        local l = machi_layouts[machi_layout_n]
        setMachiLayout(l)
    end

--
-- Swap by direction (credits: @basaran https://github.com/xinhaoyuan/layout-machi/issues/13)
-- Inferior to moving imo but prevents overlapping.
--
    function swap(dir)
        local cltbl = awful.client.visible(client.focus.screen, true)
        local grect = require("gears.geometry").rectangle
        local geomtbl = {}

        for i,cl in ipairs(cltbl) do
            geomtbl[i] = cl:geometry()
        end

        local target = grect.get_in_direction(dir, geomtbl, client.focus:geometry())

        tobe = cltbl[target]:geometry()
        is = client.focus:geometry()

        client.focus:geometry(tobe)
        cltbl[target]:geometry(is)
    end


    awful.key({ modkey, "Shift" }, "h", function() swap("left") end),
    awful.key({ modkey, "Shift" }, "j", function() swap("down") end),
    awful.key({ modkey, "Shift" }, "k", function() swap("up") end),
    awful.key({ modkey, "Shift" }, "l", function() swap("right") end),


local machi = {
    layout = require((...):match("(.-)[^%.]+$") .. "layout"),
    engine = require((...):match("(.-)[^%.]+$") .. "engine"),
}

local capi = {
    client = client,
    screen = screen,
}

local beautiful = require("beautiful")
local wibox = require("wibox")
local awful = require("awful")
local gears = require("gears")
local lgi = require("lgi")
local dpi = require("beautiful.xresources").apply_dpi
local gtimer = require("gears.timer")

local ERROR = 2
local WARNING = 1
local INFO = 0
local DEBUG = -1

local module = {
    log_level = WARNING,
}

local function log(level, msg)
    if level > module.log_level then
        print(msg)
    end
end

local function min(a, b)
    if a < b then return a else return b end
end

local function max(a, b)
    if a < b then return b else return a end
end

local function with_alpha(col, alpha)
    local r, g, b
    _, r, g, b, _ = col:get_rgba()
    return lgi.cairo.SolidPattern.create_rgba(r, g, b, alpha)
end

function module.start(c, exit_keys)
    local tablist_font_desc = beautiful.get_merged_font(
        beautiful.font, dpi(10))
    local font_color = with_alpha(gears.color(beautiful.fg_normal), 1)
    local font_color_hl = with_alpha(gears.color(beautiful.fg_focus), 1)
    local label_size = dpi(30)
    local border_color = with_alpha(
        gears.color(beautiful.machi_switcher_border_color or beautiful.border_focus),
        beautiful.machi_switcher_border_opacity or 0.25)
    local border_color_hl = with_alpha(
        gears.color(beautiful.machi_switcher_border_hl_color or beautiful.border_focus),
        beautiful.machi_switcher_border_hl_opacity or 0.75)
    local fill_color = with_alpha(
        gears.color(beautiful.machi_switcher_fill_color or beautiful.bg_normal),
        beautiful.machi_switcher_fill_opacity or 0.25)
    local box_bg = with_alpha(
        gears.color(beautiful.machi_switcher_box_bg or beautiful.bg_normal),
        beautiful.machi_switcher_box_opacity or 0.85)
    local fill_color_hl = with_alpha(
        gears.color(beautiful.machi_switcher_fill_color_hl or beautiful.bg_focus),
        beautiful.machi_switcher_fill_hl_opacity or 1)
    -- for comparing floats
    local threshold = 0.1
    local traverse_radius = dpi(5)

    local screen = c and c.screen or awful.screen.focused()
    local tag = screen.selected_tag
    local layout = tag.layout
    local gap = tag.gap
    local start_x = screen.workarea.x
    local start_y = screen.workarea.y

    if layout.machi_get_instance_data == nil then return end

    local cd, td, areas, _new_placement_cb = layout.machi_get_instance_data(screen, screen.selected_tag)
    if areas == nil or #areas == 0 then
        return
    end

    local infobox, infotabbox
    local tablist = nil

    local traverse_x, traverse_y
    if c then
        traverse_x = c.x + traverse_radius
        traverse_y = c.y + traverse_radius
    else
        traverse_x = screen.workarea.x + screen.workarea.width / 2
        traverse_y = screen.workarea.y + screen.workarea.height / 2
    end

    local selected_area_ = nil
    local function set_selected_area(area)
        selected_area_ = area
        if area then
            traverse_x = max(areas[area].x + traverse_radius, min(areas[area].x + areas[area].width - traverse_radius, traverse_x))
            traverse_y = max(areas[area].y + traverse_radius, min(areas[area].y + areas[area].height - traverse_radius, traverse_y))
        end
    end

    local function selected_area()
        if selected_area_ == nil then
            local min_dis = nil
            for i, a in ipairs(areas) do
                if a.habitable then
                    local dis =
                        math.abs(a.x + traverse_radius - traverse_x) + math.abs(a.x + a.width - traverse_radius - traverse_x) - a.width +
                        math.abs(a.y + traverse_radius - traverse_y) + math.abs(a.y + a.height - traverse_radius - traverse_y) - a.height +
                        traverse_radius * 4
                    if min_dis == nil or min_dis > dis then
                        min_dis = dis
                        selected_area_ = i
                    end
                end
            end

            set_selected_area(selected_area_)
        end
        return selected_area_
    end

    local parent_stack = {}

    local function get_tablist(area)
        local list = {}
        for _, tc in ipairs(screen.tiled_clients) do
            if not (tc.floating or tc.immobilized)
            then
                if areas[area].x <= tc.x + tc.width + tc.border_width * 2 and tc.x <= areas[area].x + areas[area].width and
                    areas[area].y <= tc.y + tc.height + tc.border_width * 2 and tc.y <= areas[area].y + areas[area].height
                then
                    list[#list + 1] = tc
                end
            end
        end

        return list
    end

    local function maintain_tablist()
        tablist = get_tablist(selected_area())
        if #tablist ~= 0 then
            c = tablist[1]
        end
    end

    local function draw_tab_info(context, cr, width, height)
        maintain_tablist()

        local wi = { x = 0, y = 0, w = 1, h = 1 }
        local ext
        local active_area = selected_area()
        if #tablist > 0 then
            local a = areas[active_area]
            local pl = lgi.Pango.Layout.create(cr)
            pl:set_font_description(tablist_font_desc)

            local vpadding = dpi(10)
            local hpadding = dpi(15)
            local vborder  = dpi(5)
            local hborder  = dpi(5)
            local list_height = 2 * vborder
            local list_width = 2 * hpadding + 2 * hborder
            local exts = {}

            local tl = {}
            local hw = math.floor((#tablist-1)/2)
            for i = hw+1,2,-1 do
                table.insert(tl, tablist[i])
            end
            table.insert(tl, tablist[1])
            local active = #tl
            for i = #tablist,hw+2,-1 do
                table.insert(tl, tablist[i])
            end

            for index, tc in ipairs(tl) do
                local label = tc.name or "<unnamed>"
                pl:set_text(label)
                local w, h
                w, h = pl:get_size()
                w = w / lgi.Pango.SCALE
                h = h / lgi.Pango.SCALE
                local ext = { width = w, height = h }
                exts[#exts + 1] = ext
                list_height = list_height + ext.height + vpadding
                list_width = max(list_width, w + 2 * hpadding + 2 * hborder)
            end

            local y_offset = vborder
            wi.x = a.x + (a.width - list_width) / 2
            wi.y = a.y + (a.height - list_height) / 2
            wi.w = list_width
            wi.h = list_height

            cr:rectangle(0, 0, list_width, list_height)
            cr:set_source(border_color_hl)
            cr:fill()

            for index, tc in ipairs(tl) do
                local label = tc.name or "<unnamed>"
                local ext = exts[index]
                if index == active then
                    cr:rectangle(hborder, y_offset, list_width - 2 * hborder, ext.height + vpadding)
                    cr:set_source(fill_color_hl)
                    cr:fill()
                    pl:set_text(label)
                    cr:move_to(hborder + hpadding, vpadding / 2 + y_offset)
                    cr:set_source(font_color_hl)
                    cr:show_layout(pl)
                else
                    pl:set_text(label)
                    cr:move_to(hborder + hpadding, vpadding / 2 + y_offset)
                    cr:set_source(font_color)
                    cr:show_layout(pl)
                end

                y_offset = y_offset + ext.height + vpadding
            end
        end

        if infotabbox.x ~= wi.x or infotabbox.y ~= wi.y or
            infotabbox.width ~= wi.w or infotabbox.height ~= wi.h
        then
            infotabbox.x = wi.x
            infotabbox.y = wi.y
            infotabbox.width = wi.w
            infotabbox.height = wi.h
        end
    end

    local function draw_info(context, cr, width, height)
        maintain_tablist()

        cr:set_source_rgba(0, 0, 0, 0)
        cr:rectangle(0, 0, width, height)
        cr:fill()

        local padx = 5
        local pady = 5
        local msg
        local active_area = selected_area()
        for i, a in ipairs(areas) do
            if a.habitable or i == active_area then
                cr:rectangle(a.x - padx - start_x, a.y - pady - start_y, a.width + 2*padx, a.height + 2*pady)
                cr:clip()
                cr:set_source(fill_color)
                cr:rectangle(a.x - start_x, a.y - start_y, a.width, a.height)
                cr:fill()
                cr:set_source(i == active_area and border_color_hl or border_color)
                cr:rectangle(a.x - start_x, a.y - start_y, a.width, a.height)
                cr:set_line_width(10.0)
                cr:stroke()
                cr:reset_clip()
            end
        end

        if infobox.width ~= screen.workarea.width or infobox.height ~= screen.workarea.height then
            gtimer.delayed_call(function ()
                infobox.width = screen.workarea.width
                infobox.height = screen.workarea.height
                infobox.visible = true
            end)
        end

        -- show the traverse point
        -- cr:rectangle(traverse_x - start_x - traverse_radius, traverse_y - start_y - traverse_radius, traverse_radius * 2, traverse_radius * 2)
        -- cr:set_source_rgba(1, 1, 1, 1)
        -- cr:fill()
    end

    local draw = function()
        if infobox ~= nil then
            infobox.bgimage = draw_info
        end
        if infotabbox ~= nil then
            infotabbox.bgimage = draw_tab_info
        end
    end

    local largest_area = function(areas)
        local largest = nil
        local size = 0
        for i, a in ipairs(areas) do
            local s = a.width * a.height
            if a.habitable and (largest == nil or s > size) then
                largest = i
                size = s
            end
        end

        return largest
    end

    local snap_area = function(x, y, width, height)
        local bestD, d
        local best
        local dist = function(x0, y0, x1, y1)
            local a, b = x0-x1, y0-y1
            return math.sqrt(a*a+b*b)
        end
        for i, a in ipairs(areas) do
            d = dist(a.x, a.y, x, y) +
                dist(a.x+a.width, a.y+a.height, x+width, y+height)
            if bestD == nil or d < bestD then
                bestD = d
                best = i
            end
        end

        return best
    end


    -- area is the index in areas, should be made consistent after el big refactor
    -- draft is reset
    local move_client
    move_client = function(c, area)
        if area == nil or areas[area] == nil or c == nil or not c.valid or c.floating then
            return
        end
        machi.layout.set_geometry(c, areas[area], areas[area], 0, c.border_width)
        if cd[c] == nil then
            return
        end
        cd[c].lu = nil
        cd[c].rd = nil
        cd[c].area = area
    end

    local snap_client = function()
        if c == nil then
            return
        end
        a = snap_area(c.x, c.y, c.width, c.height)
        if a == nil then
            return false
        end

        move_client(c, a)
        return true
    end

    local master_add = function()
        if c == nil or c.floating then
            return
        end

        local dst = largest_area(areas)
        if dst == nil then
            return
        end
        move_client(c, dst)
        awful.layout.arrange(screen)
    end

    local master_swap = function(all)
        if c == nil or c.floating then
            return
        end

        local src = selected_area()
        local dst = largest_area(areas)
        if dst == nil or dst == src then
            return
        end
        local srclist = get_tablist(src)
        local dstlist = get_tablist(dst)

        for i, c in ipairs(dstlist) do
            if all or i == 1 then
                move_client(c, src)
            end
        end
        for i, c in ipairs(srclist) do
            if all or i == 1 then
                move_client(c, dst)
            end
        end
        awful.layout.arrange(screen)
    end

    local traverse_clients = function(dir)
        dir = string.lower(dir)
        local current_area = selected_area()
        local current = areas[current_area]
        if current == nil then
            return false
        end

        local candidates = {}
        for i, a in ipairs(areas) do
            local data = {i = i, a = a}
            if not a.habitable or i == current_area then
            elseif dir == "up" and
                a.y + a.height < current.y and
                #get_tablist(i) ~= 0 then
                table.insert(candidates, data)
            elseif dir == "down" and
                a.y > current.y + current.height and
                #get_tablist(i) ~= 0 then
                table.insert(candidates, data)
            elseif dir == "left" and
                a.x + a.width < current.x and
                #get_tablist(i) ~= 0 then
                table.insert(candidates, data)
            elseif dir == "right" and
                a.x > current.x + current.width and
                #get_tablist(i) ~= 0 then
                table.insert(candidates, data)
            end
        end

        local best_area
        local score
        for i, d in ipairs(candidates) do
            local a = d.a
            local dist, overlap

            if dir == "up" or dir == "down" then
                overlap = min(current.x+current.width, a.x+a.width) - max(current.x, a.x)
            elseif dir == "left" or dir == "right" then
                overlap = min(current.y+current.height, a.y+a.height) - max(current.y, a.y)
            end

            if dir == "up" then
                dist = current.y - a.y - a.height
            elseif dir == "down" then
                dist = a.y - current. y - current.height
            elseif dir == "left" then
                dist = current.x - a.x - a.width
            elseif dir == "right" then
                dist = a.x - current.x - current.width
            end

            -- TODO this is probably not optimal
            local s = overlap - dist
            if score == nil or s > score then
                best_area = d.i
                score = s
            end
        end

        if best_area == nil then
            if #candidates == 0 then
                return false
            end
            best_area = candidates[1].i
        end

        set_selected_area(best_area)
        local tablist = get_tablist(best_area)
        if #tablist == 0 or tablist[1] == c then
            return false
        end
        c = tablist[1]
        capi.client.focus = c
        return true
    end

    local traverse_areas = function(dir, move, draft)
        dir = string.lower(dir)
        local current_area = selected_area()

        if c and move then
            if current_area == nil or
                areas[current_area].x ~= c.x or
                areas[current_area].y ~= c.y
            then
                traverse_x = c.x + traverse_radius
                traverse_y = c.y + traverse_radius
                set_selected_area(nil)
            end
        elseif c and draft then
            local ex = c.x + c.width + c.border_width * 2
            local ey = c.y + c.height + c.border_width * 2
            if current_area == nil or
                areas[current_area].x + areas[current_area].width ~= ex or
                areas[current_area].y + areas[current_area].height ~= ey
            then
                traverse_x = ex - traverse_radius
                traverse_y = ey - traverse_radius
                set_selected_area(nil)
            end
        end

        local choice = nil
        local choice_value

        current_area = selected_area()

        for i, a in ipairs(areas) do
            if not a.habitable then goto continue end

            local v
            if dir == "up" then
                if a.x < traverse_x + threshold
                    and traverse_x < a.x + a.width + threshold then
                    v = traverse_y - a.y - a.height
                else
                    v = -1
                end
            elseif dir == "down" then
                if a.x < traverse_x + threshold
                    and traverse_x < a.x + a.width + threshold then
                    v = a.y - traverse_y
                else
                    v = -1
                end
            elseif dir == "left" then
                if a.y < traverse_y + threshold
                    and traverse_y < a.y + a.height + threshold then
                    v = traverse_x - a.x - a.width
                else
                    v = -1
                end
            elseif dir == "right" then
                if a.y < traverse_y + threshold
                    and traverse_y < a.y + a.height + threshold then
                    v = a.x - traverse_x
                else
                    v = -1
                end
            end

            if (v > threshold) and (choice_value == nil or choice_value > v) then
                choice = i
                choice_value = v
            end
            ::continue::
        end

        if choice == nil then
            choice = current_area
            if dir == "up" then
                traverse_y = screen.workarea.y
            elseif dir == "down" then
                traverse_y = screen.workarea.y + screen.workarea.height
            elseif dir == "left" then
                traverse_x = screen.workarea.x
            else
                traverse_x = screen.workarea.x + screen.workarea.width
            end
        end

        if choice ~= nil then
            tablist = nil
            set_selected_area(choice)

            if c and draft and cd[c].draft ~= false then
                local lu = cd[c].lu or cd[c].area
                local rd = cd[c].rd or cd[c].area

                if draft and move then
                    lu = choice
                    if areas[rd].x + areas[rd].width <= areas[lu].x or
                        areas[rd].y + areas[rd].height <= areas[lu].y
                    then
                        rd = nil
                    end
                else
                    rd = choice
                    if areas[rd].x + areas[rd].width <= areas[lu].x or
                        areas[rd].y + areas[rd].height <= areas[lu].y
                    then
                        lu = nil
                    end
                end

                if lu ~= nil and rd ~= nil then
                    machi.layout.set_geometry(c, areas[lu], areas[rd], 0, c.border_width)
                elseif lu ~= nil then
                    machi.layout.set_geometry(c, areas[lu], nil, 0, c.border_width)
                elseif rd ~= nil then
                    c.x = min(c.x, areas[rd].x)
                    c.y = min(c.y, areas[rd].y)
                    machi.layout.set_geometry(c, nil, areas[rd], 0, c.border_width)
                end

                if lu == rd and cd[c].draft ~= true then
                    cd[c].lu = nil
                    cd[c].rd = nil
                    cd[c].area = lu
                else
                    cd[c].lu = lu
                    cd[c].rd = rd
                    cd[c].area = nil
                end

                c:emit_signal("request::activate", "mouse.move", {raise=false})
                c:raise()
                awful.layout.arrange(screen)
            elseif c and move then
                -- move the window
                local in_draft = cd[c].draft
                if cd[c].draft ~= nil then
                    in_draft = cd[c].draft
                elseif cd[c].lu then
                    in_draft = true
                elseif cd[c].area then
                    in_draft = false
                else
                    log(ERROR, "Assuming in_draft for unhandled client "..tostring(c))
                    in_draft = true
                end
                if in_draft then
                    c.x = areas[choice].x
                    c.y = areas[choice].y
                else
                    machi.layout.set_geometry(c, areas[choice], areas[choice], 0, c.border_width)
                    cd[c].lu = nil
                    cd[c].rd = nil
                    cd[c].area = choice
                end
                c:emit_signal("request::activate", "mouse.move", {raise=false})
                c:raise()
                awful.layout.arrange(screen)

                tablist = nil
            else
                maintain_tablist()
                -- move the focus
                if #tablist > 0 and tablist[1] ~= c then
                    c = tablist[1]
                    capi.client.focus = c
                end
            end

            draw()
        end
    end

    local tab = function()
        maintain_tablist()
        if #tablist > 1 then
            c = tablist[#tablist]
            c:emit_signal("request::activate", "mouse.move", {raise=false})
            c:raise()

            draw()
        end
    end

    local function handle_key(mod, key, event)
        local key_translate_tab = {
            ["k"] = "Up",
            ["h"] = "Left",
            ["j"] = "Down",
            ["l"] = "Right",
            ["K"] = "Up",
            ["H"] = "Left",
            ["J"] = "Down",
            ["L"] = "Right",
        }

        if event == "release" then
            if exit_keys and exit_keys[key] then
                exit()
            end
            return
        end
        if key_translate_tab[key] ~= nil then
            key = key_translate_tab[key]
        end

        maintain_tablist()
        assert(tablist ~= nil)

        local super = false
        local shift = false
        local ctrl = false
        for i, m in ipairs(mod) do
            if m == "Mod4" then super = true
            elseif m == "Shift" then shift = true
            elseif m == "Control" then ctrl = true
            end
        end

        if key == "Tab" then
            tab()
        elseif key == "Up" or key == "Down" or key == "Left" or key == "Right" then
            traverse_areas(key, shift or super, ctrl)
        elseif (key == "q" or key == "Prior") then
            local current_area = selected_area()
            if areas[current_area].parent_id == nil then
                return
            end

            set_selected_area(areas[current_area].parent_id)
            if #parent_stack == 0 or
                parent_stack[#parent_stack] ~= current_area then
                parent_stack = {current_area}
            end
            parent_stack[#parent_stack + 1] = areas[current_area].parent_id
            current_area = parent_stack[#parent_stack]

            if c and ctrl and cd[c].draft ~= false then
                if cd[c].area then
                    cd[c].lu, cd[c].rd, cd[c].area = cd[c].area, cd[c].area, nil
                end
                machi.layout.set_geometry(c, areas[current_area], areas[current_area], 0, c.border_width)
                awful.layout.arrange(screen)
            end

            draw()
        elseif (key =="e" or key == "Next") then
            local current_area = selected_area()
            if #parent_stack <= 1 or parent_stack[#parent_stack] ~= current_area then
                return
            end

            set_selected_area(parent_stack[#parent_stack - 1])
            table.remove(parent_stack, #parent_stack)
            current_area = parent_stack[#parent_stack]

            if c and ctrl then
                if areas[current_area].habitable and cd[c].draft ~= true then
                    cd[c].lu, cd[c].rd, cd[c].area = nil, nil, current_area
                end
                machi.layout.set_geometry(c, areas[current_area], areas[current_area], 0, c.border_width)
                awful.layout.arrange(screen)
            end

            draw()
        elseif key == "/" then
            local current_area = selected_area()
            local original_cmd = machi.engine.areas_to_command(areas, true, current_area)
            areas[current_area].hole = true
            local prefix, suffix = machi.engine.areas_to_command(
                areas, false):match("(.*)|(.*)")
            areas[current_area].hole = nil

            workarea = {
                x = areas[current_area].x - gap * 2,
                y = areas[current_area].y - gap * 2,
                width = areas[current_area].width + gap * 4,
                height = areas[current_area].height + gap * 4,
            }
            gtimer.delayed_call(
                function ()
                    layout.machi_editor.start_interactive(
                        screen,
                        {
                            workarea = workarea,
                            original_cmd = original_cmd,
                            cmd_prefix = prefix,
                            cmd_suffix = suffix,
                        }
                    )
                end
            )
            exit()
        elseif (key == "f" or key == ".") and c then
            if cd[c].draft == nil then
                cd[c].draft = true
            elseif cd[c].draft == true then
                cd[c].draft = false
            else
                cd[c].draft = nil
            end
            awful.layout.arrange(screen)
        elseif key == "Escape" or key == "Return" then
            exit()
        else
            log(DEBUG, "Unhandled key " .. key)
        end
    end

    local ui = function()
        infobox = wibox({
                screen = screen,
                x = screen.workarea.x,
                y = screen.workarea.y,
                width = 1, -- screen.workarea.width,
                height = 1, --screen.workarea.height,
                bg = "#ffffff00",
                opacity = 1,
                ontop = false,
                type = "normal",
        })
        infotabbox = wibox({
                screen = screen,
                x = screen.workarea.x,
                y = screen.workarea.y,
                width = 1,
                height = 1,
                bg = "#ffffff00",
                ontop = true,
                type = "normal",
                visible = true,
        })

        draw()

        awful.client.focus.history.disable_tracking()
        local kg
        local function exit()
            awful.client.focus.history.enable_tracking()
            if capi.client.focus then
                capi.client.emit_signal("focus", capi.client.focus)
            end
            infobox.visible = false
            infotabbox.visible = false
            awful.keygrabber.stop(kg)
        end

        kg = awful.keygrabber.run(
            function (...)
                ok, _ = pcall(handle_key, ...)
                if not ok then exit() end
            end
        )
    end

    return {
        ui = ui,
        tab = tab,
        snap_client = snap_client,
        master_add = master_add,
        --- swap current window with 'master' or moves it to the master position if it's unoccupied (i.e.: largest area/client)
        -- @param all      swap/move all clients in both areas, not just the top ones.
        master_swap = master_swap,
        --- focus client by direction
        -- @param dir      direction (up|right|down|left)
        -- @returns true if a client was found
        traverse_clients = traverse_clients,
        traverse_areas = traverse_areas,
        move = function(dir) traverse_areas(dir, true, false) end,
        -- like traverse_clients, returns true if a client was found
        focus = function(dir) return traverse_clients(dir) end,
    }
end

return module

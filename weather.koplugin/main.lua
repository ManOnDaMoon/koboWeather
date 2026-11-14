local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local Button = require("ui/widget/button")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local ImageWidget = require("ui/widget/imagewidget")
local Font = require("ui/font")
local Device = require("device")
local NetworkMgr = require("ui/network/manager")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local logger = require("logger")
local socket_ok = pcall(require, "socket")
local http_ok, http = pcall(require, "socket.http")
local https_ok, https = pcall(require, "ssl.https")
local ltn12_ok, ltn12 = pcall(require, "ltn12")
local _ = require("gettext")
local Screen = Device.screen

local Weather = WidgetContainer:extend{
    name = "weather",
    is_doc_only = false,
    config = nil,
    task = nil,
    network_timeout_task = nil,
    wakeup_callback = nil,
    resume_classify_task = nil,
    dialog = nil,
    cookie = nil,
    last_body = nil,
    last_values = nil,
    last_update = nil,
    last_error = nil,
    running = false,
    original_rotation = nil,
    refreshing = false,
    suspended = false,
    rtc_wake_pending = false,
    rtc_cycle_active = false,
    user_activity = 0,
    low_battery_protected = false,
}

local DashboardView = InputContainer:extend{
    name = "weather_dashboard",
    modal = true,
    owner = nil,
}

local function metric_card(label, value, width, height, landscape, value_size)
    local inset = Screen:scaleBySize(12)
    local inner_width = math.max(width - inset * 2, 20)
    local inner_height = math.max(height - inset * 2, 20)
    local label_size = Screen:scaleBySize(landscape and 21 or 20)
    local content
    if landscape then
        content = VerticalGroup:new{
            align = "center",
            TextBoxWidget:new{
                text = label,
                width = inner_width,
                face = Font:getFace("infofont", label_size),
                alignment = "center",
            },
            TextBoxWidget:new{
                text = value or "—",
                width = inner_width,
                face = Font:getFace("infofont", Screen:scaleBySize(value_size)),
                bold = true,
                alignment = "center",
            },
        }
    else
        local label_width = math.floor(inner_width * 0.38)
        content = HorizontalGroup:new{
            align = "center",
            TextBoxWidget:new{
                text = label,
                width = label_width,
                face = Font:getFace("infofont", label_size),
                alignment = "left",
            },
            TextBoxWidget:new{
                text = value or "—",
                width = inner_width - label_width,
                face = Font:getFace("infofont", Screen:scaleBySize(value_size)),
                bold = true,
                alignment = "right",
            },
        }
    end
    return FrameContainer:new{
        width = width,
        height = height,
        margin = 0,
        padding = inset,
        bordersize = Screen:scaleBySize(2),
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_width, h = inner_height },
            content,
        },
    }
end

local function weather_card(condition, width, height, landscape)
    local inset = Screen:scaleBySize(12)
    local inner_width = math.max(width - inset * 2, 20)
    local inner_height = math.max(height - inset * 2, 20)
    local icon_size = math.min(
        Screen:scaleBySize(landscape and 76 or 64),
        math.floor(inner_height * 0.58),
        math.floor(inner_width * 0.34)
    )
    local content = VerticalGroup:new{
        align = "center",
        ImageWidget:new{
            file = "/mnt/onboard/.adds/koreader/plugins/weather.koplugin/icons/" .. condition.icon,
            width = icon_size,
            height = icon_size,
            is_icon = true,
        },
        TextBoxWidget:new{
            text = condition.label,
            width = inner_width,
            face = Font:getFace("infofont", Screen:scaleBySize(landscape and 21 or 19)),
            bold = true,
            alignment = "center",
        },
    }
    return FrameContainer:new{
        width = width,
        height = height,
        margin = 0,
        padding = inset,
        bordersize = Screen:scaleBySize(2),
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_width, h = inner_height },
            content,
        },
    }
end

local function detail_cell(item, width, height)
    local content = VerticalGroup:new{
        align = "center",
        TextBoxWidget:new{
            text = item[1],
            width = width,
            face = Font:getFace("infofont", Screen:scaleBySize(12)),
            alignment = "center",
        },
        TextBoxWidget:new{
            text = item[2] or "—",
            width = width,
            face = Font:getFace("infofont", Screen:scaleBySize(14)),
            bold = true,
            alignment = "center",
        },
    }
    return CenterContainer:new{
        dimen = Geom:new{ w = width, h = height },
        content,
    }
end

function DashboardView:init()
    local width, height = Screen:getWidth(), Screen:getHeight()
    self.dimen = Screen:getSize()
    local padding = Screen:scaleBySize(8)
    local gap = Screen:scaleBySize(5)
    local landscape = width > height
    local columns = landscape and 2 or 1
    local metrics = self.owner:_primaryMetricList()
    local rows = math.ceil(#metrics / columns)
    local header_height = Screen:scaleBySize(60)
    local secondary_height = Screen:scaleBySize(84)
    local vertical_safety_margin = Screen:scaleBySize(30)
    local vertical_gaps = rows - 1 + 2
    local fixed_height = header_height + secondary_height + vertical_safety_margin + padding * 2 + gap * vertical_gaps
    local card_height = math.floor((height - fixed_height) / rows)
    local card_width = math.floor((width - padding * 2 - gap * (columns - 1)) / columns)
    local inner_width = width - padding * 2

    local close_button_size = Screen:scaleBySize(40)
    local header_content = VerticalGroup:new{
        align = "center",
        HorizontalGroup:new{
            align = "center",
            TextBoxWidget:new{
                text = self.owner.station_name or self.owner.config.station_name or "Station météo",
                width = inner_width - close_button_size - gap,
                face = Font:getFace("infofont", Screen:scaleBySize(landscape and 24 or 22)),
                bold = true,
                alignment = "left",
            },
            HorizontalSpan:new{ width = gap },
            Button:new{
                text = "X",
                width = close_button_size,
                height = close_button_size,
                padding = 0,
                bordersize = Screen:scaleBySize(1),
                text_font_size = Screen:scaleBySize(22),
                callback = function() self.owner:_minimize() end,
            },
        },
        TextBoxWidget:new{
            text = self.owner:_lastUpdateText(),
            width = inner_width,
            face = Font:getFace("infofont", Screen:scaleBySize(13)),
            alignment = "center",
        },
    }
    local header = FrameContainer:new{
        width = inner_width,
        height = header_height,
        margin = 0,
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_width, h = header_height },
            header_content,
        },
    }

    local grid = VerticalGroup:new{ align = "left" }
    for start = 1, #metrics, columns do
        local row = HorizontalGroup:new{ align = "top" }
        for column = 0, columns - 1 do
            local item = metrics[start + column]
            if item then
                local card
                if item.kind == "weather" then
                    card = weather_card(item.condition, card_width, card_height, landscape)
                else
                    card = metric_card(item[1], item[2], card_width, card_height, landscape, item[3])
                end
                table.insert(row, card)
            else
                table.insert(row, VerticalSpan:new{ width = card_width })
            end
            if column < columns - 1 then
                table.insert(row, HorizontalSpan:new{ width = gap })
            end
        end
        table.insert(grid, row)
        if start + columns <= #metrics then
            table.insert(grid, VerticalSpan:new{ width = gap })
        end
    end

    local secondary_metrics = self.owner:_secondaryMetricList()
    local detail_columns = #secondary_metrics
    local detail_row = HorizontalGroup:new{ align = "center" }
    local detail_cell_width = math.floor((inner_width - gap * (detail_columns - 1)) / detail_columns)
    for index = 1, detail_columns do
        table.insert(detail_row, detail_cell(secondary_metrics[index], detail_cell_width, secondary_height))
        if index < detail_columns then
            table.insert(detail_row, HorizontalSpan:new{ width = gap })
        end
    end

    local content = VerticalGroup:new{
        align = "center",
        header,
        VerticalSpan:new{ width = gap },
        grid,
        VerticalSpan:new{ width = gap },
        detail_row,
    }
    self[1] = FrameContainer:new{
        width = width,
        height = height,
        margin = 0,
        padding = padding,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{ w = width - padding * 2, h = height - padding * 2 },
            ignore_if_over = "height",
            content,
        },
    }
end

local plugin_dir = ".adds/koreader/plugins/weather.koplugin/"

local function load_config()
    local paths = {
        "/mnt/onboard/" .. plugin_dir .. "config.lua",
        "/mnt/onboard/.adds/koreader/plugins/weather.koplugin/config.lua",
    }
    for _, path in ipairs(paths) do
        local chunk = loadfile(path)
        if chunk then
            local ok, value = pcall(chunk)
            if ok and type(value) == "table" then return value end
        end
    end
    return nil
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function unescape(s)
    return (s:gsub("&nbsp;", " "):gsub("&#160;", " "):gsub("&deg;", "°")
        :gsub("&amp;", "&"):gsub("&quot;", '"'):gsub("&#39;", "'")
        :gsub("&lt;", "<"):gsub("&gt;", ">"))
end

local function strip_tags(s)
    return trim(unescape(s:gsub("<[^>]->", " "):gsub("%s+", " ")))
end

local function request(url, method, body, cookie)
    if not (socket_ok and ltn12_ok) then return nil, "KOReader socket modules unavailable" end
    local headers = {
        ["User-Agent"] = "KoboWeather/0.1 KOReader",
        ["Connection"] = "close",
    }
    if cookie then headers.Cookie = cookie end
    if body then
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        headers["Content-Length"] = tostring(#body)
    end
    local sink = {}
    local opts = {
        url = url,
        method = method or "GET",
        headers = headers,
        source = body and ltn12.source.string(body) or nil,
        sink = ltn12.sink.table(sink),
        redirect = false,
        timeout = 20,
    }
    local client = url:match("^https:") and (https_ok and https or nil) or (http_ok and http or nil)
    if not client then return nil, "KOReader HTTPS module unavailable" end
    local result, code, response_headers = client.request(opts)
    if not result then return nil, tostring(code or "network error") end
    local set_cookie = response_headers and (response_headers["set-cookie"] or response_headers["Set-Cookie"])
    return table.concat(sink), tonumber(code), response_headers, set_cookie
end

local function encode_form(s)
    return (tostring(s or ""):gsub("\n", "\r\n"):gsub("([^%w%-_%.~ ])", function(c)
        return string.format("%%%02X", string.byte(c))
    end):gsub(" ", "+"))
end

local function cookie_pair(header)
    if type(header) == "table" then header = header[1] end
    if type(header) ~= "string" then return nil end
    return header:match("^%s*([^;]+)")
end

local function merge_cookie(existing, incoming_header)
    local pair = cookie_pair(incoming_header)
    if not pair then return existing end
    local key = pair:match("^([^=]+)=")
    if not key then return existing or pair end
    local entries, replaced = {}, false
    for item in (existing or ""):gmatch("[^;]+") do
        item = trim(item)
        if item:match("^([^=]+)=") == key then
            entries[#entries + 1] = pair
            replaced = true
        else
            entries[#entries + 1] = item
        end
    end
    if not replaced then entries[#entries + 1] = pair end
    return table.concat(entries, "; ")
end

function Weather:_fetch()
    local cfg = self.config
    local base = cfg.base_url:gsub("/+$", "")
    local login_url = base .. "/login"
    local station_url = base .. "/station/" .. cfg.station_id
    if self.cookie then
        local cached_page, cached_code, _, cached_cookie = request(station_url, "GET", nil, self.cookie)
        self.cookie = merge_cookie(self.cookie, cached_cookie)
        if cached_page and cached_code == 200 and not cached_page:find('name="password"') then
            return cached_page
        end
        self.cookie = nil
    end
    local body, code, _, set_cookie = request(login_url, "GET")
    if not body or not code or code >= 400 then return nil, "Cannot open login page" end
    local cookie = merge_cookie(nil, set_cookie)
    local post = "username=" .. encode_form(cfg.username) .. "&password=" .. encode_form(cfg.password)
    local _, post_code, _, post_cookie = request(login_url, "POST", post, cookie)
    cookie = merge_cookie(cookie, post_cookie)
    local page, page_code, _, page_cookie = request(station_url, "GET", nil, cookie)
    cookie = merge_cookie(cookie, page_cookie)
    if not page or not page_code or page_code >= 400 then return nil, "Cannot load station page" end
    if page:find('name="password"') or page:find("/login") then
        return nil, "Login rejected or session expired"
    end
    self.cookie = cookie
    return page
end

local function parse_card_section(cards, section_title, section)
    local in_indoor_section = section_title:lower():find("intérieur", 1, true) ~= nil
    for header, content in section:gmatch("<header[^>]*>(.-)</header>(.-)</article>") do
        local label = strip_tags(header):lower()
        local value = content:match("<h1[^>]*>(.-)</h1>")
        if value then
            value = strip_tags(value)
            if label:find("température", 1, true) then
                local explicitly_indoor = label:find("intérieure", 1, true) or label:find("indoor", 1, true)
                local explicitly_outdoor = label:find("extérieure", 1, true) or label:find("outdoor", 1, true)
                if explicitly_indoor or (in_indoor_section and not explicitly_outdoor) then
                    cards["Température intérieure"] = value
                else
                    cards["Température"] = value
                end
            elseif label:find("humidité", 1, true) then
                if in_indoor_section then cards["Humidité intérieure"] = value
                else cards["Humidité"] = value end
            elseif label:find("pression", 1, true) then cards["Pression"] = value
            elseif label:find("rosée", 1, true) then cards["Point de rosée"] = value
            elseif label:find("quotidienne", 1, true) then cards["Pluie du jour"] = value
            elseif label:find("intensité", 1, true) then cards["Pluie"] = value
            elseif label:find("rayonnement", 1, true) then cards["Solaire"] = value
            elseif label:find("indice uv", 1, true) then cards["Indice UV"] = value
            elseif label:find("vitesse du vent", 1, true) then cards["Vent"] = value
            elseif label:find("rafale", 1, true) then cards["Rafale"] = value
            elseif label:find("direction", 1, true) then cards["Direction"] = value
        end
    end
end
end

local function parse_measurements(page)
    local cards = {}
    local position, found_section = 1, false
    while true do
        local heading_start, heading_end, title = page:find("<h2[^>]*>(.-)</h2>", position)
        if not heading_start then break end
        found_section = true
        local next_heading = page:find("<h2[^>]*>", heading_end + 1)
        local section_end = next_heading and (next_heading - 1) or #page
        parse_card_section(cards, strip_tags(title), page:sub(heading_end + 1, section_end))
        if not next_heading then break end
        position = next_heading
    end
    if not found_section then parse_card_section(cards, "", page) end
    if not cards["Température"] then return nil end
    return cards
end

local function metric_number(value)
    if not value then return nil end
    local numeric = tostring(value):gsub(",", "."):match("[-+]?%d+%.?%d*")
    return tonumber(numeric)
end

function Weather:_primaryMetricList()
    local values = self.last_values or {}
    return {
        { "TEMP. EXTÉRIEURE", values["Température"] or "—", 64 },
        { kind = "weather", condition = self:_weatherCondition() },
        { "PLUIE / JOUR", values["Pluie du jour"] or "—", 64 },
        { "TEMP. INTÉRIEURE", values["Température intérieure"] or "—", 60 },
    }
end

function Weather:_secondaryMetricList()
    local values = self.last_values or {}
    local wind = values["Vent"] or "—"
    local wind_label = "VENT"
    if values["Rafale"] then
        local wind_speed, wind_unit = wind:match("^(.-)%s*(%S+)$")
        local gust_speed, gust_unit = values["Rafale"]:match("^(.-)%s*(%S+)$")
        if wind_unit and gust_unit == wind_unit then
            wind = wind_speed:gsub("%s+$", "") .. "/" .. gust_speed:gsub("%s+$", "") .. " " .. wind_unit
        else
            wind = wind .. "/" .. values["Rafale"]
        end
        wind_label = "VENT/RAF."
    end
    return {
        { "HUMIDITÉ", values["Humidité"] },
        { "PRESSION", values["Pression"] },
        { wind_label, wind },
        { "PLUIE/H", values["Pluie"] },
        { "SOLEIL", values["Solaire"] },
        { "UV", values["Indice UV"] },
    }
end

function Weather:_weatherCondition()
    local values = self.last_values or {}
    local rain = metric_number(values["Pluie"])
    local solar = metric_number(values["Solaire"])
    if rain and rain >= 10 then
        return { icon = "storm.svg", label = "ORAGE" }
    elseif rain and rain > 0 then
        return { icon = "rain.svg", label = "PLUIE" }
    elseif solar and solar >= 300 then
        return { icon = "sun.svg", label = "SOLEIL" }
    elseif solar and solar >= 80 then
        return { icon = "partly-cloudy.svg", label = "NUAGEUX" }
    elseif solar then
        return { icon = "cloud.svg", label = "COUVERT" }
    end
    return { icon = "cloud.svg", label = "MÉTÉO INDISPONIBLE" }
end

function Weather:_statusText()
    local text = self.last_update and ("Mis à jour le " .. os.date("%d/%m/%Y à %H:%M", self.last_update))
        or "Récupération des données météo…"
    text = text .. "  ·  Actualisation toutes les " .. tostring(self.config.interval_minutes) .. " min"
    if self.last_error then text = text .. "  ·  " .. self.last_error end
    return text
end

function Weather:_lastUpdateText()
    local battery_label = "Batterie : —"
    local powerd = Device and Device.powerd
    if powerd and powerd.getCapacity then
        local ok, capacity = pcall(powerd.getCapacity, powerd)
        if ok and type(capacity) == "number" then
            battery_label = "Batterie : " .. tostring(math.floor(capacity + 0.5)) .. " %"
        end
    end

    if self.last_update then
        local text = "Dernière mise à jour : " .. os.date("%d/%m/%Y à %H:%M", self.last_update)
            .. " · " .. battery_label
        if self.last_error then text = text .. " · " .. self.last_error end
        return text
    end
    if self.last_error then
        return "Dernière mise à jour indisponible · " .. battery_label .. " · " .. self.last_error
    end
    return "Dernière mise à jour : récupération en cours… · " .. battery_label
end

function Weather:_batteryCapacity()
    local powerd = Device and Device.powerd
    if not (powerd and powerd.getCapacity) then return nil end
    local ok, capacity = pcall(powerd.getCapacity, powerd)
    if ok and type(capacity) == "number" then return capacity end
    return nil
end

function Weather:_batteryThresholdReached()
    local threshold = tonumber(self.config and self.config.low_battery_threshold)
    local capacity = self:_batteryCapacity()
    return threshold and threshold >= 0 and capacity and capacity <= threshold or false
end

function Weather:_protectLowBattery()
    if self.low_battery_protected or not self:_batteryThresholdReached() then return false end
    self.low_battery_protected = true
    if self.task then UIManager:unschedule(self.task); self.task = nil end
    self:_removeWakeup()
    self:_cancelNetworkTimeout()
    self.refreshing = false
    local function suspend_now()
        if self.running then UIManager:suspend() end
    end
    if NetworkMgr:isWifiOn() then
        NetworkMgr:disableWifi(suspend_now, false)
    else
        suspend_now()
    end
    return true
end

function Weather:_renderDashboard()
    if self.dialog then UIManager:close(self.dialog) end
    self.dialog = DashboardView:new{ owner = self }
    UIManager:show(self.dialog)
    UIManager:setDirty(self.dialog, "full")
end

function Weather:_refresh()
    if self:_protectLowBattery() then return false end
    local page, err = self:_fetch()
    if not page then
        logger.warn("Weather plugin: " .. tostring(err))
        self.last_error = "Échec réseau à " .. os.date("%H:%M")
        self:_renderDashboard()
        return false
    end
    local values = parse_measurements(page)
    if not values then
        logger.warn("Weather plugin: station HTML not recognized")
        self.last_error = "Format meteodb non reconnu"
        self:_renderDashboard()
        return false
    end
    local title = page:match("<h1[^>]*>(.-)</h1>")
    self.station_name = title and strip_tags(title) or self.config.station_name
    self.last_values = values
    self.last_update = os.time()
    self.last_error = nil
    self:_renderDashboard()
    return true
end

function Weather:_cancelNetworkTimeout()
    if self.network_timeout_task then
        UIManager:unschedule(self.network_timeout_task)
        self.network_timeout_task = nil
    end
end

function Weather:_scheduleWakeup()
    if not (self.running and not self.low_battery_protected and Device.wakeup_mgr and Device:canSuspend()) then return end
    self:_removeWakeup()
    self.wakeup_callback = function()
        if not self.running then return end
        self.rtc_wake_pending = true
        -- Resume processing is still running when WakeupMgr invokes us.
        UIManager:nextTick(function()
            if self.running and self.rtc_wake_pending then
                self.rtc_wake_pending = false
                self.rtc_cycle_active = true
                self:_refreshWithWifi(true)
            end
        end)
    end
    Device.wakeup_mgr:addTask((tonumber(self.config.interval_minutes) or 15) * 60, self.wakeup_callback)
end

function Weather:_removeWakeup()
    if Device.wakeup_mgr and self.wakeup_callback then
        Device.wakeup_mgr:removeTasks(nil, self.wakeup_callback)
    end
    self.wakeup_callback = nil
end

function Weather:_finishRefresh(should_suspend)
    self:_cancelNetworkTimeout()
    self.refreshing = false
    if self:_protectLowBattery() then return end
    -- Keep KOReader's wifi_was_on marker intact. With auto_restore_wifi enabled,
    -- KOReader can restore the connection after manual resume or a reboot.
    local function finish_power_cycle()
        if not should_suspend or not self.running then return end
        self.rtc_cycle_active = false
        if self.user_activity == self.refresh_activity then
            if Device.wakeup_mgr and Device:canSuspend() then
                -- Arm the next RTC wake before entering system suspend.
                self:_scheduleWakeup()
                UIManager:suspend()
            else
                -- Without RTC wake support, keep KOReader active for its timer.
                self:_schedule()
            end
        else
            -- Keep the dashboard awake after interaction during a refresh.
            if Device.suspend then UIManager:unschedule(Device.suspend) end
            self:_removeWakeup()
            self:_schedule()
        end
    end

    if NetworkMgr:isWifiOn() then
        NetworkMgr:disableWifi(finish_power_cycle, false)
    else
        finish_power_cycle()
    end
end

function Weather:_refreshWithWifi(should_suspend)
    if not self.running or self.low_battery_protected or self.refreshing then return end
    self.refreshing = true
    -- This guard is per refresh cycle: a stale true value would make all
    -- subsequent network callbacks return without fetching or powering Wi-Fi off.
    self.refresh_attempted = false
    self.refresh_activity = self.user_activity
    local function refresh_now()
        if not self.running or not self.refreshing then return end
        if self.refresh_attempted then return end
        self.refresh_attempted = true
        if should_suspend and Device.suspend then UIManager:unschedule(Device.suspend) end
        self:_refresh()
        self:_finishRefresh(should_suspend)
    end

    if NetworkMgr:isConnected() then
        refresh_now()
        return
    end

    local elapsed = 0
    local function check_connection()
        if not self.refreshing then return end
        -- Kobo schedules a return-to-sleep timer shortly after an RTC wake.
        -- Keep that timer from interrupting the asynchronous Wi-Fi reconnect.
        if should_suspend and Device.suspend then UIManager:unschedule(Device.suspend) end
        if NetworkMgr:isConnected() then
            refresh_now()
        elseif elapsed >= 50 then
            self.last_error = "Connexion Wi-Fi indisponible"
            self:_renderDashboard()
            self:_finishRefresh(should_suspend)
        else
            elapsed = elapsed + 1
            UIManager:scheduleIn(1, check_connection)
        end
    end
    self.network_timeout_task = check_connection
    UIManager:scheduleIn(1, check_connection)
    NetworkMgr:enableWifi(refresh_now, false)
end

function Weather:_schedule()
    if self.low_battery_protected then return end
    if self.task then UIManager:unschedule(self.task) end
    self.task = function()
        if not self.running or self.low_battery_protected then return end
        if self:_protectLowBattery() then return end
        self:_refreshWithWifi(false)
        if self.running then
            UIManager:scheduleIn((tonumber(self.config.interval_minutes) or 15) * 60, self.task)
        end
    end
    UIManager:scheduleIn((tonumber(self.config.interval_minutes) or 15) * 60, self.task)
end

function Weather:_stopTimer()
    if self.task then
        UIManager:unschedule(self.task)
        self.task = nil
    end
    self.running = false
    self:_cancelNetworkTimeout()
    self:_removeWakeup()
    if self.resume_classify_task then
        UIManager:unschedule(self.resume_classify_task)
        self.resume_classify_task = nil
    end
end

function Weather:_minimize()
    self:_stopTimer()
    if self.dialog then UIManager:close(self.dialog); self.dialog = nil end
    if self.original_rotation and Screen:getRotationMode() ~= self.original_rotation then
        Screen:setRotationMode(self.original_rotation)
        UIManager:setDirty(nil, "full")
    end
    self.original_rotation = nil
end

function Weather:_closeDashboard()
    self:_minimize()
    self.last_values = nil
    self.last_update = nil
    self.last_error = nil
    self.cookie = nil
end

function Weather:_toggleOrientation()
    local target = (Screen:getRotationMode() % 2 == 0)
        and Screen.DEVICE_ROTATED_CLOCKWISE or Screen.DEVICE_ROTATED_UPRIGHT
    G_reader_settings:saveSetting("weather_rotation_mode", target)
    Screen:setRotationMode(target)
    if self.dialog then UIManager:close(self.dialog); self.dialog = nil end
    UIManager:setDirty(nil, "full")
    UIManager:scheduleIn(0.2, function()
        if self.running then self:_renderDashboard() end
    end)
end

function Weather:onWeather()
    if not self.config then self.config = load_config() end
    if not self.config or not self.config.base_url or not self.config.station_id then
        UIManager:show(InfoMessage:new{
            text = "Configurer config.lua dans weather.koplugin avant utilisation.",
            timeout = 8,
        })
        return true
    end
    local interval = tonumber(self.config.interval_minutes)
    if not interval or interval < 1 then interval = 15 end
    self.config.interval_minutes = interval
    local threshold = tonumber(self.config.low_battery_threshold)
    if not threshold or threshold < 0 or threshold > 100 then threshold = 10 end
    self.config.low_battery_threshold = threshold
    self.low_battery_protected = false
    self.station_name = self.config.station_name
    self.running = true
    self.original_rotation = Screen:getRotationMode()
    local wanted_rotation = G_reader_settings:readSetting("weather_rotation_mode")
    if not wanted_rotation then
        wanted_rotation = Screen.DEVICE_ROTATED_CLOCKWISE
        G_reader_settings:saveSetting("weather_rotation_mode", wanted_rotation)
    end
    if wanted_rotation ~= Screen:getRotationMode() then
        Screen:setRotationMode(wanted_rotation)
    end
    G_reader_settings:makeTrue("auto_restore_wifi")
    self:_refreshWithWifi(true)
    return true
end

function Weather:onSuspend()
    if not self.running then return end
    self.suspended = true
    if self.task then UIManager:unschedule(self.task) end
    if self.refreshing then
        self:_cancelNetworkTimeout()
        self.refreshing = false
        if NetworkMgr:isWifiOn() then NetworkMgr:disableWifi(nil, false) end
    end
    self:_scheduleWakeup()
end

function Weather:onResume()
    if not self.running then return end
    self.suspended = false
    if self.low_battery_protected then return end
    if self.rtc_wake_pending or self.rtc_cycle_active then return end
    if not self.wakeup_callback then
        self:_refreshWithWifi(true)
        return
    end
    -- Kobo validates RTC alarms shortly after resume. Defer classification so
    -- a scheduled wake is not mistaken for a manual one and canceled too early.
    if self.resume_classify_task then UIManager:unschedule(self.resume_classify_task) end
    self.resume_classify_task = function()
        self.resume_classify_task = nil
        if not self.running or self.rtc_cycle_active or self.rtc_wake_pending then return end
        self:_removeWakeup()
        self:_refreshWithWifi(true)
    end
    UIManager:scheduleIn(17, self.resume_classify_task)
end

function Weather:onInputEvent()
    self.user_activity = self.user_activity + 1
    if self.rtc_cycle_active and Device.suspend then UIManager:unschedule(Device.suspend) end
    if self.resume_classify_task then
        UIManager:unschedule(self.resume_classify_task)
        self.resume_classify_task = nil
        if not self.rtc_cycle_active then
            self:_removeWakeup()
            self:_refreshWithWifi(true)
        end
    end
end

function Weather:init()
    self.ui.menu:registerToMainMenu(self)
end

function Weather:addToMainMenu(menu_items)
    menu_items.weather = {
        text = _("Météo meteodb"),
        sorting_hint = "tools",
        callback = function() self:onWeather() end,
    }
    menu_items.weather_stop = {
        text = _("Arrêter l'actualisation météo"),
        sorting_hint = "tools",
        callback = function()
            self:_closeDashboard()
        end,
    }
end

function Weather:onClose()
    self:_closeDashboard()
end

return Weather

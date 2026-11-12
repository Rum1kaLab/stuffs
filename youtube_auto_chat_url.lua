/*
 * Copyright (C) 2026, Rum1kaLab
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

local obs = obslua

local SCRIPT_NAME = "YouTube Chat Auto URL"
local DEFAULT_BROWSER_SOURCE = "Comment Box"
local CHAT_URL = "https://www.youtube.com/live_chat?is_popout=1&v=%s"

local browser_source_name = DEFAULT_BROWSER_SOURCE

local startup_retry_count = 0
local startup_retry_max = 10
local startup_retry_interval_ms = 1000
local startup_retry_pending = false

local function log(message)
    obs.script_log(obs.LOG_INFO, "[" .. SCRIPT_NAME .. "] " .. message)
end

local function warn(message)
    obs.script_log(obs.LOG_WARNING, "[" .. SCRIPT_NAME .. "] " .. message)
end

local function error_log(message)
    obs.script_log(obs.LOG_ERROR, "[" .. SCRIPT_NAME .. "] " .. message)
end

function script_description()
    return [[
<h2>YouTube Chat Auto URL</h2>
<p>When you start a YouTube stream in OBS, the script retrieves the Video ID from OBS's internal stream information and automatically updates the YouTube live chat URL of the specified browser source.</p>
<p><b>It does not search for live streams on YouTube.</b> It directly uses the <code>broadcast_id</code> currently selected in OBS.</p>
]]
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "browser_source_name", DEFAULT_BROWSER_SOURCE)
end

function get_broadcast_id()
    local service = obs.obs_frontend_get_streaming_service()
    if not service then
        return nil
    end

    local settings = obs.obs_service_get_settings(service)
    if not settings then
        return nil
    end

    local broadcast_id = obs.obs_data_get_string(settings, "broadcast_id")
    obs.obs_data_release(settings)

    broadcast_id = broadcast_id:match("^%s*(.-)%s*$")
    if broadcast_id == "" then
        return nil
    end

    return broadcast_id
end

function update_browser_url(video_id)
    local source = obs.obs_get_source_by_name(browser_source_name)
    if not source then
        warn("Browser source \"" .. browser_source_name .. "\" not found.")
        return false
    end

    if obs.obs_source_get_id(source) ~= "browser_source" then
        warn("\"" .. browser_source_name .. "\" is not a browser source.")
        obs.obs_source_release(source)
        return false
    end

    local settings = obs.obs_source_get_settings(source)
    local new_url = string.format(CHAT_URL, video_id)

    obs.obs_data_set_string(settings, "url", new_url)
    obs.obs_source_update(source, settings)

    obs.obs_data_release(settings)
    obs.obs_source_release(source)

    log("URL of \"" .. browser_source_name .. "\" updated: " .. new_url)
    return true
end

local function on_test_update(props, prop)
    local video_id = get_broadcast_id()

    if not video_id then
        warn("Failed to retrieve Video ID. Please select a broadcast in 'Stream Manager' and try again.")
        return true
    end

    log("Test: Video ID retrieved successfully: " .. video_id)
    update_browser_url(video_id)
    return true
end

function script_properties()
    local props = obs.obs_properties_create()

    local source_list = obs.obs_properties_add_list(
        props,
        "browser_source_name",
        "Comment Display Browser Source",
        obs.OBS_COMBO_TYPE_EDITABLE,
        obs.OBS_COMBO_FORMAT_STRING
    )

    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            if obs.obs_source_get_id(source) == "browser_source" then
                local name = obs.obs_source_get_name(source)
                if name and name ~= "" then
                    obs.obs_property_list_add_string(source_list, name, name)
                end
            end
        end
        obs.source_list_release(sources)
    end

    obs.obs_properties_add_button(props, "test_update", "Test URL Update Now", on_test_update)

    return props
end

function script_update(settings)
    local name = obs.obs_data_get_string(settings, "browser_source_name")
    if name == nil or name == "" then
        name = DEFAULT_BROWSER_SOURCE
    end
    browser_source_name = name
end

local function startup_retry_tick()
    if not startup_retry_pending then
        obs.timer_remove(startup_retry_tick)
        return
    end

    startup_retry_count = startup_retry_count + 1

    local video_id = get_broadcast_id()

    if video_id then
        startup_retry_pending = false
        obs.timer_remove(startup_retry_tick)

        log(string.format("Video ID retrieved successfully (%d/%d): %s",
            startup_retry_count, startup_retry_max, video_id))
        update_browser_url(video_id)
        return
    end

    if startup_retry_count >= startup_retry_max then
        startup_retry_pending = false
        obs.timer_remove(startup_retry_tick)

        warn("Failed to retrieve Video ID. Please check that OBS is linked to your YouTube account and that a broadcast is selected in 'Stream Manager'.")
        return
    end

    log(string.format("Video ID not yet retrieved (%d/%d). Retrying in 1 second.",
        startup_retry_count, startup_retry_max))
end

local function on_frontend_event(event)
    if event == obs.OBS_FRONTEND_EVENT_STREAMING_STARTED then
        log("OBS streaming start event detected.")

        startup_retry_count = 0
        startup_retry_pending = true

        obs.timer_remove(startup_retry_tick)
        -- Video ID may not be available immediately after stream start, so retry every second up to 10 times
        obs.timer_add(startup_retry_tick, startup_retry_interval_ms)

    elseif event == obs.OBS_FRONTEND_EVENT_STREAMING_STOPPED then
        startup_retry_pending = false
        obs.timer_remove(startup_retry_tick)
    end
end

function script_load(settings)
    obs.obs_frontend_add_event_callback(on_frontend_event)
    log("Script loaded.")
    log("Automatically updates the YouTube chat URL when streaming starts.")
end

function script_unload()
    startup_retry_pending = false
    obs.timer_remove(startup_retry_tick)
    obs.obs_frontend_remove_event_callback(on_frontend_event)
end

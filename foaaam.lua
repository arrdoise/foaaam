--
--          foaaam
--                  pitch-shifter    
--              delay /         
--                looper    
--
--      #####                   
--    #+    + #         
--   #    +++  #    
--   #  +  ++  #       ####      
--   #  ++    #      #      #                           
--     #####      #    ++   #              
--                  #  ++     #                    
--                   #+ ++   #                                  
--                     ####               
--                       
-- foam bubbles as you play.
-- grid optional.
-- navigate pages with enc1.
--
-- -----------------------
--
-- page 1, live, loop & bpm
--
-- hold key1 + enc2 =
-- change mode
-- enc3 = change bpm
-- 
-- loop mode: 
-- k2 = rec loop
-- k3 = loop direction
--
-- hold key1 + tap key2
--  = tap bpm
-- ----------------------
--
-- page 2, the fun
--
-- key2 = change step 1
-- key3 = change step 2
-- 
-- enc2 = change rate 1
-- enc3 = change rate 2
--
-- ------------------------
--
-- page 3, mix
--
-- enc2 = select parameter
-- enc3 = change value
--
--------------------------------------
--
-- created by @arrdoise // 
--             @beachpomo
-- 
-- v1.0
--

local softcut = require 'softcut'

-- Bubble settings
local bubbles = {}
local bubble_spawn_rate = 0
local max_bubbles = 12
local pop_chance = 0.005
local audio_threshold = 0.0001
local max_amplitude = 0.08
local SCREEN_WIDTH = 128
local SCREEN_HEIGHT = 64

-- Metro timer IDs
local redraw_metro
local step_metro
local flash_metro
local record_fade_metro

-- Audio amplitude variables
local amp_l = 0
local amp_r = 0

-- Grid variable
local g

-- Global variables
bpm = 120
delay_level = 0.7
feedback = 0.6
rate = 1.0
delay_division = 2
selected_param = 1
step_state = 1
k1_held = false
last_tap = 0
tap_count = 0
flash_state = false
current_page = 1
mode = 1
recording = false
playing = false
reversed = false
rec_length = 0
awaiting_confirmation = false
screen_message = nil
delay_time = 0
shift_held = false
record_brightness = 4
record_fade_direction = 1
param_control_1_value = 0 -- No selection by default
param_control_2_value = 0 -- No selection by default

-- Delay divisions
delay_divisions = {
  {name = "quarter", value = 1},
  {name = "eighth", value = 0.5},
  {name = "dot.eighth", value = 0.75}
}

function init()
  -- Audio setup
  audio.comp_mix(1)
  audio.level_adc_cut(1)
  audio.level_monitor(1)
  
  -- Calculate initial delay time
  delay_time = (60 / bpm) * delay_divisions[delay_division].value
  
  -- Softcut configuration
  softcut.buffer_clear()
  
  -- Voice 1: Loop recording/playback
  softcut.enable(1, 1)
  softcut.buffer(1, 1)
  softcut.level(1, 1.0)
  softcut.pan(1, 0)
  softcut.rate(1, 1.0)
  softcut.play(1, 0)
  softcut.rec(1, 0)
  softcut.rec_level(1, 1.0)
  softcut.pre_level(1, 0.8)
  softcut.position(1, 0)
  softcut.loop(1, 1)
  softcut.loop_start(1, 0)
  softcut.loop_end(1, 60)
  softcut.fade_time(1, 0.01)
  softcut.level_input_cut(1, 1, 1.0)
  softcut.level_input_cut(2, 1, 1.0)
  
  -- Voice 2: Pitch-shifting and delay effects
  softcut.enable(2, 1)
  softcut.buffer(2, 1)
  softcut.loop(2, 1)
  softcut.loop_start(2, 0)
  softcut.loop_end(2, delay_time)
  softcut.position(2, 0)
  softcut.play(2, 1)
  softcut.rec(2, 1)
  softcut.rate(2, rate)
  softcut.rate_slew_time(2, 0.015)
  softcut.level(2, delay_level)
  softcut.rec_level(2, feedback)
  softcut.pre_level(2, feedback)
  softcut.pan(2, 0)
  softcut.post_filter_dry(2, 0.0)
  softcut.post_filter_lp(2, 1.0)
  softcut.post_filter_fc(2, 2000)
  softcut.post_filter_rq(2, 0.5)
  softcut.level_input_cut(1, 2, 1.0)
  softcut.level_cut_cut(1, 2, 0.0)
  
  -- Parameter definitions
  params:add_separator("foaaam")
  
  params:add_control("bpm", "bpm", controlspec.new(20, 240, "lin", 1, 120, "bpm"))
  params:set_action("bpm", function(x)
    bpm = math.floor(x)
    delay_time = (60 / bpm) * delay_divisions[delay_division].value
    softcut.loop_end(2, delay_time)
    update_step_metro()
    update_flash_metro()
  end)
  
  params:add_control("filter_cutoff", "filter cutoff", controlspec.new(20, 12000, "exp", 1, 2000, "Hz"))
  params:set_action("filter_cutoff", function(x) softcut.post_filter_fc(2, x) end)
  
  params:add_control("filter_rq", "filter rq", controlspec.new(0.1, 10, "lin", 0.01, 0.5))
  params:set_action("filter_rq", function(x) softcut.post_filter_rq(2, x) end)
  
  params:add_control("feedback", "feedback", controlspec.new(0, 1, "lin", 0.01, 0.6))
  params:set_action("feedback", function(x)
    feedback = x
    softcut.rec_level(2, x)
    softcut.pre_level(2, x)
  end)
  
  params:add_control("delay_level", "delay level", controlspec.new(0, 1, "lin", 0.01, 0.7))
  params:set_action("delay_level", function(x)
    delay_level = x
    softcut.level(2, x)
  end)
  
  params:add_option("delay_division", "time", {"quarter", "eighth", "dot.eighth"}, 2)
  params:set_action("delay_division", function(x)
    delay_division = x
    delay_time = (60 / bpm) * delay_divisions[delay_division].value
    softcut.loop_end(2, delay_time)
    update_step_metro()
    grid_redraw()
  end)
  
  params:add_control("pan", "pan", controlspec.new(-1, 1, "lin", 0.05, 0))
  params:set_action("pan", function(x) softcut.pan(2, x) end)
  
  params:add_control("slew_time", "glide", controlspec.new(0, 1, "lin", 0.001, 0.015, "s"))
  params:set_action("slew_time", function(x) softcut.rate_slew_time(2, x) end)
  
  params:add_option("rate", "rate 1", 
    {"-2oct", "-oct-5th", "-oct", "-5th", "-4th", "unison", "+4th", "+5th", "+oct", "+oct+5th", "+2oct"}, 6)
  params:set_action("rate", function(x)
    if step_state == 2 then
      apply_rate(x)
      softcut.rate(2, rate)
      softcut.buffer_clear_region(2, delay_time, 0.01)
    end
    grid_redraw()
  end)
  
  params:add_option("rate2", "rate 2", 
    {"-2oct", "-oct-5th", "-oct", "-5th", "-4th", "unison", "+4th", "+5th", "+oct", "+oct+5th", "+2oct"}, 6)
  params:set_action("rate2", function(x)
    if step_state == 3 then
      apply_rate(x)
      softcut.rate(2, rate)
      softcut.buffer_clear_region(2, delay_time, 0.01)
    end
    grid_redraw()
  end)
  
  params:add_option("step", "step 1", {"quarter", "eighth", "dot.eighth"}, 1)
  params:set_action("step", function(x)
    update_step_metro()
    grid_redraw()
  end)
  
  params:add_option("step2", "step 2", {"quarter", "eighth", "dot.eighth"}, 1)
  params:set_action("step2", function(x)
    update_step_metro()
    grid_redraw()
  end)
  
  params:add_option("dry_mute", "dry mute", {"off", "on"}, 2)
  params:set_action("dry_mute", function(x)
    if x == 1 then audio.level_monitor(0)
    else audio.level_monitor(1) end
  end)
  
  params:add_option("mode", "mode", {"live", "loop"}, 1)
  params:set_action("mode", function(x)
    mode = x
    if mode == 1 then
      softcut.level_input_cut(1, 2, 1.0)
      softcut.level_input_cut(2, 2, 1.0)
      softcut.level_cut_cut(1, 2, 0.0)
      softcut.play(1, 0)
      softcut.rec(1, 0)
      recording = false
      playing = false
      softcut.play(2, 1)
      softcut.rec(2, 1)
    elseif mode == 2 then
      softcut.level_input_cut(1, 2, 0.0)
      softcut.level_input_cut(2, 2, 0.0)
      softcut.level_cut_cut(1, 2, 1.0)
    end
    grid_redraw()
  end)
  
  -- Grid parameters
  params:add_separator("grid")
  
  params:add_option("param_control_1", "param control 1", {"empty", "lpf", "reso", "feedback", "level", "pan", "glide"}, 1)
  params:set_action("param_control_1", function(x)
    if x ~= 1 then -- Not "empty"
      param_control_1_value = 0 -- Reset Grid selection
    end
    grid_redraw()
  end)
  
  params:add_option("param_control_2", "param control 2", {"empty", "lpf", "reso", "feedback", "level", "pan", "glide"}, 1)
  params:set_action("param_control_2", function(x)
    if x ~= 1 then -- Not "empty"
      param_control_2_value = 0 -- Reset Grid selection
    end
    grid_redraw()
  end)
  
  -- Hide parameters from menu (excluding param_control_1 and param_control_2)
  params:hide("mode")
  params:hide("dry_mute")
  params:hide("rate")
  params:hide("rate2")
  params:hide("step")
  params:hide("step2")
  
  -- Set live mode on init
  params:set("mode", 1)
  
  -- Metro for step timing
  step_metro = metro.init()
  step_metro.event = toggle_rate
  update_step_metro()
  step_metro:start()
  toggle_rate()
  
  -- Metro for BPM flash (syncs both screen and Grid)
  flash_metro = metro.init()
  flash_metro.event = function()
    flash_state = true
    redraw()
    grid_redraw()
    clock.run(function()
      clock.sleep(0.05)
      flash_state = false
      redraw()
      grid_redraw()
    end)
  end
  update_flash_metro()
  flash_metro:start()
  
  -- Metro for record button fade
  record_fade_metro = metro.init()
  record_fade_metro.event = function()
    if recording then
      record_brightness = record_brightness + record_fade_direction * 0.5
      if record_brightness >= 15 then
        record_brightness = 15
        record_fade_direction = -1
      elseif record_brightness <= 4 then
        record_brightness = 4
        record_fade_direction = 1
      end
    else
      record_brightness = 4
    end
    grid_redraw()
  end
  record_fade_metro.time = 0.05
  record_fade_metro:start()
  
  -- Recording length tracker
  clock.run(track_recording_length)
  
  -- Start tap reset clock
  clock.run(function() while true do clock.sleep(1) reset_taps() end end)
  
  -- Ensure voice 2 effects start immediately
  clock.run(function()
    clock.sleep(0.1)
    softcut.level_input_cut(1, 2, 1.0)
    softcut.level_input_cut(2, 2, 1.0)
    softcut.level_cut_cut(1, 2, 0.0)
    softcut.play(2, 1)
    softcut.rec(2, 1)
  end)
  
  -- Bubbles setup
  local p_l = poll.set("amp_in_l")
  local p_r = poll.set("amp_in_r")
  if p_l then
    p_l.callback = function(val) amp_l = val end
    p_l.time = 0.02
    p_l:start()
  end
  if p_r then
    p_r.callback = function(val) amp_r = val end
    p_r.time = 0.02
    p_r:start()
  end

  redraw_metro = metro.init()
  redraw_metro.event = function()
    local avg_amp = (amp_l + amp_r) / 2
    bubble_spawn_rate = util.clamp(avg_amp / max_amplitude * 10, 0, 10)
    if #bubbles < max_bubbles and bubble_spawn_rate > audio_threshold then
      if math.random() < bubble_spawn_rate / 20 then
        spawn_bubble()
      end
    end
    update_bubbles()
    redraw()
  end
  redraw_metro.time = 1/30
  redraw_metro:start()
  
  -- Grid setup
  g = grid.connect()
  g.key = grid_key
  grid_redraw()
end

function update_step_metro()
  local step_values = {1, 0.5, 0.75}
  local step_time
  if step_state == 1 then
    step_time = (60 / bpm) * delay_divisions[params:get("delay_division")].value
  elseif step_state == 2 then
    step_time = (60 / bpm) * step_values[params:get("step")]
  else
    step_time = (60 / bpm) * step_values[params:get("step2")]
  end
  step_metro.time = step_time
end

function update_flash_metro()
  flash_metro.time = 60 / bpm
end

function apply_rate(index)
  if index == 1 then rate = 0.25
  elseif index == 2 then rate = 0.3333
  elseif index == 3 then rate = 0.5
  elseif index == 4 then rate = 0.6667
  elseif index == 5 then rate = 0.75
  elseif index == 6 then rate = 1.0
  elseif index == 7 then rate = 1.3333
  elseif index == 8 then rate = 1.5
  elseif index == 9 then rate = 2.0
  elseif index == 10 then rate = 3.0
  elseif index == 11 then rate = 4.0
  end
end

function toggle_rate()
  step_state = (step_state % 3) + 1
  if step_state == 1 then rate = 1.0
  elseif step_state == 2 then apply_rate(params:get("rate"))
  else apply_rate(params:get("rate2"))
  end
  softcut.rate_slew_time(2, params:get("slew_time"))
  softcut.rate(2, rate)
  softcut.buffer_clear_region(2, delay_time, 0.01)
  update_step_metro()
end

function reset_taps()
  if (k1_held or shift_held) and util.time() - last_tap > 2 then
    last_tap = 0
    tap_count = 0
  end
end

function track_recording_length()
  while true do
    if recording then
      rec_length = rec_length + 0.1
      if rec_length >= 60 then
        recording = false
        softcut.rec(1, 0)
        softcut.loop_end(1, rec_length)
        softcut.position(1, 0)
        softcut.play(1, 1)
        playing = true
      end
    end
    clock.sleep(0.1)
  end
end

function spawn_bubble()
  local style = math.random(1, 3)
  local bubble = {
    x = math.random(10, SCREEN_WIDTH - 10),
    y = SCREEN_HEIGHT,
    base_x = math.random(10, SCREEN_WIDTH - 10),
    speed = math.random(10, 23) / 10,
    size = math.random(3, 6),
    phase = math.random(0, 100) / 100,
    style = style,
    popping = false,
    pop_frame = 0
  }
  table.insert(bubbles, bubble)
end

function update_bubbles()
  for i = #bubbles, 1, -1 do
    local b = bubbles[i]
    if b.popping then
      b.pop_frame = b.pop_frame + 1
      if b.pop_frame > 2 then
        table.remove(bubbles, i)
      end
    else
      b.y = b.y - b.speed
      b.x = b.base_x + math.sin(b.y * 0.1 + b.phase) * 2.5
      if b.y < -b.size then
        table.remove(bubbles, i)
      elseif math.random() < pop_chance then
        b.popping = true
      end
    end
  end
end

function draw_bubble(b)
  if b.popping then
    screen.level(10)
    screen.pixel(b.x - 2, b.y)
    screen.pixel(b.x + 2, b.y)
    screen.pixel(b.x, b.y - 2)
    screen.pixel(b.x, b.y + 2)
    screen.fill()
  else
    screen.level(15)
    if b.style == 1 then
      screen.circle(b.x, b.y, b.size)
      screen.stroke()
      screen.level(5)
      screen.circle(b.x, b.y, b.size - 2)
      screen.fill()
      screen.level(10)
      screen.pixel(b.x - b.size + 1, b.y - b.size + 1)
      screen.fill()
    elseif b.style == 2 then
      screen.circle(b.x, b.y, b.size)
      screen.stroke()
      screen.level(10)
      screen.pixel(b.x - b.size + 1, b.y - b.size + 1)
      screen.fill()
    elseif b.style == 3 then
      screen.circle(b.x, b.y, b.size - 1)
      screen.stroke()
      screen.level(8)
      screen.circle(b.x, b.y, b.size - 2)
      screen.stroke()
    end
  end
end

function update_param_control(control, row)
  local param = (control == 1) and params:get("param_control_1") or params:get("param_control_2")
  if param == 1 then return end -- "empty", do nothing
  local percentage
  if row == 1 then percentage = 1.0
  elseif row == 2 then percentage = 0.9
  elseif row == 3 then percentage = 0.75
  elseif row == 4 then percentage = 0.5
  elseif row == 5 then percentage = 0.25
  else percentage = 0.0 end
  
  if param == 2 then -- lpf
    local min, max = 20, 12000
    params:set("filter_cutoff", min + (max - min) * percentage)
  elseif param == 3 then -- reso
    local min, max = 0.1, 10
    params:set("filter_rq", min + (max - min) * percentage)
  elseif param == 4 then -- feedback
    local min, max = 0, 1
    params:set("feedback", min + (max - min) * percentage)
  elseif param == 5 then -- level
    local min, max = 0, 1
    params:set("delay_level", min + (max - min) * percentage)
  elseif param == 6 then -- pan
    local min, max = -1, 1
    params:set("pan", min + (max - min) * percentage)
  elseif param == 7 then -- glide
    local min, max = 0, 1
    params:set("slew_time", min + (max - min) * percentage)
  end
end

function enc(n, d)
  if n == 1 then
    current_page = util.clamp(current_page + (d > 0 and 1 or -1), 1, 3)
  elseif n == 2 and current_page == 1 and k1_held then
    params:delta("mode", d)
  elseif n == 3 and current_page == 1 then
    local delta = d
    if math.abs(d) > 1 then delta = d * 5 end
    local new_bpm = util.clamp(params:get("bpm") + delta, 20, 240)
    params:set("bpm", math.floor(new_bpm))
  elseif n == 2 and current_page == 2 then
    params:delta("rate", d)
  elseif n == 3 and current_page == 2 then
    params:delta("rate2", d)
  elseif n == 2 and current_page == 3 then
    selected_param = util.clamp(selected_param + d, 1, 8)
  elseif n == 3 and current_page == 3 then
    if selected_param == 1 then params:delta("delay_level", d * 0.2)
    elseif selected_param == 2 then params:delta("feedback", d * 0.2)
    elseif selected_param == 3 then params:delta("delay_division", d)
    elseif selected_param == 4 then params:delta("filter_cutoff", d * 5)
    elseif selected_param == 5 then params:delta("dry_mute", d)
    elseif selected_param == 6 then params:delta("slew_time", d * 0.1)
    elseif selected_param == 7 then
      local delta = d * 0.1
      if math.abs(d) > 1 then delta = d * 0.5 end
      params:delta("pan", delta)
    elseif selected_param == 8 then params:delta("filter_rq", d * 0.1)
    end
  end
  redraw()
end

function key(n, z)
  if current_page == 1 then
    if n == 1 then
      k1_held = (z == 1)
      if not k1_held then last_tap = 0 tap_count = 0 end
    elseif n == 2 and z == 1 and k1_held then
      local current_time = util.time()
      if last_tap > 0 then
        local time_diff = current_time - last_tap
        local tapped_bpm = 60 / time_diff
        tapped_bpm = math.max(20, math.min(240, tapped_bpm))
        tapped_bpm = math.floor(tapped_bpm + 0.5)
        params:set("bpm", tapped_bpm)
        redraw()
      end
      last_tap = current_time
      tap_count = tap_count + 1
    elseif n == 2 and z == 1 and mode == 2 then
      if not recording and not playing and not awaiting_confirmation then
        recording = true
        rec_length = 0
        softcut.buffer_clear_channel(1)
        softcut.position(1, 0)
        softcut.loop_start(1, 0)
        softcut.loop_end(1, 60)
        softcut.rate(1, 1.0)
        softcut.rec(1, 1)
        softcut.play(1, 1)
      elseif recording then
        recording = false
        softcut.rec(1, 0)
        if rec_length and rec_length > 0 then
          clock.run(function()
            softcut.loop_end(1, rec_length)
            softcut.position(1, 0)
            clock.sleep(0.01)
            softcut.play(1, 1)
            playing = true
            redraw()
          end)
        end
      elseif playing and not awaiting_confirmation then
        awaiting_confirmation = true
        screen_message = "PRESS K2 TO START REC"
        clock.run(function()
          clock.sleep(2)
          if awaiting_confirmation then
            awaiting_confirmation = false
            screen_message = nil
          end
        end)
      elseif playing and awaiting_confirmation then
        awaiting_confirmation = false
        playing = false
        recording = true
        screen_message = nil
        softcut.play(1, 0)
        softcut.level(1, 0)
        clock.run(function()
          softcut.buffer_clear_channel(1)
          softcut.position(1, 0)
          softcut.loop_start(1, 0)
          softcut.loop_end(1, 60)
          softcut.rate(1, 1.0)
          rec_length = 0
          clock.sleep(0.01)
          softcut.level(1, 1.0)
          softcut.rec(1, 1)
          softcut.play(1, 1)
          redraw()
        end)
      end
      redraw()
    elseif n == 3 and z == 1 and mode == 2 and playing then
      reversed = not reversed
      softcut.rate(1, reversed and -1.0 or 1.0)
      redraw()
    elseif n == 3 and z == 1 then
      redraw()
    end
  elseif current_page == 2 and z == 1 then
    if n == 2 then
      local current_step = params:get("step")
      local next_step = current_step + 1
      if next_step > 3 then next_step = 1 end
      params:set("step", next_step)
    elseif n == 3 then
      local current_step2 = params:get("step2")
      local next_step2 = current_step2 + 1
      if next_step2 > 3 then next_step2 = 1 end
      params:set("step2", next_step2)
    end
    redraw()
  elseif current_page == 3 and z == 1 then
    if n == 2 then
      local current = params:get("param_control_1")
      local other = params:get("param_control_2")
      local next = current + 1
      while next <= 7 and next ~= other do
        if next > 7 then next = 1 end
        if next ~= other or next == 1 then break end
        next = next + 1
      end
      params:set("param_control_1", next > 7 and 1 or next)
    elseif n == 3 then
      local current = params:get("param_control_2")
      local other = params:get("param_control_1")
      local next = current + 1
      while next <= 7 and next ~= other do
        if next > 7 then next = 1 end
        if next ~= other or next == 1 then break end
        next = next + 1
      end
      params:set("param_control_2", next > 7 and 1 or next)
    end
    redraw()
  end
end

function redraw()
  screen.clear()
  
  screen.level(current_page == 1 and 15 or 3)
  screen.move(43, 5)
  screen.line_rel(12, 0)
  screen.stroke()
  
  screen.level(current_page == 2 and 15 or 3)
  screen.move(58, 5)
  screen.line_rel(12, 0)
  screen.stroke()
  
  screen.level(current_page == 3 and 15 or 3)
  screen.move(73, 5)
  screen.line_rel(12, 0)
  screen.stroke()
  
  if flash_state then
    screen.level(15)
    if current_page == 3 then
      screen.move(64, 13)
      screen.circle(64, 13, 2)
    else
      screen.move(64, 17)
      screen.circle(64, 17, 2)
    end
    screen.fill()
  end
  
  if current_page == 1 then
    screen.level(15)
    for _, bubble in ipairs(bubbles) do
      draw_bubble(bubble)
    end
    screen.move(5, 19)
    screen.text(params:get("mode") == 1 and "LIVE" or "LOOP")
    local bpm_text = "BPM " .. params:get("bpm")
    screen.move(128 - screen.text_extents(bpm_text), 19)
    screen.text(bpm_text)
    if mode == 2 then
      screen.move(5, 30)
      screen.level(3)
      if recording then
        screen.text("REC: " .. string.format("%.1f", rec_length) .. "s")
      elseif playing then
        screen.text("PLAY" .. (reversed and " (bwd)" or " (fwd)"))
      else
        screen.text("READY")
      end
      if screen_message then
        screen.level(15)
        screen.move(10, 55)
        screen.text(screen_message)
      end
    end
  elseif current_page == 2 then
    screen.level(15)
    screen.move(5, 19)
    screen.text("RATE 1")
    local rate1_value = ({"-2oct", "-oct-5th", "-oct", "-5th", "-4th", "unison", "+4th", "+5th", "+oct", "+oct+5th", "+2oct"})[params:get("rate")]
    screen.move(5, 29)
    screen.text(rate1_value)
    
    local rate2_text = "RATE 2"
    screen.move(128 - screen.text_extents(rate2_text), 19)
    screen.text(rate2_text)
    local rate2_value = ({"-2oct", "-oct-5th", "-oct", "-5th", "-4th", "unison", "+4th", "+5th", "+oct", "+oct+5th", "+2oct"})[params:get("rate2")]
    screen.move(128 - screen.text_extents(rate2_value), 29)
    screen.text(rate2_value)
    
    screen.move(5, 47)
    screen.text("STEP 1")
    local step1_value = ({"1/4", "1/8", "1/8d"})[params:get("step")]
    screen.move(5, 57)
    screen.text(step1_value)
    
    local step2_text = "STEP 2"
    screen.move(128 - screen.text_extents(step2_text), 47)
    screen.text(step2_text)
    local step2_value = ({"1/4", "1/8", "1/8d"})[params:get("step2")]
    screen.move(128 - screen.text_extents(step2_value), 57)
    screen.text(step2_value)
  elseif current_page == 3 then
    screen.level(selected_param == 1 and 15 or 3)
    screen.move(16 - screen.text_extents("level") / 2, 27)
    screen.text("level")
    local level_value = string.format("%.2f", params:get("delay_level"))
    screen.move(16 - screen.text_extents(level_value .. (selected_param == 1 and " <" or "")) / 2, 37)
    screen.text(level_value .. (selected_param == 1 and " <" or ""))
    
    screen.level(selected_param == 2 and 15 or 3)
    screen.move(48 - screen.text_extents("fb") / 2, 27)
    screen.text("fb")
    local fb_value = string.format("%.2f", params:get("feedback"))
    screen.move(48 - screen.text_extents(fb_value .. (selected_param == 2 and " <" or "")) / 2, 37)
    screen.text(fb_value .. (selected_param == 2 and " <" or ""))
    
    screen.level(selected_param == 3 and 15 or 3)
    screen.move(80 - screen.text_extents("time") / 2, 27)
    screen.text("time")
    local time_value = ({"1/4", "1/8", "1/8d"})[params:get("delay_division")]
    screen.move(80 - screen.text_extents(time_value .. (selected_param == 3 and " <" or "")) / 2, 37)
    screen.text(time_value .. (selected_param == 3 and " <" or ""))
    
    screen.level(selected_param == 4 and 15 or 3)
    screen.move(112 - screen.text_extents("lpf") / 2, 27)
    screen.text("lpf")
    local lpf_value = string.format("%d", params:get("filter_cutoff"))
    screen.move(112 - screen.text_extents(lpf_value .. (selected_param == 4 and " <" or "")) / 2, 37)
    screen.text(lpf_value .. (selected_param == 4 and " <" or ""))
    
    screen.level(selected_param == 5 and 15 or 3)
    screen.move(16 - screen.text_extents("dry") / 2, 50)
    screen.text("dry")
    local dry_value = ({"off", "on"})[params:get("dry_mute")]
    screen.move(16 - screen.text_extents(dry_value .. (selected_param == 5 and " <" or "")) / 2, 60)
    screen.text(dry_value .. (selected_param == 5 and " <" or ""))
    
    screen.level(selected_param == 6 and 15 or 3)
    screen.move(48 - screen.text_extents("glide") / 2, 50)
    screen.text("glide")
    local glide_value = string.format("%.3f", params:get("slew_time"))
    screen.move(48 - screen.text_extents(glide_value .. (selected_param == 6 and " <" or "")) / 2, 60)
    screen.text(glide_value .. (selected_param == 6 and " <" or ""))
    
    screen.level(selected_param == 7 and 15 or 3)
    screen.move(80 - screen.text_extents("pan") / 2, 50)
    screen.text("pan")
    local pan_value = string.format("%.2f", params:get("pan"))
    screen.move(80 - screen.text_extents(pan_value .. (selected_param == 7 and " <" or "")) / 2, 60)
    screen.text(pan_value .. (selected_param == 7 and " <" or ""))
    
    screen.level(selected_param == 8 and 15 or 3)
    screen.move(112 - screen.text_extents("reso") / 2, 50)
    screen.text("reso")
    local reso_value = string.format("%.2f", params:get("filter_rq"))
    screen.move(112 - screen.text_extents(reso_value .. (selected_param == 8 and " <" or "")) / 2, 60)
    screen.text(reso_value .. (selected_param == 8 and " <" or ""))
  end
  
  screen.update()
end

-- Grid key handler
function grid_key(x, y, z)
  if y == 8 and x == 1 then -- Shift button at [1,8]
    shift_held = (z == 1)
    if not shift_held then last_tap = 0 tap_count = 0 end
  elseif y == 8 and x == 15 and z == 1 and shift_held then -- BPM tap at [15,8] when shift held
    local current_time = util.time()
    if last_tap > 0 then
      local time_diff = current_time - last_tap
      local tapped_bpm = 60 / time_diff
      tapped_bpm = math.max(20, math.min(240, tapped_bpm))
      tapped_bpm = math.floor(tapped_bpm + 0.5)
      params:set("bpm", tapped_bpm)
      redraw()
      grid_redraw()
    end
    last_tap = current_time
    tap_count = tap_count + 1
  elseif z == 1 then -- Other controls only on press
    if x == 1 and y >= 1 and y <= 6 and params:get("param_control_1") ~= 1 then -- Column 1: Param Control 1
      param_control_1_value = y
      update_param_control(1, y)
    elseif x == 2 and y >= 1 and y <= 6 and params:get("param_control_2") ~= 1 then -- Column 2: Param Control 2
      param_control_2_value = y
      update_param_control(2, y)
    elseif y == 2 then -- Row 2: STEP 1 [4,2] to [6,2]
      if x == 4 then params:set("step", 1)
      elseif x == 5 then params:set("step", 2)
      elseif x == 6 then params:set("step", 3)
      end
    elseif y == 5 then -- Row 5: STEP 2 [4,5] to [6,5]
      if x == 4 then params:set("step2", 1)
      elseif x == 5 then params:set("step2", 2)
      elseif x == 6 then params:set("step2", 3)
      end
    elseif y == 1 then -- Row 1: RATE 1 [5,1] to [15,1]
      if x >= 5 and x <= 15 then params:set("rate", x - 4) end
    elseif y == 4 then -- Row 4: RATE 2 [5,4] to [15,4]
      if x >= 5 and x <= 15 then params:set("rate2", x - 4) end
    elseif y == 8 then -- Row 8: TIME [10,8] to [12,8], MODE [3,8] to [4,8], LOOP CONTROLS [6,8] to [8,8]
      if x == 10 then params:set("delay_division", 1)
      elseif x == 11 then params:set("delay_division", 2)
      elseif x == 12 then params:set("delay_division", 3)
      elseif x == 3 and shift_held then params:set("mode", 1)
      elseif x == 4 and shift_held then params:set("mode", 2)
      elseif mode == 2 then
        if x == 6 and not recording and not playing and rec_length > 0 then -- Play
          softcut.position(1, 0)
          softcut.play(1, 1)
          playing = true
        elseif x == 7 and playing then -- Stop
          softcut.play(1, 0)
          playing = false
        elseif x == 8 then
          if shift_held and not recording and not playing then -- Start recording
            recording = true
            rec_length = 0
            softcut.buffer_clear_channel(1)
            softcut.position(1, 0)
            softcut.loop_start(1, 0)
            softcut.loop_end(1, 60)
            softcut.rate(1, 1.0)
            softcut.rec(1, 1)
            softcut.play(1, 1)
          elseif recording then -- Stop recording
            recording = false
            softcut.rec(1, 0)
            softcut.loop_end(1, rec_length)
            softcut.position(1, 0)
            softcut.play(1, 1)
            playing = true
          end
        end
      end
    elseif y == 7 and mode == 2 then -- Row 7: LOOP DIRECTION [6,7] to [7,7]
      if x == 6 then
        reversed = false
        softcut.rate(1, 1.0)
      elseif x == 7 then
        reversed = true
        softcut.rate(1, -1.0)
      end
    elseif y == 6 then -- Row 6: PAGE [14,6] to [16,6], DRY [10,6] to [11,6]
      if x == 14 then current_page = 1
      elseif x == 15 then current_page = 2
      elseif x == 16 then current_page = 3
      elseif x == 10 then params:set("dry_mute", 1) -- Dry Off
      elseif x == 11 then params:set("dry_mute", 2) -- Dry On
      end
    end
    redraw()
    grid_redraw()
  end
end

-- Grid redraw function
function grid_redraw()
  if g then
    g:all(0) -- Clear Grid
    
    -- Column 1: Param Control 1 [1,1] to [1,6]
    if params:get("param_control_1") ~= 1 and param_control_1_value >= 1 and param_control_1_value <= 6 then
      for y = 1, 6 do
        g:led(1, y, (y == param_control_1_value) and 15 or 4)
      end
    else
      for y = 1, 6 do g:led(1, y, 4) end
    end
    
    -- Column 2: Param Control 2 [2,1] to [2,6]
    if params:get("param_control_2") ~= 1 and param_control_2_value >= 1 and param_control_2_value <= 6 then
      for y = 1, 6 do
        g:led(2, y, (y == param_control_2_value) and 15 or 4)
      end
    else
      for y = 1, 6 do g:led(2, y, 4) end
    end
    
    -- Row 2: STEP 1 [4,2] to [6,2]
    local step_value = params:get("step")
    if step_value == 1 then g:led(4, 2, 15)
    elseif step_value == 2 then g:led(5, 2, 15)
    elseif step_value == 3 then g:led(6, 2, 15)
    end
    for i = 4, 6 do if i - 3 ~= step_value then g:led(i, 2, 4) end end
    
    -- Row 5: STEP 2 [4,5] to [6,5]
    local step2_value = params:get("step2")
    if step2_value == 1 then g:led(4, 5, 15)
    elseif step2_value == 2 then g:led(5, 5, 15)
    elseif step2_value == 3 then g:led(6, 5, 15)
    end
    for i = 4, 6 do if i - 3 ~= step2_value then g:led(i, 5, 4) end end
    
    -- Row 1: RATE 1 [5,1] to [15,1]
    local rate_value = params:get("rate")
    for i = 5, 15 do g:led(i, 1, (i - 4) == rate_value and 15 or 4) end
    
    -- Row 4: RATE 2 [5,4] to [15,4]
    local rate2_value = params:get("rate2")
    for i = 5, 15 do g:led(i, 4, (i - 4) == rate2_value and 15 or 4) end
    
    -- Row 8: TIME [10,8] to [12,8]
    local time_value = params:get("delay_division")
    if time_value == 1 then g:led(10, 8, 15)
    elseif time_value == 2 then g:led(11, 8, 15)
    elseif time_value == 3 then g:led(12, 8, 15)
    end
    for i = 10, 12 do if i - 9 ~= time_value then g:led(i, 8, 4) end end
    
    -- Row 8: MODE [3,8] to [4,8]
    local mode_value = params:get("mode")
    if mode_value == 1 then g:led(3, 8, 15)
    elseif mode_value == 2 then g:led(4, 8, 15)
    end
    for i = 3, 4 do if i - 2 ~= mode_value then g:led(i, 8, 4) end end
    
    -- Row 6: PAGE [14,6] to [16,6]
    if current_page == 1 then g:led(14, 6, 15)
    elseif current_page == 2 then g:led(15, 6, 15)
    elseif current_page == 3 then g:led(16, 6, 15)
    end
    for i = 14, 16 do if i - 13 ~= current_page then g:led(i, 6, 4) end end
    
    -- Row 6: PAGE [14,6] to [16,6], DRY [10,6] to [11,6]
    if current_page == 1 then g:led(14, 6, 15)
    elseif current_page == 2 then g:led(15, 6, 15)
    elseif current_page == 3 then g:led(16, 6, 15)
    end
    for i = 14, 16 do if i - 13 ~= current_page then g:led(i, 6, 4) end end
    local dry_value = params:get("dry_mute")
    g:led(10, 6, dry_value == 1 and 15 or 4) -- Dry Off
    g:led(11, 6, dry_value == 2 and 15 or 4) -- Dry On
    
    -- Row 8: Shift and BPM controls
    g:led(1, 8, shift_held and 15 or 4) -- Shift button
    g:led(15, 8, 7) -- BPM tap button
    g:led(16, 8, flash_state and 7 or 0) -- BPM flash
    
    -- Row 8: LOOP CONTROLS [6,8] to [8,8] (only in loop mode)
    if mode == 2 then
      g:led(6, 8, playing and 15 or 4) -- Play
      g:led(7, 8, (not playing or rec_length == 0) and 15 or 4) -- Stop
      g:led(8, 8, math.floor(record_brightness)) -- Record (fading)
    end
    
    -- Row 7: LOOP DIRECTION [6,7] to [7,7] (only in loop mode)
    if mode == 2 then
      g:led(6, 7, not reversed and 15 or 4) -- Forward
      g:led(7, 7, reversed and 15 or 4) -- Reverse
    end
    
    -- Static bright LEDs
    g:led(4, 1, 15)  -- Row 1, column 4
    g:led(4, 4, 15)  -- Row 4, column 4
    g:led(16, 1, 15) -- Row 1, column 16
    g:led(16, 4, 15) -- Row 4, column 16
    
    g:refresh()
  end
end

function cleanup()
  if redraw_metro then redraw_metro:stop() end
  if step_metro then step_metro:stop() end
  if flash_metro then flash_metro:stop() end
  if record_fade_metro then record_fade_metro:stop() end
  poll.set("amp_in_l"):stop()
  poll.set("amp_in_r"):stop()
  softcut.buffer_clear()
  softcut.play(1, 0)
  softcut.rec(1, 0)
  softcut.level(1, 0)
  softcut.play(2, 0)
  softcut.rec(2, 0)
  softcut.level(2, 0)
  if g then g:all(0) g:refresh() end
end

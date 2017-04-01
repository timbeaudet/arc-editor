local lume = require "lume"

local arc = nil

local arcs = {}

local lastMouse = {0, -16}

local track_radius = 10

local function tangent_to_basis (tangent)
	return {
		x = tangent,
		y = {-tangent [2], tangent [1]},
	}
end

local function into_basis (v, basis)
	return {
		v [1] * basis.x [1] + v [2] * basis.x [2],
		v [1] * basis.y [1] + v [2] * basis.y [2],
	}
end

local function from_basis (v, basis)
	return {
		v [1] * basis.x [1] + v [2] * basis.y [1],
		v [1] * basis.x [2] + v [2] * basis.y [2],
	}
end

local function draw_arc (g, arc, color)
	if not arc then
		return
	end
	
	local color = color or {255, 255, 255}
	
	g.setColor (color)
	
	if arc.params and arc.stop.tangent then
		local basis = tangent_to_basis (arc.start.tangent)
		local points = tesselate_arc_basis (arc.start.pos, arc.params, basis)
		
		local function draw_polyline (ls)
			for i = 1, #ls - 1 do
				local j = i + 1
				
				local a = ls [i]
				local b = ls [j]
				
				g.line (a [1], a [2], b [1], b [2])
			end
		end
		
		draw_polyline (tesselate_arc_basis (arc.start.pos, arc.params, basis, -track_radius))
		draw_polyline (tesselate_arc_basis (arc.start.pos, arc.params, basis, track_radius))
		
		local pos = points [#points]
		local basis = tangent_to_basis (arc.stop.tangent)
		
		g.setColor (255, 64, 64)
		g.line (pos [1], pos [2], pos [1] + 16 * arc.stop.tangent [1], pos [2] + 16 * arc.stop.tangent [2])
		
		local avg_curvature = arc.params.total_theta / arc.params.length
		local stop_curvature = avg_curvature + (avg_curvature - arc.start.curvature)
		
		local length = 64.0
		--[[
		draw_polyline (tesselate_arc_basis (pos, {
			start_curvature = stop_curvature,
			total_theta = length * stop_curvature,
			length = length,
			num_segments = 16,
		}, basis, 0.0))
		--]]
		local normal = from_basis ({0.0, 16.0}, basis)
		
		g.line (pos [1], pos [2], pos [1] + normal [1], pos [2] + normal [2])
	end
	
	--g.setColor (64, 64, 64)
	--g.line (arc.start.pos [1], 0, arc.start.pos [1], 600)
end

function bend_arc_basis (start, mouse, basis, start_curvature)
	local local_mouse = into_basis ({mouse [1] - start [1], mouse [2] - start [2]}, basis)
	
	local a, arc_params = bend_arc (local_mouse, start_curvature)
	
	local tangent = from_basis (a, basis)
	
	return tangent, arc_params
end

function bend_arc (mouse, start_curvature)
	local theta = math.atan2 (mouse [2], mouse [1])
	local theta_gran = 7.5
	local snapped_theta = (math.floor (((theta * 180.0 / math.pi) + theta_gran * 0.5) / theta_gran) * theta_gran) * math.pi / 180.0
	
	local radius = math.sqrt (math.pow (mouse [1], 2.0) + math.pow (mouse [2], 2.0))
	
	--[[
	local snapped_mouse = {
		radius * math.cos (snapped_theta) + start [1],
		radius * math.sin (snapped_theta) + start [2],
	}
	--]]
	
	local total_arc_theta = 2 * snapped_theta
	
	local num_segments = 8
	local gran = num_segments * 3
	
	local arc_length = math.floor (radius / gran) * gran
	
	local arc_params = {
		total_theta = total_arc_theta,
		length = arc_length,
		num_segments = num_segments,
		start_curvature = start_curvature or 0.0,
	}
	local lines = tesselate_arc (arc_params)
	local tangent = {math.cos (total_arc_theta), math.sin (total_arc_theta)}
	
	return tangent, arc_params
end

function tesselate_arc_basis (start, p, basis, offset)
	return lume.map (tesselate_arc (p, offset), function (p)
		local p2 = from_basis (p, basis)
		return {p2 [1] + start [1], p2 [2] + start [2]}
	end)
end

function tesselate_arc (p, offset)
	local offset = offset or 0.0
	local lines = {
		{0.0, offset},
	}
	
	local curvature = p.total_theta / p.length
	local end_curvature = curvature + (curvature - p.start_curvature)
	local theta = 0.0
	local last_point = {0.0, 0.0}
	local segment_length = p.length / p.num_segments
	for i = 1, p.num_segments do
		local t = i / p.num_segments
		--local local_curvature = p.start_curvature * (1.0 - t) + end_curvature * t
		local local_curvature = curvature
		theta = theta + 0.5 * local_curvature * segment_length
		local point = {
			last_point [1] + segment_length * math.cos (theta),
			last_point [2] + segment_length * math.sin (theta),
		}
		theta = theta + 0.5 * local_curvature * segment_length
		if offset == 0.0 then
			table.insert (lines, point)
		else
			local normal_theta = theta + 0.5 * math.pi
			local normal = {
				offset * math.cos (normal_theta),
				offset * math.sin (normal_theta),
			}
			
			table.insert (lines, {
				point [1] + normal [1],
				point [2] + normal [2],
			})
		end
		last_point = point
	end
	
	return lines
end

function love.draw ()
	for _, arc in ipairs (arcs) do
		draw_arc (love.graphics, arc)
	end
	draw_arc (love.graphics, arc, {120, 120, 120})
	
	if not arc and #arcs == 0 then
		love.graphics.setColor (120, 120, 120)
		love.graphics.printf ("Click to start", 0, 300, 800, "center")
		
		love.graphics.setColor (255, 64, 64)
		love.graphics.line (lastMouse [1], lastMouse [2], lastMouse [1], lastMouse [2])
	end
end

function love.mousemoved (x, y)
	if arc then
		local gran = 5.0 / 16.0
		local rounded_curvature = math.floor ((arc.start.curvature - 0.5 * gran) / gran) * gran + 0.5 * gran
		arc.stop.tangent, arc.params = bend_arc_basis (arc.start.pos, {x, y}, tangent_to_basis (arc.start.tangent), arc.start.curvature)
	end
	
	lastMouse = {x, y}
end

function love.mousepressed (x, y)
	local old_arc = arc
	table.insert (arcs, arc)
	
	if old_arc then
		local old_p = old_arc.params
		local old_points = tesselate_arc_basis (old_arc.start.pos, old_p, tangent_to_basis (old_arc.start.tangent))
		local old_stop = old_points [#old_points]
		local old_avg_curvature = old_p.total_theta / old_p.length
		local old_stop_curvature = old_avg_curvature + (old_avg_curvature - old_p.start_curvature)
		
		arc = {
			start = {
				pos = old_stop,
				tangent = old_arc.stop.tangent,
				curvature = old_stop_curvature,
			},
			stop = {
				pos = old_stop,
				tangent = old_arc.stop.tangent,
			},
			params = nil,
		}
	else
		arc = {
			start = {
				pos = {x, y},
				tangent = {1, 0},
				curvature = 0.0,
			},
			stop = {
				pos = {x, y},
				tangent = {1, 0},
			},
			params = nil,
		}
	end
end

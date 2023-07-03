#!/usr/bin/env luajit
local ffi = require 'ffi'
local sdl = require 'ffi.sdl'
local ig = require 'imgui'
local gl = require 'gl'
local ImGuiApp = require 'imguiapp'	-- on windows, imguiapp needs to be before ig...
local vec3ub = require 'vec-ffi.vec3ub'
local class = require 'ext.class'
local table = require 'ext.table'
local vec2 = require 'vec.vec2'
local GLProgram = require 'gl.program'
local HSVTex = require 'gl.hsvtex'
local PingPong = require 'gl.pingpong'
local glreport = require 'gl.report'
local GLTex2D = require 'gl.tex2d'
local template = require 'template'
local Image = require 'image'
-- isle of misfits:
local clnumber = require 'cl.obj.number'
local Mouse = require 'glapp.mouse'

local gridsize = assert(tonumber(arg[2] or 1024))

local App = class(ImGuiApp)

App.title = 'Rule 110'

local pingpong
local updateShader
local displayShader
local mouse = Mouse()
	
local bufferCPU = ffi.new('int[?]', gridsize * gridsize)

local colors = {
	vec3ub(0,0,0),
	vec3ub(0,255,255),
	vec3ub(255,255,0),
	vec3ub(255,0,0),
}

local function reset()
	ffi.fill(bufferCPU, ffi.sizeof'int' * gridsize * gridsize)
	for i=0,gridsize*gridsize-1 do
		--bufferCPU[i] = math.random(0,1) * -1
		--bufferCPU[i] = math.random(0xffffffff)
	end
	bufferCPU[bit.rshift(gridsize,1) + gridsize * (gridsize-1)] = -1
	pingpong:prev():bind(0)
	gl.glTexSubImage2D(gl.GL_TEXTURE_2D, 0, 0, 0, gridsize, gridsize, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, bufferCPU)
	pingpong:prev():unbind(0)
end

function App:initGL()
	App.super.initGL(self)

	gl.glClearColor(.2, .2, .2, 0)

	pingpong = PingPong{
		width = gridsize,
		height = gridsize,
		internalFormat = gl.GL_RGBA8,
		format = gl.GL_RGBA,
		type = gl.GL_UNSIGNED_BYTE,
		magFilter = gl.GL_LINEAR,
		minFilter = gl.GL_LINEAR,
		--minFilter = gl.GL_LINEAR_MIPMAP_LINEAR,
		--generateMipmap = true,
		wrap = {
			s = gl.GL_REPEAT,
			t = gl.GL_REPEAT,
		}
	}
	reset()

	updateShader = GLProgram{
		vertexCode = [[
varying vec2 tc;
void main() {
	tc = gl_MultiTexCoord0.st;
	gl_Position = ftransform();
}
]],
		fragmentCode = template([[
varying vec2 tc;
uniform sampler2D tex;

const float gridsize = <?=clnumber(gridsize)?>;
const float du = <?=clnumber(du)?>;

void main() {
	if (floor(tc.y * gridsize) < gridsize - 1.) 
	{
		gl_FragColor = texture2D(tex, tc + vec2(0, du));
	} 
	else 
	{
		//sum neighbors
		float v = floor(.5 + texture2D(tex, tc + vec2(du, 0)).r)
			+ 2. * floor(.5 + texture2D(tex, tc + vec2(0, 0)).r)
			+ 4. * floor(.5 +  texture2D(tex, tc + vec2(-du, 0)).r);

		if (v == 1. || v == 2. || v == 3. || v == 5. || v == 6.) {
			gl_FragColor = vec4(1.);
		} else {
			gl_FragColor = vec4(0.);
		}
	}
}
]],			{
				clnumber = clnumber,
				gridsize = gridsize,
				du = 1 / gridsize,
			}
		),
		uniforms = {
			tex = 0,
		},
	}

	displayShader = GLProgram{
		vertexCode = [[
varying vec2 tc;
void main() {
	gl_Position = ftransform();
	tc = gl_MultiTexCoord0.st;
}
]],
		fragmentCode = template([[
varying vec2 tc;
uniform sampler2D tex;
void main() {
	gl_FragColor = texture2D(tex, tc);
}
]],			{
				clnumber = clnumber,
			}
		),
		uniforms = {
			tex = 0,
		},
	}

	glreport 'here'
end

local leftShiftDown
local rightShiftDown 
local zoomFactor = .9
local zoom = 1
local viewPos = vec2(0,0)

local value = ffi.new('int[1]', 0)
function App:update()
	local ar = self.width / self.height
	
	local canHandleMouse = not ig.igGetIO()[0].WantCaptureMouse
	if canHandleMouse then 
		mouse:update()
		if mouse.leftDown then
			local pos = (vec2(mouse.pos:unpack()) - vec2(.5, .5)) * (2 / zoom)
			pos[1] = pos[1] * ar
			pos = ((pos + viewPos) * .5 + vec2(.5, .5)) * gridsize
			local x = math.floor(pos[1] + .5)
			local y = math.floor(pos[2] + .5)
			if x >= 0 and x < gridsize and y >= 0 and y < gridsize then
				pingpong:draw{
					callback = function()
						gl.glReadPixels(x, gridsize-1, 1, 1, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, value)
						if value[0] == 0 then
							value[0] = -1
						else
							value[0] = 0
						end
					end,
				}
				pingpong:prev():bind(0)
				gl.glTexSubImage2D(gl.GL_TEXTURE_2D, 0, x, gridsize-1, 1, 1, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, value)
				pingpong:prev():unbind(0)
			end
		end
		if mouse.rightDragging then
			if leftShiftDown or rightShiftDown then
				zoom = zoom * math.exp(10 * mouse.deltaPos.y)
			else
				viewPos = viewPos - vec2(mouse.deltaPos.x * ar, mouse.deltaPos.y) * (2 / zoom)
			end
		end
	end

	-- update
	pingpong:draw{
		viewport = {0, 0, gridsize, gridsize},
		resetProjection = true,
		shader = updateShader,
		texs = {pingpong:prev()},
		callback = function()
			gl.glBegin(gl.GL_TRIANGLE_STRIP)
			for _,v in ipairs{{0,0},{1,0},{0,1},{1,1}} do
				gl.glTexCoord2d(v[1], v[2])
				gl.glVertex2d(v[1], v[2])
			end
			gl.glEnd()
		end,
	}
	pingpong:swap()

	gl.glMatrixMode(gl.GL_PROJECTION)
	gl.glLoadIdentity()
	gl.glOrtho(-ar, ar, -1, 1, -1, 1)

	gl.glMatrixMode(gl.GL_MODELVIEW)
	gl.glLoadIdentity()
	gl.glScaled(zoom, zoom, 1)
	gl.glTranslated(-viewPos[1], -viewPos[2], 0)

	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))
	displayShader:use()
	pingpong:cur():bind(0)
	gl.glBegin(gl.GL_TRIANGLE_STRIP)
	for _,v in ipairs{{0,0},{1,0},{0,1},{1,1}} do
		gl.glTexCoord2d(v[1], v[2])
		gl.glVertex2d(v[1]*2-1, 1-v[2]*2)	-- flipped from typical display. TODO instead write to the first col instead of the last, and scroll in the opposite dir, and flip this back to normal
	end
	gl.glEnd()
	pingpong:cur():unbind(0)
	
	GLProgram:useNone()
	App.super.update(self)
end

function App:event(event, eventPtr)
	App.super.event(self, event, eventPtr)
	local canHandleMouse = not ig.igGetIO()[0].WantCaptureMouse
	local canHandleKeyboard = not ig.igGetIO()[0].WantCaptureKeyboard

	if event.type == sdl.SDL_MOUSEBUTTONDOWN then
		if event.button.button == sdl.SDL_BUTTON_WHEELUP then
			zoom = zoom * zoomFactor
		elseif event.button.button == sdl.SDL_BUTTON_WHEELDOWN then
			zoom = zoom / zoomFactor
		end
	elseif event.type == sdl.SDL_KEYDOWN or event.type == sdl.SDL_KEYUP then
		if event.key.keysym.sym == sdl.SDLK_LSHIFT then
			leftShiftDown = event.type == sdl.SDL_KEYDOWN
		elseif event.key.keysym.sym == sdl.SDLK_RSHIFT then
			rightShiftDown = event.type == sdl.SDL_KEYDOWN
		end
	end
end

function App:updateGUI()
	if ig.igButton'Save' then
		pingpong:prev():bind(0)	-- prev? shouldn't this be cur?
		gl.glGetTexImage(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, bufferCPU)
		pingpong:prev():unbind(0)
		Image(gridsize, gridsize, 3, 'unsigned char', function(x,y)
			local value = bufferCPU[x + gridsize * y]
			value = value % modulo
			return colors[value+1]:unpack()
		end):save'output.glsl.png'
	end

	ig.igSameLine()

	if ig.igButton'Load' then
		local image = Image'output.glsl.png'
		assert(image.width == gridsize)
		assert(image.height == gridsize)
		assert(image.channels == 3)
		for y=0,image.height-1 do
			for x=0,image.width-1 do
				local rgb = image.buffer + 4 * (x + image.width * y)
				for i,color in ipairs(colors) do
					if rgb[0] == color.x
					and rgb[1] == color.y
					and rgb[2] == color.z
					then
						bufferCPU[x + gridsize * y] = i-1
						break
					end
					if i == #colors then
						error("unknown color")
					end
				end
			end
		end
		pingpong:prev():bind(0)
		gl.glTexSubImage2D(gl.GL_TEXTURE_2D, 0, 0, 0, gridsize, gridsize, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, bufferCPU)
		pingpong:prev():unbind(0)
	end

	ig.igSameLine()
	
	if ig.igButton'Reset' then
		reset()
	end
end

return App():run()

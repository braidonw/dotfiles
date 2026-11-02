local terminal = "com.superlogical.terminal"

local function focused_cwd(ctx)
  local r = rex.block.call(terminal, "pwd", { block_id = ctx.block_id })
  if r == nil or r.pwd == nil then return nil end
  local path = r.pwd:gsub("^file://[^/]*", "")
  return (path:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

local function float_command(name, title, command)
  rex.action{
    name  = name,
    title = title,
    run   = function(ctx, args)
      local _, err = rex.session.new_layer{
        bounds = { 0.05, 0.05, 0.9, 0.9 },
        focus  = true,
        layout = rex.layout.block{
          flavor  = terminal .. ".shell",
          options = { command = command, cwd = focused_cwd(ctx) },
        },
      }
      if err ~= nil then error(err, 0) end
    end,
  }
end

float_command("float_lazygit", "Floating Lazygit", { "lazygit" })
float_command("float_tuicr", "Floating tuicr", { "tuicr" })

rex.bind("cmd+shift+g", "float_lazygit")
rex.bind("cmd+shift+r", "float_tuicr")

-- Read defaults and supported overrides without loading compositor side effects.
local home = os.getenv("HOME")
package.path = home .. "/.config/hypr/?.lua;" .. home .. "/.config/caelestia/?.lua;" .. package.path
local vars = require("variables")
for k, v in pairs(require("hypr-vars")) do vars[k] = v end
io.write(require("utils.json").encode(vars))

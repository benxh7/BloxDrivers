--[[

> TopbarPlus was developed by ForeverHD and is actively maintained
thanks to HD Admin.

> You can get in touch with me on Discord via the social link here:
https://create.roblox.com/store/asset/92368439343389/TopbarPlus

> READ_ME is Script with RunContext set to 'Client' meaning you can
store it in ReplicatedStorage and Workspace and it will still run 
like a normal LocalScript. DO NOT PLACE place in StarterPlayerScripts
(because this is a Script with RunContext). You need to create a separate
LocalScript for anything under StarterPlayerScripts. 

> You're welcome to move `Icon` and require it yourself. You can
then delete this folder and READ_ME.

> Icon is a Package for when Roblox (hopefully soon) release
public packages. This for example will enable you to receive
automatic updates, and to compare code easily between changes

> Have feedback? Post it to devforum.roblox.com/t/topbarplus/1017485
which I actively monitor. Enjoy! ~ForeverHD June 2025



local container  = script.Parent
local Icon = require(container.Icon)

Icon.new()
	:setName("Example")
	:setLabel("Example")
	:setImage(16086868244, "Deselected")
	:setImage(16086868447, "Selected")--]]
-- Default username palette from Roblox's classic chat.
-- https://github.com/Roblox/Core-Scripts/blob/master/CoreScriptsRoot/Modules/Server/ServerChat/DefaultChatModules/ExtraDataInitializer.lua
local ChatNameColor={}
local colors={
 Color3.fromRGB(253,41,67),
 Color3.fromRGB(1,162,255),
 Color3.fromRGB(2,184,87),
 BrickColor.new("Bright violet").Color,
 BrickColor.new("Bright orange").Color,
 BrickColor.new("Bright yellow").Color,
 BrickColor.new("Light reddish violet").Color,
 BrickColor.new("Brick yellow").Color,
}
function ChatNameColor.FromUsername(username: string): Color3
 local total=0
 local length=#username
 for i=1,length do
  local reverse=length-i+1
  if length%2==1 then reverse-=1 end
  local value=string.byte(username,i)
  total+=if reverse%4>=2 then -value else value
 end
 return colors[total%#colors+1]
end
return ChatNameColor

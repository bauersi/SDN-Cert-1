--[[
  Feature test for matching of IPv4 src and dst field
]]

require "feature_config"

local Feature = FeatureConfig.new()

Feature.require = "OpenFlow12"
Feature.state   = "required"
  
Feature.loadGen = "moongen"
Feature.files   = "feature_test.lua"
Feature.lgArgs  = "$file=1 $name $link=1 $link=2"
Feature.ofArgs  = "$link=2"
    
Feature.pkt = Feature.getDefaultPkt()

Feature.settings = {
    txIterations = 2,
    new_DST_IP4 = "10.0.2.2"
}
local conf = Feature.settings

Feature.flowEntries = function(openflowVersion, flowData, outPort)
    table.insert(flowData.flows, string.format("table=0, ip, nw_dst=%s, actions=DROP", Feature.pkt.DST_IP4))
    table.insert(flowData.flows, string.format("table=0, ip, nw_dst=%s, actions=output:%s", conf.new_DST_IP4, outPort))
end
  
Feature.modifyPkt = function(pkt, iteration)
    pkt.DST_IP4 = conf.new_DST_IP4
end
  
return Feature

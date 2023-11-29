local addonName = ... ---@type string

---@class BetterBags: AceAddon
local addon = LibStub('AceAddon-3.0'):GetAddon(addonName)

---@class Constants: AceModule
local const = addon:GetModule('Constants')

---@class Database: AceModule
local database = addon:GetModule('Database')

---@class ItemRowFrame: AceModule
local itemRowFrame = addon:GetModule('ItemRowFrame')

---@class Views: AceModule
local views = addon:GetModule('Views')

---@param bag Bag
---@param dirtyItems table<number, table<number, ItemMixin>>
function views:ListView(bag, dirtyItems)
  local sizeInfo = database:GetBagSizeInfo(bag.kind)
  bag:WipeFreeSlots()
  local freeSlotsData = {count = 0, bagid = 0, slotid = 0}
  local freeReagentSlotsData = {count = 0, bagid = 0, slotid = 0}
  bag.content.compactStyle = database:GetBagCompaction(bag.kind)
  for bid, bagData in pairs(dirtyItems) do
    bag.itemsByBagAndSlot[bid] = bag.itemsByBagAndSlot[bid] or {}
    for sid, itemData in pairs(bagData) do
      local bagid, slotid = itemData:GetItemLocation():GetBagAndSlot()

      -- Capture information about free slots.
      if itemData:IsItemEmpty() then
        if bagid == Enum.BagIndex.ReagentBag then
          freeReagentSlotsData.count = freeReagentSlotsData.count + 1
          freeReagentSlotsData.bagid = bagid
          freeReagentSlotsData.slotid = slotid
        else
          freeSlotsData.count = freeSlotsData.count + 1
          freeSlotsData.bagid = bagid
          freeSlotsData.slotid = slotid
        end
      end

      local oldFrame = bag.itemsByBagAndSlot[bagid][slotid] --[[@as ItemRow]]
      -- The old frame does not exist, so we need to create a new one.
      if oldFrame == nil and not itemData:IsItemEmpty() then
        local newFrame = itemRowFrame:Create()
        newFrame:SetItem(itemData)
        local category = newFrame:GetCategory()
        local section ---@type Section|nil
        if newFrame:IsNewItem() then
          section = bag.recentItems
        else
          section = bag:GetOrCreateSection(category)
        end

        section:AddCell(itemData:GetItemGUID(), newFrame)
        newFrame:AddToMasqueGroup(bag.kind)
        bag.itemsByBagAndSlot[bagid][slotid] = newFrame
      elseif oldFrame ~= nil and not itemData:IsItemEmpty() and oldFrame:GetMixin():GetItemGUID() ~= itemData:GetItemGUID() then
        -- This case handles the situation where the item in this slot no longer matches the item displayed.
        -- The old frame exists, so we need to update it.
        local oldCategory = oldFrame:GetCategory()
        local oldSection = bag.sections[oldCategory]
        if bag.recentItems:HasItem(oldFrame.button) then
          oldSection = bag.recentItems
          oldCategory = bag.recentItems.title:GetText()
        end
        local oldGuid = oldFrame:GetGUID()
        oldFrame:SetItem(itemData)
        local newCategory = oldFrame:GetCategory()
        local newSection = bag:GetOrCreateSection(newCategory)

        if oldCategory ~= newCategory then
          oldSection:RemoveCell(oldGuid, oldFrame)
          newSection:AddCell(oldFrame:GetGUID(), oldFrame)
        end
        if oldSection == bag.recentItems then
        elseif oldSection:GetCellCount() == 0 then
          bag.sections[oldCategory] = nil
          bag.content:RemoveCell(oldCategory, oldSection)
          oldSection:Release()
        end
      elseif oldFrame ~= nil and not itemData:IsItemEmpty() and oldFrame:GetGUID() == itemData:GetItemGUID() then
        -- This case handles when the item in this slot is the same as the item displayed.
        oldFrame:SetItem(itemData)

        -- The item in this same slot may no longer be a new item, i.e. it was moused over. If so, we
        -- need to resection it.
        if not oldFrame:IsNewItem() and bag.recentItems:HasItem(oldFrame.button) then
          bag.recentItems:RemoveCell(oldFrame:GetGUID(), oldFrame)
          local category = oldFrame:GetCategory()
          local section = bag:GetOrCreateSection(category)
          section:AddCell(oldFrame:GetGUID(), oldFrame)
        end
      elseif itemData:IsItemEmpty() and oldFrame ~= nil then
        -- The old frame exists, but the item is empty, so we need to delete it.
        bag.itemsByBagAndSlot[bagid][slotid] = nil
        -- Special handling for the recent items section.
        if bag.recentItems:HasItem(oldFrame.button) then
          bag.recentItems:RemoveCell(oldFrame:GetGUID(), oldFrame)
        else
          local section = bag.sections[oldFrame:GetCategory()]
          section:RemoveCell(oldFrame:GetGUID(), oldFrame)
          -- Delete the section if it's empty as well.
          if section:GetCellCount() == 0 then
            bag.sections[oldFrame:GetCategory()] = nil
            bag.content:RemoveCell(oldFrame:GetCategory(), section)
            section:Release()
          end
        end
        oldFrame:Release()
      end
    end
  end

  bag.freeSlots:AddCell("freeBagSlots", bag.freeBagSlotsButton)
  bag.freeSlots:AddCell("freeReagentBagSlots", bag.freeReagentBagSlotsButton)

  bag.freeBagSlotsButton:SetFreeSlots(freeSlotsData.bagid, freeSlotsData.slotid, freeSlotsData.count, false)
  bag.freeReagentBagSlotsButton:SetFreeSlots(freeReagentSlotsData.bagid, freeReagentSlotsData.slotid, freeReagentSlotsData.count, true)

  bag.recentItems:SetMaxCellWidth(sizeInfo.itemsPerRow)
  -- Loop through each section and draw it's size.
  local recentW, recentH = bag.recentItems:Draw()
  for _, section in pairs(bag.sections) do
    section:SetMaxCellWidth(1)
    section:Draw()
  end
  bag.freeSlots:SetMaxCellWidth(sizeInfo.itemsPerRow)
  bag.freeSlots:Draw()

  -- Remove the freeSlots section.
  bag.content:RemoveCell(bag.freeSlots.title:GetText(), bag.freeSlots)

  -- Sort all sections by title.
  bag.content:Sort(function(a, b)
    ---@cast a +Section
    ---@cast b +Section
    if not a.title or not b.title then return false end
    return a.title:GetText() < b.title:GetText()
  end)
  bag.content.maxCellWidth = 1
  -- Add the freeSlots section back to the end of all sections
  --bag.content:AddCellToLastColumn(bag.freeSlots.title:GetText(), bag.freeSlots)

  -- Position all sections and draw the main bag.
  local w, h = bag.content:Draw()
  -- Reposition the content frame if the recent items section is empty.
  if recentW == 0 then
    bag.content:GetContainer():SetPoint("TOPLEFT", bag.leftHeader, "BOTTOMLEFT", 3, -3)
  else
    bag.content:GetContainer():SetPoint("TOPLEFT", bag.recentItems.frame, "BOTTOMLEFT", 3, -3)
  end

  --debug:DrawDebugBorder(self.content.frame, 1, 1, 1)
  if w < 160 then
    w = 160
  end
  if h == 0 then
    h = 40
  end
  bag.content:ShowScrollBar()
  bag.frame:SetWidth(380)
  bag.frame:SetHeight(700)
end

--[[
local ScrollBox = CreateFrame("Frame", nil, UIParent, "WowScrollBox")
ScrollBox:SetPoint("CENTER")
ScrollBox:SetSize(300, 300)
ScrollBox:SetInterpolateScroll(true)

local ScrollBar = CreateFrame("EventFrame", nil, UIParent, "MinimalScrollBar")
ScrollBar:SetPoint("TOPLEFT", ScrollBox, "TOPRIGHT")
ScrollBar:SetPoint("BOTTOMLEFT", ScrollBox, "BOTTOMRIGHT")
ScrollBar:SetInterpolateScroll(true)

local ScrollView = CreateScrollBoxLinearView()
ScrollView:SetPanExtent(100)

local ScrollChild = CreateFrame("Frame", nil, ScrollBox)
ScrollChild:SetSize(300, 1500)
ScrollChild.scrollable = true

local ScrollChildFill = ScrollChild:CreateTexture()
ScrollChildFill:SetAllPoints(ScrollChild)
ScrollChildFill:SetColorTexture(1, 1, 1, 1)
ScrollChildFill:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(1, 0, 0, 1))

ScrollUtil.InitScrollBoxWithScrollBar(ScrollBox, ScrollBar, ScrollView)
--]]
AvariceGuildBank = LibStub("AceAddon-3.0"):NewAddon("AvariceGuildBank", "AceComm-3.0", "AceConsole-3.0", "AceEvent-3.0")
local AvariceGuildBankLDB = LibStub("LibDataBroker-1.1"):NewDataObject("AvariceGuildBank", {
	type = "data source",
	text = "Avarice Guild Bank",
	icon = "Interface\\Icons\\inv_misc_coin_01",
	OnTooltipShow = function(tooltip)
		tooltip:SetText("|cffb3b7ffAvarice Guild Bank|r")
		tooltip:AddLine("/avaricegb", 1, 1, 1)
		tooltip:Show()
   	end,
	OnClick = function () AvariceGuildBank:ShowMainFrame() end,
})
local minimapIcon = LibStub("LibDBIcon-1.0")
local LibSerialize = LibStub("LibSerialize")
local LibDeflate = LibStub("LibDeflate")
local AceGUI = LibStub("AceGUI-3.0")

local startMoney

local messagePrefixVersion = "AvariceGB_Ver"
local messagePrefixVersion_Request = "AvariceGB_Ver_R"
local messagePrefixTransactionLog = "AvariceGB_Log"
local messagePrefixSyncRequest = "AvariceGB_Sync"


local containerTransactionLog -- Container frame which displays the transaction log
local transactionLogRowFrames -- Table containing all rows shown in the transaction log
local transactionLogPages = { ["current"] = 1, ["total"] = 1 }
local transactionLogHeaderRow -- Table containing the header row widgets

local transactionLogEntriesPerPage = 13

-- These are declared at this level as they are used in callbacks or other functions and thus need to be accessible
local dropdownDateFilter -- Widget for date filter dropdown
local editBoxFromDate -- Widget for custom date from edit box
local editBoxToDate -- Widget for custom date to edit box
local editBoxFilterName -- Widget for name filter
local dropdownStatus -- Widget for status filter dropdown
local editboxEPAmount -- EP Award Amount widget in settings page
local labelPageCount -- Transaction Log Page count label
local buttonPageFirst -- Widget for first page button
local buttonPageLast -- Widget for last page button
local buttonPageNext -- widget for next page button
local buttonPagePrevious -- widget for previous page button
local buttonAwardEP -- Widget for action button
local buttonIgnore -- Widget for action button
local buttonSync -- Widget for action button

function AvariceGuildBank:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("AvariceGuildBankDB")
	if not self.db.realm.transactions then
		self.db.realm.transactions = {}
	end
	if not self.db.realm.settings then
		self.db.realm.settings = {}
		self.db.realm.settings["epAwardAmount"] = 25
		self.db.realm.settings["epReason"] = "Guild Bank Donation"
		self.db.realm.settings["guildName"] = "Avarice"
		self.db.realm.settings["sortAscending"] = false
		self.db.realm.settings["sortBy"] = "timestamp"
		self.db.realm.settings["filterStatus"] = { ["Pending"]=true, ["Ignored"]=false, ["EP Awarded"]=false }
		self.db.realm.settings["filterDate"] = "month"
		self.db.realm.settings["filterCustomFrom"] = "01/01/1970"
		self.db.realm.settings["filterCustomTo"] = "01/01/1970"
		self.db.realm.settings["filterName"] = ""
		
		self.db.realm.settings.minimap = { hide = false }
	end

	-- Set up minimap icon
	minimapIcon:Register("AvariceGuildBank", AvariceGuildBankLDB, self.db.realm.settings.minimap)
	if self.db.realm.settings.minimap.hide then
		minimapIcon:Hide("AvariceGuildBank")
	else
		minimapIcon:Show("AvariceGuildBank")
	end

	-- Purge old entries from the log (only keep 90 days of entries)
	-- Keeps the log from growing ridiculously large over time with data noone cares about
	AvariceGuildBank:PurgeOldEntries(GetServerTime() - 90*24*60*60)

	AvariceGuildBank:BroadcastTransactionLog()
end

function AvariceGuildBank:OnEnable()
    -- Called when the addon is enabled
	AvariceGuildBank:RegisterComm(messagePrefixVersion)
	AvariceGuildBank:RegisterComm(messagePrefixVersion_Request)
	AvariceGuildBank:RegisterComm(messagePrefixTransactionLog)
	AvariceGuildBank:RegisterComm(messagePrefixSyncRequest)
end

function AvariceGuildBank:OnDisable()
    -- Called when the addon is disabled
end

local mainFrameShown = false

function AvariceGuildBank:CreateTableHeaderRow(container)
	local row = AceGUI:Create("SimpleGroup")
	row:SetFullWidth(true)
	row:SetLayout("Flow")
	container:AddChild(row)

	row.cells = {}
	-- Select Checkbox
	row.cells[1] = AceGUI:Create("CheckBox")
	row.cells[1]:SetRelativeWidth(0.1)
	row.cells[1]:SetLabel("")
	row.cells[1]:SetTriState(true)
	row.cells[1]:SetCallback(
		"OnValueChanged",
		function(widget, callback, value)
			if value == nil then
				-- If nil, this is the tristate, and we want to skip over this and move to false
				-- The tristate will only ever be set in code, while this callback only fires on a click
				row.cells[1]:SetValue(false)
				AvariceGuildBank:SelectNoTransactions()
			elseif value == true then
				AvariceGuildBank:SelectAllTransactions()
			else
				AvariceGuildBank:SelectNoTransactions()
			end
		end
	)

	-- Date
	row.cells[2] = AceGUI:Create("InteractiveLabel")
	row.cells[2]:SetRelativeWidth(0.225)
	row.cells[2]:SetFontObject("GameFontNormal")
	row.cells[2]:SetText("Date")
	row.cells[2]:SetCallback(
		"OnClick",
		function()
			AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable("timestamp"))
		end
	)
	
	-- Player Name
	row.cells[3] = AceGUI:Create("InteractiveLabel")
	row.cells[3]:SetRelativeWidth(0.225)
	row.cells[3]:SetFontObject("GameFontNormal")
	row.cells[3]:SetText("Player Name")
	row.cells[3]:SetCallback(
		"OnClick",
		function()
			AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable("owner"))
		end
	)
	
	-- Transaction
	row.cells[4] = AceGUI:Create("InteractiveLabel")
	row.cells[4]:SetRelativeWidth(0.225)
	row.cells[4]:SetFontObject("GameFontNormal")
	row.cells[4]:SetText("Transaction")
	row.cells[4]:SetCallback(
		"OnClick",
		function()
			AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable("amount"))
		end
	)
	
	-- Status
	row.cells[5] = AceGUI:Create("InteractiveLabel")
	row.cells[5]:SetRelativeWidth(0.225)
	row.cells[5]:SetFontObject("GameFontNormal")
	row.cells[5]:SetText("Status")
	row.cells[5]:SetCallback(
		"OnClick",
		function()
			AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable("status"))
		end
	)
	
	for i, cell in pairs(row.cells) do
		row:AddChild(cell)
	end

	return row
end

function AvariceGuildBank:CreateTableRow(container)
	local row = AceGUI:Create("SimpleGroup")
	row:SetFullWidth(true)
	row:SetLayout("Flow")
	container:AddChild(row)

	row.cells = {}
	-- Select Checkbox
	row.cells[1] = AceGUI:Create("CheckBox")
	row.cells[1]:SetRelativeWidth(0.1)
	row.cells[1]:SetLabel("")
	row.cells[1]:SetCallback(
		"OnValueChanged",
		function()
			AvariceGuildBank:ProcessSelectAllTriState()
		end
	)
	-- Date
	row.cells[2] = AceGUI:Create("Label")
	row.cells[2]:SetRelativeWidth(0.225)
	-- Player Name
	row.cells[3] = AceGUI:Create("Label")
	row.cells[3]:SetRelativeWidth(0.225)
	-- Transaction
	row.cells[4] = AceGUI:Create("Label")
	row.cells[4]:SetRelativeWidth(0.225)
	-- Status
	row.cells[5] = AceGUI:Create("Label")
	row.cells[5]:SetRelativeWidth(0.225)

	for i, cell in pairs(row.cells) do
		row:AddChild(cell)
	end

	return row
end

function AvariceGuildBank:SetRowData(row, transaction)
	row["uuid"] = transaction["uuid"]
	
	-- Selected
	row.cells[1]:SetValue(false)
	
	-- Date
	row.cells[2]:SetText(date("%d/%m/%Y", transaction["timestamp"]))
	
	-- Player Name
	row.cells[3]:SetText(transaction["owner"])
	
	-- Transaction
	local amountText
	if transaction["amount"] < 0 then
		-- Deposit
		amountText = GetCoinTextureString(math.abs(transaction["amount"]))
		row.cells[4]:SetColor(0, 255, 0)
	else
		-- Withdrawal
		amountText = "(" .. GetCoinTextureString(math.abs(transaction["amount"])) .. ")"
		row.cells[4]:SetColor(255, 0, 0)
	end
	row.cells[4]:SetText(amountText)
	
	-- Status
	row.cells[5]:SetText(transaction["status"])
	
	-- Grey out the row and disable selection if the transaction has already been actioned
	if transaction["status"] ~= "Pending" then
		row.cells[1]:SetDisabled(true)
		for i = 2, 5 do
			row.cells[i]:SetColor(0.5, 0.5, 0.5)
		end
	end
end

function AvariceGuildBank:SortedTransactionTable(SortBy, Ascending)
	local sortAscending
	if Ascending == nil then
		sortAscending = true
	else
		sortAscending = Ascending
	end

	-- If sort by the same SortBy as already sorted, and no Ascending flag set, then just flip current sort direction
	if ((SortBy == self.db.realm.settings["sortBy"]) and (Ascending == nil)) then
		sortAscending = not self.db.realm.settings["sortAscending"]
	end
	
	local transactionTable = self.db.realm.transactions

	-- Apply filters before sorting
	transactionTable = AvariceGuildBank:FilteredTransactionTable(transactionTable, "status")
	transactionTable = AvariceGuildBank:FilteredTransactionTable(transactionTable, "timestamp")
	transactionTable = AvariceGuildBank:FilteredTransactionTable(transactionTable, "name")

	local sortedTransactionTable = {}

	-- Reformat into a table with numeric indexes so it can be sorted
	for uuid, transaction in pairs(transactionTable) do
		table.insert(sortedTransactionTable, {
			["uuid"] = uuid,
			["timestamp"] = transaction["timestamp"],
			["owner"] = transaction["owner"],
			["status"] = transaction["status"],
			["amount"] = transaction["amount"]
		})
	end

	-- Sort the table
	table.sort(sortedTransactionTable,
		function(a,b)
			if sortAscending then
				return a[SortBy] < b[SortBy]
			else
				return a[SortBy] > b[SortBy]
			end
		end
	)

	self.db.realm.settings["sortBy"] = SortBy
	self.db.realm.settings["sortAscending"] = sortAscending

	return sortedTransactionTable
end

function AvariceGuildBank:FilteredTransactionTable(TransactionLog, FilterBy)
	local filteredTransactionTable = {}

	if FilterBy == "status" then
		for uuid, transaction in pairs(TransactionLog) do
			if self.db.realm.settings["filterStatus"][transaction["status"]] then
				filteredTransactionTable[uuid] = transaction
			end
		end
	elseif FilterBy == "timestamp" then
		for uuid, transaction in pairs(TransactionLog) do
			if AvariceGuildBank:DateFilter(transaction["timestamp"], self.db.realm.settings["filterDate"]) then
				filteredTransactionTable[uuid] = transaction
			end
		end
	elseif FilterBy == "name" then
		if self.db.realm.settings["filterName"] == "" then
			filteredTransactionTable = TransactionLog
		else
			for uuid, transaction in pairs(TransactionLog) do
				if transaction["owner"] == self.db.realm.settings["filterName"] then
					filteredTransactionTable[uuid] = transaction
				end
			end
		end
	end

	return filteredTransactionTable
end

function AvariceGuildBank:DateFilter(TransactionTimestamp, Criteria)
	if Criteria == "week" then
		return (TransactionTimestamp >= GetServerTime() - 7*24*60*60)
	elseif Criteria == "month" then
		return (TransactionTimestamp >= GetServerTime() - 30*24*60*60)
	elseif Criteria == "custom" then
		-- Get timestamp from text
		local fromTimestamp = AvariceGuildBank:DateStringToTimestamp(self.db.realm.settings["filterCustomFrom"])
		local toTimestamp = AvariceGuildBank:DateStringToTimestamp(self.db.realm.settings["filterCustomTo"])
		return (TransactionTimestamp >= fromTimestamp) and (TransactionTimestamp <= toTimestamp)
	else
		return true
	end
end

function AvariceGuildBank:DateStringToTimestamp(DateString)
	local dateTable = {}
	local i = 0
	
	for segment in DateString:gmatch("([^/]+)") do
		i = i + 1
		dateTable[i] = segment
	end

	return time{year=dateTable[3], month=dateTable[2], day=dateTable[1]}
end

function AvariceGuildBank:PopulateContainer_TransactionLog(TransactionLog, Page)
	-- Pause layout of the container to make changing it more efficient
	containerTransactionLog:PauseLayout()

	-- Make sure the container is empty before populating it
	containerTransactionLog:ReleaseChildren()
	
	local table = AceGUI:Create("ScrollFrame")
	table:SetLayout("List")
	containerTransactionLog:AddChild(table)

	transactionLogRowFrames = {}

	if Page == nil then
		transactionLogPages["current"] = 1
	else
		transactionLogPages["current"] = Page
	end

	-- Paginate transaction log
	local paginatedTransactionLog = {}
	for i, transaction in pairs(TransactionLog) do
		local currentPage = math.floor((i-1)/transactionLogEntriesPerPage) + 1
		if paginatedTransactionLog[currentPage] == nil then
			paginatedTransactionLog[currentPage] = {}
		end
		paginatedTransactionLog[currentPage][i] = transaction
		transactionLogPages["total"] = currentPage
	end

	-- If after pagination the page we were requested to change to is out of bounds, set it to the last page
	if transactionLogPages["current"] > transactionLogPages["total"] then
		transactionLogPages["current"] = transactionLogPages["total"]
	end

	labelPageCount:SetText("Page " .. transactionLogPages["current"] .. " / " .. transactionLogPages["total"])
	if transactionLogPages["current"] == 1 then
		-- if we only have 1 page total, then disable everything
		if transactionLogPages["total"] == 1 then
			buttonPageNext:SetDisabled(true)
			buttonPageLast:SetDisabled(true)
		else
			buttonPageNext:SetDisabled(false)
			buttonPageLast:SetDisabled(false)
		end
		buttonPageFirst:SetDisabled(true)
		buttonPagePrevious:SetDisabled(true)
	elseif transactionLogPages["current"] == transactionLogPages["total"] then
		buttonPageFirst:SetDisabled(false)
		buttonPageLast:SetDisabled(true)
		buttonPageNext:SetDisabled(true)
		buttonPagePrevious:SetDisabled(false)	
	else
		buttonPageFirst:SetDisabled(false)
		buttonPageLast:SetDisabled(false)
		buttonPageNext:SetDisabled(false)
		buttonPagePrevious:SetDisabled(false)
	end

	-- Create a table row for each transaction in the log
	-- We first make sure our paginated log actually has entries in case we filtered everything out
	if paginatedTransactionLog[transactionLogPages["current"]] ~= nil then
		for i, transaction in pairs(paginatedTransactionLog[transactionLogPages["current"]]) do
			transactionLogRowFrames[i] = AvariceGuildBank:CreateTableRow(table)
			AvariceGuildBank:SetRowData(transactionLogRowFrames[i], transaction)
		end
	end
	
	-- Clear the "select all" checkbox since all selections are cleared on repopulation
	transactionLogHeaderRow.cells[1]:SetValue(false)

	-- Resume and relayout the container
	containerTransactionLog:ResumeLayout()
	containerTransactionLog:DoLayout()
end

function AvariceGuildBank:DrawFrame_Log(container)
	local logFrameMainContainer = AceGUI:Create("SimpleGroup")
	logFrameMainContainer:SetFullWidth(true)
	logFrameMainContainer:SetFullHeight(true)
	logFrameMainContainer:SetLayout("Flow")
	container:AddChild(logFrameMainContainer)

	local headingActions = AceGUI:Create("Heading")
	headingActions:SetText("Actions")
	headingActions:SetFullWidth(true)
	logFrameMainContainer:AddChild(headingActions)

		local labelActions = AceGUI:Create("Label")
		labelActions:SetText("Actions are applied for everyone and cannot be undone. For example, ignoring a transaction will mark it as ignored for all members.")
		labelActions:SetFullWidth(true)
		logFrameMainContainer:AddChild(labelActions)

		local actionsRow1 = AceGUI:Create("SimpleGroup")
		actionsRow1:SetFullWidth(true)
		actionsRow1:SetLayout("Flow")
		logFrameMainContainer:AddChild(actionsRow1)

			buttonAwardEP = AceGUI:Create("Button")
			buttonAwardEP:SetText("Award EP")
			buttonAwardEP:SetRelativeWidth(1/3)
			buttonAwardEP:SetDisabled(not C_GuildInfo.CanViewOfficerNote() or SlashCmdList["ACECONSOLE_EPGP"] == nil)
			buttonAwardEP:SetCallback("OnClick", function() AvariceGuildBank:ApplyActionToSelectedRows("AwardEP") end)
			actionsRow1:AddChild(buttonAwardEP)

			buttonIgnore = AceGUI:Create("Button")
			buttonIgnore:SetText("Ignore")
			buttonIgnore:SetRelativeWidth(1/3)
			buttonIgnore:SetDisabled(not C_GuildInfo.CanViewOfficerNote())
			buttonIgnore:SetCallback("OnClick", function() AvariceGuildBank:ApplyActionToSelectedRows("Ignore") end)
			actionsRow1:AddChild(buttonIgnore)

			buttonSync = AceGUI:Create("Button")
			buttonSync:SetText("Sync")
			buttonSync:SetRelativeWidth(1/3)
			buttonSync:SetCallback("OnClick", function() AvariceGuildBank:SendSyncRequest() end)
			actionsRow1:AddChild(buttonSync)

	local headingFilter = AceGUI:Create("Heading")
	headingFilter:SetText("Filter")
	headingFilter:SetFullWidth(true)
	logFrameMainContainer:AddChild(headingFilter)

		local filterRow1 = AceGUI:Create("SimpleGroup")
		filterRow1:SetFullWidth(true)
		filterRow1:SetLayout("Flow")
		logFrameMainContainer:AddChild(filterRow1)

			dropdownDateFilter = AceGUI:Create("Dropdown")
			dropdownDateFilter:SetLabel("Date Range:")
			dropdownDateFilter:SetRelativeWidth(0.2)
			dropdownDateFilter:SetList(
				{
					["week"] = "Past Week",
					["month"] = "Past Month",
					["all"] = "All Time",
					["custom"] = "Custom"
				},
				{
					[1] = "week",
					[2] = "month",
					[3] = "all",
					[4] = "custom"
				}
			)
			dropdownDateFilter:SetValue(self.db.realm.settings["filterDate"])
			dropdownDateFilter:SetCallback(
				"OnValueChanged",
				function(widget, callbackname, key)
					self.db.realm.settings["filterDate"] = key
					if key == "custom" then
						editBoxFromDate:SetDisabled(false)
						editBoxToDate:SetDisabled(false)
					else
						editBoxFromDate:SetDisabled(true)
						editBoxToDate:SetDisabled(true)
					end
					AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable(self.db.realm.settings["sortBy"], self.db.realm.settings["sortAscending"]))
				end
			)
			filterRow1:AddChild(dropdownDateFilter)

			editBoxFromDate = AceGUI:Create("EditBox")
			editBoxFromDate:SetLabel("From (dd/mm/yyyy):")
			editBoxFromDate:SetText(self.db.realm.settings["filterCustomFrom"])
			editBoxFromDate:SetRelativeWidth(0.2)
			editBoxFromDate:SetDisabled(true)
			editBoxFromDate:SetCallback(
				"OnEnterPressed",
				function(widget, event, text)
					if AvariceGuildBank:ValidateStringAgainstPattern(text, "^%d%d/%d%d/%d%d%d%d$") or
					   AvariceGuildBank:ValidateStringAgainstPattern(text, "^%d/%d/%d%d%d%d$") or
					   AvariceGuildBank:ValidateStringAgainstPattern(text, "^%d%d/%d/%d%d%d%d$") or
					   AvariceGuildBank:ValidateStringAgainstPattern(text, "^%d/%d%d/%d%d%d%d$")
					   then
						self.db.realm.settings["filterCustomFrom"] = text
					else
						editBoxFromDate:SetLabel("|cffff0000Invalid date format!|r")
						C_Timer.After(2, function() editBoxFromDate:SetLabel("From (dd/mm/yyyy):") end)
						editBoxFromDate:SetText(self.db.realm.settings["filterCustomFrom"])
					end
					AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable(self.db.realm.settings["sortBy"], self.db.realm.settings["sortAscending"]))
				end
			)
			filterRow1:AddChild(editBoxFromDate)

			editBoxToDate = AceGUI:Create("EditBox")
			editBoxToDate:SetLabel("To (dd/mm/yyyy):")
			editBoxToDate:SetText(self.db.realm.settings["filterCustomTo"])
			editBoxToDate:SetRelativeWidth(0.2)
			editBoxToDate:SetDisabled(true)
			editBoxToDate:SetCallback(
				"OnEnterPressed",
				function(widget, event, text)
					if AvariceGuildBank:ValidateStringAgainstPattern(text, "^%d%d/%d%d/%d%d%d%d$") or
					   AvariceGuildBank:ValidateStringAgainstPattern(text, "^%d/%d/%d%d%d%d$") or
					   AvariceGuildBank:ValidateStringAgainstPattern(text, "^%d%d/%d/%d%d%d%d$") or
					   AvariceGuildBank:ValidateStringAgainstPattern(text, "^%d/%d%d/%d%d%d%d$")
					   then
						self.db.realm.settings["filterCustomTo"] = text
					else
						editBoxToDate:SetLabel("|cffff0000Invalid date format!|r")
						C_Timer.After(2, function() editBoxToDate:SetLabel("To (dd/mm/yyyy):") end)
						editBoxFromDate:SetText(self.db.realm.settings["filterCustomTo"])
					end
					AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable(self.db.realm.settings["sortBy"], self.db.realm.settings["sortAscending"]))
				end
			)
			filterRow1:AddChild(editBoxToDate)

			editBoxFilterName = AceGUI:Create("EditBox")
			editBoxFilterName:SetLabel("Player Name:")
			editBoxFilterName:SetText(self.db.realm.settings["filterName"])
			editBoxFilterName:SetRelativeWidth(0.2)
			editBoxFilterName:SetCallback(
				"OnEnterPressed",
				function(widget, event, text)
					self.db.realm.settings["filterName"] = text
					AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable(self.db.realm.settings["sortBy"], self.db.realm.settings["sortAscending"]))
				end
			)
			filterRow1:AddChild(editBoxFilterName)

			dropdownStatus = AceGUI:Create("Dropdown")
			dropdownStatus:SetLabel("Status:")
			dropdownStatus:SetRelativeWidth(0.2)
			dropdownStatus:SetMultiselect(true)
			dropdownStatus:SetList(
				{
					["Pending"] = "Pending",
					["Ignored"] = "Ignored",
					["EP Awarded"] = "EP Awarded"
				},
				{
					[1] = "Pending",
					[2] = "EP Awarded",
					[3] = "Ignored"
				}
			)
			dropdownStatus:SetItemValue("Pending", self.db.realm.settings["filterStatus"]["Pending"])
			dropdownStatus:SetItemValue("Ignored", self.db.realm.settings["filterStatus"]["Ignored"])
			dropdownStatus:SetItemValue("EP Awarded", self.db.realm.settings["filterStatus"]["EP Awarded"])
			dropdownStatus:SetCallback(
				"OnValueChanged",
				function(widget, callbackname, key, checked)
					self.db.realm.settings["filterStatus"][key] = checked
					AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable(self.db.realm.settings["sortBy"], self.db.realm.settings["sortAscending"]))
				end)
			filterRow1:AddChild(dropdownStatus)

	local headingTransactionLog = AceGUI:Create("Heading")
	headingTransactionLog:SetText("Transaction Log")
	headingTransactionLog:SetFullWidth(true)
	logFrameMainContainer:AddChild(headingTransactionLog)
		
	local pageControlsRow = AceGUI:Create("SimpleGroup")
	pageControlsRow:SetFullWidth(true)
	pageControlsRow:SetLayout("Flow")
	logFrameMainContainer:AddChild(pageControlsRow)

		buttonPageFirst = AceGUI:Create("Button")
		buttonPageFirst:SetText("<<")
		buttonPageFirst:SetRelativeWidth(1/5)
		buttonPageFirst:SetCallback(
			"OnClick",
			function()
				AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable(self.db.realm.settings["sortBy"], self.db.realm.settings["sortAscending"]), 1)
			end
		)
		pageControlsRow:AddChild(buttonPageFirst)

		buttonPagePrevious = AceGUI:Create("Button")
		buttonPagePrevious:SetText("<")
		buttonPagePrevious:SetRelativeWidth(1/5)
		buttonPagePrevious:SetCallback(
			"OnClick",
			function()
				AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable(self.db.realm.settings["sortBy"], self.db.realm.settings["sortAscending"]), transactionLogPages["current"] - 1)
			end
		)
		pageControlsRow:AddChild(buttonPagePrevious)

		labelPageCount = AceGUI:Create("Label")
		labelPageCount:SetText("Page " .. transactionLogPages["current"] .. " / " .. transactionLogPages["total"])
		labelPageCount:SetRelativeWidth(1/5)
		labelPageCount:SetJustifyH("CENTER")
		pageControlsRow:AddChild(labelPageCount)

		buttonPageNext = AceGUI:Create("Button")
		buttonPageNext:SetText(">")
		buttonPageNext:SetRelativeWidth(1/5)
		buttonPageNext:SetCallback(
			"OnClick",
			function()
				AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable(self.db.realm.settings["sortBy"], self.db.realm.settings["sortAscending"]), transactionLogPages["current"] + 1)
			end
		)
		pageControlsRow:AddChild(buttonPageNext)

		buttonPageLast = AceGUI:Create("Button")
		buttonPageLast:SetText(">>")
		buttonPageLast:SetRelativeWidth(1/5)
		buttonPageLast:SetCallback(
			"OnClick",
			function()
				AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable(self.db.realm.settings["sortBy"], self.db.realm.settings["sortAscending"]), transactionLogPages["total"])
			end
		)
		pageControlsRow:AddChild(buttonPageLast)
	
	-- Transaction Table
	transactionLogHeaderRow = AvariceGuildBank:CreateTableHeaderRow(logFrameMainContainer)
	
	containerTransactionLog = AceGUI:Create("SimpleGroup")
	containerTransactionLog:SetFullWidth(true)
	containerTransactionLog:SetFullHeight(true)
	containerTransactionLog:SetLayout("Fill")
	logFrameMainContainer:AddChild(containerTransactionLog)

	AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable(self.db.realm.settings["sortBy"], self.db.realm.settings["sortAscending"]))
end

function AvariceGuildBank:DrawFrame_Settings(container)
	local scrollContainer = AceGUI:Create("SimpleGroup")
	scrollContainer:SetFullWidth(true)
	scrollContainer:SetFullHeight(true)
	scrollContainer:SetLayout("Fill")

	container:AddChild(scrollContainer)

		local settingsScroll = AceGUI:Create("ScrollFrame")
		settingsScroll:SetLayout("Flow")
		scrollContainer:AddChild(settingsScroll)

			local headingGeneral = AceGUI:Create("Heading")
			headingGeneral:SetText("General")
			headingGeneral:SetFullWidth(true)
			settingsScroll:AddChild(headingGeneral)

				local editboxGuildName = AceGUI:Create("EditBox")
				editboxGuildName:SetRelativeWidth(0.25)
				editboxGuildName:SetLabel("Guild Name:")
				editboxGuildName:SetText(self.db.realm.settings["guildName"])
				editboxGuildName:SetDisabled(true)
				editboxGuildName:SetCallback(
					"OnEnterPressed",
					function(widget, callback, text)
						self.db.realm.settings["guildName"] = text
					end
				)
				settingsScroll:AddChild(editboxGuildName)

				local labelGuildNameSpacer = AceGUI:Create("Label")
				labelGuildNameSpacer:SetRelativeWidth(0.05)
				settingsScroll:AddChild(labelGuildNameSpacer)

				local labelGuildName = AceGUI:Create("Label")
				labelGuildName:SetText("Sets the guild name to log transactions for.")
				labelGuildName:SetRelativeWidth(0.7)
				settingsScroll:AddChild(labelGuildName)



				local checkboxMinimapIconShow = AceGUI:Create("CheckBox")
				checkboxMinimapIconShow:SetRelativeWidth(0.25)
				checkboxMinimapIconShow:SetLabel("Show Minimap Icon")
				checkboxMinimapIconShow:SetValue(not self.db.realm.settings.minimap.hide)
				checkboxMinimapIconShow:SetCallback(
					"OnValueChanged",
					function(widget, callback, value)
						self.db.realm.settings.minimap.hide = not value
						if self.db.realm.settings.minimap.hide then
							minimapIcon:Hide("AvariceGuildBank")
						else
							minimapIcon:Show("AvariceGuildBank")
						end
					end
				)
				settingsScroll:AddChild(checkboxMinimapIconShow)

				local labelMinimapIconShowSpacer = AceGUI:Create("Label")
				labelMinimapIconShowSpacer:SetRelativeWidth(0.05)
				settingsScroll:AddChild(labelMinimapIconShowSpacer)

				local labelMinimapIconShow = AceGUI:Create("Label")
				labelMinimapIconShow:SetText("Enables/disables the minimap icon.")
				labelMinimapIconShow:SetRelativeWidth(0.7)
				settingsScroll:AddChild(labelMinimapIconShow)
				

			local headingEPAward = AceGUI:Create("Heading")
			headingEPAward:SetText("EP Award")
			headingEPAward:SetFullWidth(true)
			settingsScroll:AddChild(headingEPAward)

				editboxEPAmount = AceGUI:Create("EditBox")
				editboxEPAmount:SetRelativeWidth(0.25)
				editboxEPAmount:SetLabel("EP Award Amount:")
				editboxEPAmount:SetText(self.db.realm.settings["epAwardAmount"])
				editboxEPAmount:SetCallback(
					"OnEnterPressed",
					function(widget, callback, text)
						if AvariceGuildBank:ValidateStringAgainstPattern(text, "^%d+$") then
							self.db.realm.settings["epAwardAmount"] = text
						else
							editboxEPAmount:SetLabel("|cffff0000EP Amount must be a number!|r")
							C_Timer.After(2, function() editboxEPAmount:SetLabel("EP Award Amount:") end)
							editboxEPAmount:SetText(self.db.realm.settings["epAwardAmount"])
						end
					end
				)
				settingsScroll:AddChild(editboxEPAmount)

				local labelEPAmountSpacer = AceGUI:Create("Label")
				labelEPAmountSpacer:SetRelativeWidth(0.05)
				settingsScroll:AddChild(labelEPAmountSpacer)

				local labelEPAmount = AceGUI:Create("Label")
				labelEPAmount:SetText("Sets the amount of EP awarded to each player when the |cffb3b7ff[Award EP]|r action is taken.")
					labelEPAmount:SetRelativeWidth(0.7)
				settingsScroll:AddChild(labelEPAmount)

				

				local editboxEPReason = AceGUI:Create("EditBox")
				editboxEPReason:SetRelativeWidth(0.25)
				editboxEPReason:SetLabel("EP Reason:")
				editboxEPReason:SetText(self.db.realm.settings["epReason"])
				editboxEPReason:SetCallback(
					"OnEnterPressed",
					function(widget, callback, text)
						self.db.realm.settings["epReason"] = text
					end
				)
				settingsScroll:AddChild(editboxEPReason)

				local labelEPReasonSpacer = AceGUI:Create("Label")
				labelEPReasonSpacer:SetRelativeWidth(0.05)
				settingsScroll:AddChild(labelEPReasonSpacer)

				local labelEPReason = AceGUI:Create("Label")
				labelEPReason:SetText("Sets the reason to be used when awarding EP when the |cffb3b7ff[Award EP]|r action is taken.")
				labelEPReason:SetRelativeWidth(0.7)
				settingsScroll:AddChild(labelEPReason)

			-- local headingDebug = AceGUI:Create("Heading")
			-- headingDebug:SetText("Debug")
			-- headingDebug:SetFullWidth(true)
			-- settingsScroll:AddChild(headingDebug)

			-- 	local buttonClearDB = AceGUI:Create("Button")
			-- 	buttonClearDB:SetText("Clear DB")
			-- 	buttonClearDB:SetRelativeWidth(0.25)
			-- 	buttonClearDB:SetCallback("OnClicked", function() AvariceGuildBank:ClearDatabase() end)
			-- 	settingsScroll:AddChild(buttonClearDB)

			-- 	local labelClearDBSpacer = AceGUI:Create("Label")
			-- 	labelClearDBSpacer:SetRelativeWidth(0.05)
			-- 	settingsScroll:AddChild(labelClearDBSpacer)
			
			-- 	local labelClearDB = AceGUI:Create("Label")
			-- 	labelClearDB:SetText("Clears your copy of the AvariceGuildBank database. It is recommended you do a |cffb3b7ff[Sync]|r afterwards to rebuild your database. Will cause a reload of the UI.")
			-- 	labelClearDB:SetRelativeWidth(0.7)
			-- 	settingsScroll:AddChild(labelClearDB)

end

function AvariceGuildBank:DrawFrame_Help(container)
	local scrollContainer = AceGUI:Create("SimpleGroup")
	scrollContainer:SetFullWidth(true)
	scrollContainer:SetFullHeight(true)
	scrollContainer:SetLayout("Fill")

	container:AddChild(scrollContainer)

		local helpScroll = AceGUI:Create("ScrollFrame")
		helpScroll:SetLayout("Flow")
		scrollContainer:AddChild(helpScroll)

			local headingOverview = AceGUI:Create("Heading")
			headingOverview:SetText("Overview")
			headingOverview:SetFullWidth(true)
			helpScroll:AddChild(headingOverview)

				local labelOverview = AceGUI:Create("Label")
				labelOverview:SetText(
					"Avarice Guild Bank provides an extension to the built in guild bank money log to enable a more comprehensive analysis of incoming and outgoing expenses over time, along with supporting an efficient means of providing EP rewards for donations by guild members.\n\n" ..
					"Avarice Guild Bank will only track transactions conducted by those who have the addon, and will promulgate its complete database between all users of the addon within the guild.\n\n" ..
					"Please note that transaction data will only be held up to a maximum of three months from the date of the transaction. All data older than this will be purged from the database on load."
				)
				labelOverview:SetFullWidth(true)
				helpScroll:AddChild(labelOverview)

			local headingSynchronisation = AceGUI:Create("Heading")
			headingSynchronisation:SetText("Synchronisation")
			headingSynchronisation:SetFullWidth(true)
			helpScroll:AddChild(headingSynchronisation)

				local labelSynchronisation = AceGUI:Create("Label")
				labelSynchronisation:SetText(
					"Avarice Guild Bank maintains a local table of all transactions conducted and synchronises this database both automatically and manually as triggered by the user.\n\n" ..
					"Data will be automatically broadcast to all online guild members after the following events:\n" ..
					" - Upon logging into the game.\n" ..
					" - After closing the Blizzard Guild Bank window.\n" ..
					" - After closing the Avarice Guild Bank window (this window).\n\n" ..
					"Data may also be manually synchronised by clicking the |cffb3b7ff[Sync]|r button on the |cffb3b7ff[Log]|r tab. Doing this will request all online guild members to send you their database.\n\n" ..
					"Please note that the manual synchronisation option may take a short amount of time to complete, depending on how many guild members are online at the time."
				)
				labelSynchronisation:SetFullWidth(true)
				helpScroll:AddChild(labelSynchronisation)

			local headingTransactionLog = AceGUI:Create("Heading")
			headingTransactionLog:SetText("Transaction Log")
			headingTransactionLog:SetFullWidth(true)
			helpScroll:AddChild(headingTransactionLog)

				local labelTransactionLog = AceGUI:Create("Label")
				labelTransactionLog:SetText(
					"On the |cffb3b7ff[Log]|r tab, the lower half of the frame consists of the Transaction Log. Here you will be able to see all transactions that match the current filter settings, and can select transactions to apply actions to.\n\n" ..
					"Deposits are shown in green text (|cff00ff00" .. GetCoinTextureString(10000) .. "|r), while withdrawals are shown in red text surrounded by parentheses (|cffff0000(" .. GetCoinTextureString(10000) .. ")|r).\n\n" ..
					"Select transactions to apply actions to by ticking the checkbox to the left of the desired transaction. Multiple transactions may be selected and actioned in a single step. Please note that only actions with a status of “Pending” may be selected.\n\n" ..
					"You can select/deselect all transactions by using the checkbox in the header row.\n\n" ..
					"Change pages by using the |cffb3b7ff[<<][<][>][>>]|r controls located at the top of the transaction log."
				)
				labelTransactionLog:SetFullWidth(true)
				helpScroll:AddChild(labelTransactionLog)

			local headingFilteringSorting = AceGUI:Create("Heading")
			headingFilteringSorting:SetText("Filtering and Sorting")
			headingFilteringSorting:SetFullWidth(true)
			helpScroll:AddChild(headingFilteringSorting)

				local subheadingFiltering = AceGUI:Create("Label")
				subheadingFiltering:SetText("Filtering")
				subheadingFiltering:SetColor(1, 0.83, 0.07)
				subheadingFiltering:SetFullWidth(true)
				subheadingFiltering:SetFontObject("GameFontNormal")
				helpScroll:AddChild(subheadingFiltering)
			
				local labelFiltering = AceGUI:Create("Label")
				labelFiltering:SetText(
					"The Transaction Log can be filtered based on the date and status of the transaction. Simply use the dropdowns to select the desired options and the transactions displayed will update to match.\n\n" ..
					"Please note that if using custom date filtering, then custom dates must be entered in the format |cffb3b7ffdd/mm/yyyy|r. Attempting to enter a date in any other format will be denied."
				)
				labelFiltering:SetFullWidth(true)
				helpScroll:AddChild(labelFiltering)

				local subheadingSorting = AceGUI:Create("Label")
				subheadingSorting:SetText("\nSorting")
				subheadingSorting:SetColor(1, 0.83, 0.07)
				subheadingSorting:SetFullWidth(true)
				subheadingSorting:SetFontObject("GameFontNormal")
				helpScroll:AddChild(subheadingSorting)
			
				local labelSorting = AceGUI:Create("Label")
				labelSorting:SetText(
					"The Transaction Log can be sorted by clicking on any of the header labels (e.g. Status). Click the same label multiple times to change the order of the sort."
				)
				labelSorting:SetFullWidth(true)
				helpScroll:AddChild(labelSorting)

			local headingActions = AceGUI:Create("Heading")
			headingActions:SetText("Actions")
			headingActions:SetFullWidth(true)
			helpScroll:AddChild(headingActions)

				local labelActionsOverview = AceGUI:Create("Label")
				labelActionsOverview:SetText(
					"The Action buttons allow you to apply particular actions to transactions in the log. Please note that all actions are final, and only one action may be taken for any given transaction. That is, if you ignore a transaction then this transaction will be ignored for all other guild members. Likewise if you award EP to a transaction, this transaction will be marked as having been awarded EP for all other guild members.\n\n" ..
					"Actions will be applied to all currently selected transactions in the log.\n\n" ..
					"Actions are only able to be performed by those with suitable permissions in the guild (i.e. officers). For those players with insufficient privileges these buttons will be disabled."
				)
				labelActionsOverview:SetFullWidth(true)
				helpScroll:AddChild(labelActionsOverview)

				local subheadingAwardEP = AceGUI:Create("Label")
				subheadingAwardEP:SetText("\nAward EP")
				subheadingAwardEP:SetColor(1, 0.83, 0.07)
				subheadingAwardEP:SetFullWidth(true)
				subheadingAwardEP:SetFontObject("GameFontNormal")
				helpScroll:AddChild(subheadingAwardEP)
			
				local labelAwardEP = AceGUI:Create("Label")
				labelAwardEP:SetText(
					"Awards the amount of EP as specified in |cffb3b7ff[Settings]|r to the player who made each selected transaction.\n\n" ..
					"Please note that this will award the EP amount once per transaction selected. That is, if multiple transactions made by the same player are selected then EP will be awarded multiple times to this player, once for each selected transaction belonging to that player.\n\n" ..
					"This action will only be available if you can see officer notes and have the EPGP-Classic addon installed."
				)
				labelAwardEP:SetFullWidth(true)
				helpScroll:AddChild(labelAwardEP)

				local subheadingIgnore = AceGUI:Create("Label")
				subheadingIgnore:SetText("\nIgnore")
				subheadingIgnore:SetColor(1, 0.83, 0.07)
				subheadingIgnore:SetFullWidth(true)
				subheadingIgnore:SetFontObject("GameFontNormal")
				helpScroll:AddChild(subheadingIgnore)
			
				local labelIgnore = AceGUI:Create("Label")
				labelIgnore:SetText(
					"Marks the transaction as ignored.\n\n" ..
					"This is useful to allow you to acknowledge a given transaction as having been assessed and not relevant for the purposes of awarding EP (for example, depositing the proceeds from selling guild bank items).\n\n" ..
					"The main purpose of the Ignore function is to allow filtering of transactions by “Pending” to see only new transactions that have been made since EP was last awarded.\n\n" ..
					"It is heavily recommended to ignore any superfluous transactions and filter them out to improve performance of the Avarice Guild Bank frame."
				)
				labelIgnore:SetFullWidth(true)
				helpScroll:AddChild(labelIgnore)

end

-- Callback function for OnGroupSelected
local function SelectTabGroup(container, event, group)
	container:ReleaseChildren()
	if group == "log" then
		AvariceGuildBank:DrawFrame_Log(container)
	elseif group == "settings" then
		AvariceGuildBank:DrawFrame_Settings(container)
	elseif group == "help" then
		AvariceGuildBank:DrawFrame_Help(container)
	end
end

function AvariceGuildBank:ShowMainFrame()
	-- Don't redraw the frame if it's already shown
	if mainFrameShown then
		return
	else
		mainFrameShown = true
	end

	-- Create Main Frame
	local mainFrame = AceGUI:Create("Frame")
	mainFrame:SetTitle("Avarice Guild Bank")
	mainFrame:SetStatusText("/avaricegb v" .. GetAddOnMetadata("AvariceGuildBank", "version") .. " by Malfos")
	mainFrame:SetCallback(
		"OnClose",
		function(widget)
			AceGUI:Release(widget)
			mainFrameShown = false
			AvariceGuildBank:BroadcastTransactionLog()
		end
	)
	mainFrame:SetWidth(600)
	mainFrame:SetHeight(700)
	mainFrame.frame:SetMinResize(600, 700)
	mainFrame.frame:SetMaxResize(600, 2000)
	mainFrame:SetLayout("Fill")

	-- Add the main frame to the global frame list so that hitting Escape will close it
	-- Add the frame as a global variable under the name `AvariceGuildBankMainFrame`
    _G["AvariceGuildBankMainFrame"] = mainFrame.frame
    -- Register the global variable `AvariceGuildBankMainFrame` as a "special frame"
    -- so that it is closed when the escape key is pressed.
    tinsert(UISpecialFrames, "AvariceGuildBankMainFrame")

	-- Create the TabGroup
	local tab = AceGUI:Create("TabGroup")
	tab:SetLayout("Flow")
	-- Set up which tabs to show
	tab:SetTabs(
		{
			{
				text = "Log",
				value = "log"
			},
			{
				text = "Settings",
				value = "settings"
			},
			{
				text = "Help",
				value = "help"
			}
		}
	)
	-- Register callback
	tab:SetCallback("OnGroupSelected", SelectTabGroup)
	-- Set Initial Tab (this will fire the OnGroupSelected callback)
	tab:SelectTab("log")

	-- Add to the frame container
	mainFrame:AddChild(tab)
end

function AvariceGuildBank:TransmitComm(prefix, data, channel, target)
	local serialized = LibSerialize:Serialize(data)
    local compressed = LibDeflate:CompressDeflate(serialized)
    local encoded = LibDeflate:EncodeForWoWAddonChannel(compressed)
    if channel == "WHISPER" then
		AvariceGuildBank:SendCommMessage(prefix, encoded, "WHISPER", target)
	else
		AvariceGuildBank:SendCommMessage(prefix, encoded, channel)
	end	
end

function AvariceGuildBank:OnCommReceived(prefix, payload, distribution, sender)
    local decoded = LibDeflate:DecodeForWoWAddonChannel(payload)
    if not decoded then
		AvariceGuildBank:LogError("Decoding received message failed")
		return
	end
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
		AvariceGuildBank:LogError("Decompressing received message failed")
		return
	end
    local success, data = LibSerialize:Deserialize(decompressed)
    if not success then
		AvariceGuildBank:LogError("Deserializing received message failed")
		return
	end

    -- Handle 'data'
	if prefix == messagePrefixTransactionLog then
		AvariceGuildBank:ParseReceivedTransactionLog(data)
	elseif prefix == messagePrefixVersion then
		AvariceGuildBank:Print("[VERSION] " ..data .. " : " .. sender)
	elseif prefix == messagePrefixVersion_Request then
		AvariceGuildBank:SendVersion(sender)
	elseif prefix == messagePrefixSyncRequest then
		AvariceGuildBank:WhisperTransactionLog(sender)
	end
end

function AvariceGuildBank:GUILDBANK_UPDATE_WITHDRAWMONEY(event)
	-- GUILDBANK_UPDATE_WITHDRAWMONEY fires on load for some reason, however the GuildBankFrame doesn't get
	-- loaded until you access the guild bank, so we can just check if the GuildBankFrame exists when this event
	-- fires to see if it's a legit event that we need to handle.
	if (GuildBankFrame) then
		C_Timer.After(0.5, function() AvariceGuildBank:ProcessTransaction() end)
	end
end

function AvariceGuildBank:GUILDBANKFRAME_OPENED(event)
	startMoney = GetMoney()
end

function AvariceGuildBank:GUILDBANKFRAME_CLOSED(event)
	AvariceGuildBank:BroadcastTransactionLog()
end

function AvariceGuildBank:ApplyActionToSelectedRows(Action)
	AvariceGuildBank:SetProcessingState(true, Action)
	local delayCounter = 0
	for i, row in pairs(transactionLogRowFrames) do
		if row.cells[1]:GetValue() then
			if Action == "Ignore" then
				AvariceGuildBank:IgnoreTransaction(row["uuid"])
			elseif Action == "AwardEP" then
				-- We have to add a delay otherwise the EP commands get lost in the ether
				delayCounter = delayCounter + 1
				C_Timer.After(0.5*delayCounter, function() AvariceGuildBank:AwardEP(row["uuid"]) end)
			else
				AvariceGuildBank:LogError("Invalid action requested: " .. Action, true)
			end
		end
	end
	C_Timer.After(
		0.5*delayCounter+1,
		function()
			AvariceGuildBank:SetProcessingState(false)
			AvariceGuildBank:PopulateContainer_TransactionLog(AvariceGuildBank:SortedTransactionTable(self.db.realm.settings["sortBy"], self.db.realm.settings["sortAscending"]), transactionLogPages["current"])
		end
	)
end

function AvariceGuildBank:SetProcessingState(State, Action)
	-- Sort controls
	for i = 1, 5 do
		transactionLogHeaderRow.cells[i]:SetDisabled(State)
	end

	-- Filter controls
	dropdownDateFilter:SetDisabled(State)
	editBoxFilterName:SetDisabled(State)
	dropdownStatus:SetDisabled(State)
	if not State then
		if self.db.realm.settings["filterDate"] == "custom" then
			editBoxFromDate:SetDisabled(State)
			editBoxToDate:SetDisabled(State)
		end
	else
		editBoxFromDate:SetDisabled(State)
		editBoxToDate:SetDisabled(State)
	end

	-- Pagination controls
	buttonPageFirst:SetDisabled(State)
	buttonPageLast:SetDisabled(State)
	buttonPageNext:SetDisabled(State)
	buttonPagePrevious:SetDisabled(State)

	-- Action buttons
	buttonAwardEP:SetDisabled(State)
	buttonIgnore:SetDisabled(State)
	buttonSync:SetDisabled(State)

	if State then
		if Action == "AwardEP" then
			buttonAwardEP:SetText("Processing...")
		elseif Action == "Ignore" then
			buttonIgnore:SetText("Processing...")
		end
	else
		buttonAwardEP:SetText("Award EP")
		buttonIgnore:SetText("Ignore")
		buttonSync:SetText("Sync")
	end
end

function AvariceGuildBank:SelectAllTransactions()
	for i, row in pairs(transactionLogRowFrames) do
		if self.db.realm.transactions[row.uuid]["status"] == "Pending" then
			row.cells[1]:SetValue(true)
		end
	end
end

function AvariceGuildBank:SelectNoTransactions()
	for i, row in pairs(transactionLogRowFrames) do
		row.cells[1]:SetValue(false)
	end
end

function AvariceGuildBank:ProcessSelectAllTriState()
	local countTotal = 0
	local countChecked = 0
	
	for i, row in pairs(transactionLogRowFrames) do
		if self.db.realm.transactions[row.uuid]["status"] == "Pending" then
			countTotal = countTotal + 1

			if row.cells[1]:GetValue() then
				countChecked = countChecked + 1
			end
		end
	end

	if countChecked == countTotal then
		transactionLogHeaderRow.cells[1]:SetValue(true)
	elseif countChecked > 0 then
		transactionLogHeaderRow.cells[1]:SetValue(nil)
	else
		transactionLogHeaderRow.cells[1]:SetValue(false)
	end
end

function AvariceGuildBank:AwardEP(uuid)
	SlashCmdList["ACECONSOLE_EPGP"]("ep " .. self.db.realm.transactions[uuid]["owner"] .. " \"" .. self.db.realm.settings["epReason"] .. "\" " .. self.db.realm.settings["epAwardAmount"])
	self.db.realm.transactions[uuid]["status"] = "EP Awarded"
end

function AvariceGuildBank:IgnoreTransaction(uuid)
	self.db.realm.transactions[uuid]["status"] = "Ignored"
end

function AvariceGuildBank:ValidateStringAgainstPattern(String, Pattern)
	-- Match only numbers: "^%d+$"
	-- Match dd/mm/yyyy: "^%d%d/%d%d/%d%d%d%d$"
	if string.find(String, Pattern) then
		return true
	else
		return false
	end
end

function AvariceGuildBank:PrintTransaction(copperTransacted)
	outputString = ""
	if copperTransacted < 0 then
		outputString = outputString .. "Deposited "
	else
		outputString = outputString .. "Withdrew "
	end

	-- Append formatted coin display
	outputString = outputString .. GetCoinTextureString(math.abs(copperTransacted))
	AvariceGuildBank:Print(outputString)
end

function AvariceGuildBank:ProcessTransaction()	
	local guildName, _, _, _ = GetGuildInfo("player")
	if guildName == self.db.realm.settings["guildName"] then
		if startMoney then
			local moneyDelta = GetMoney() - startMoney
			startMoney = GetMoney()
			AvariceGuildBank:PrintTransaction(moneyDelta)
			AvariceGuildBank:AddTransactionToLog(AvariceGuildBank:GenerateUUID(), (select(1, UnitName("player"))), moneyDelta, GetServerTime())
		else
			AvariceGuildBank:LogError("Called ProcessTransaction but startMoney is nil")
		end
	end
end

function AvariceGuildBank:AddTransactionToLog(UUID, Owner, Amount, Timestamp)
	self.db.realm.transactions[UUID] = {
		["owner"] = Owner,
		["amount"] = Amount,
		["timestamp"] = Timestamp,
		["status"] = "Pending"
	}
end

function AvariceGuildBank:ParseReceivedTransactionLog(transactionLog)
	-- Go through the received log, if your log doesn't contain that GUID then add it, otherwise skip to next
	for uuid, transaction in pairs(transactionLog) do
		if self.db.realm.transactions[uuid] == nil then
			self.db.realm.transactions[uuid] = transaction
		else
			-- If transaction already exists in your log, check if it has been updated
			-- and update its status if so
			-- NOTE: This can have collisions if two people do different actions without being
			--       synchronised. Since anything other than Pending means that a second action
			--		 cannot be performed on the transaction then the risk is minimal.
			if transaction["status"] ~= "Pending" then
				self.db.realm.transactions[uuid]["status"] = transaction["status"]
			end
		end
	end
end

function AvariceGuildBank:TransmitTransactionLogToPlayer(playerName)
	AvariceGuildBank:TransmitComm(messagePrefixTransactionLog, self.db.realm.transactions, "WHISPER", playerName)
end

function AvariceGuildBank:PurgeOldEntries(CutOffEpochTime)
	for uuid, transaction in pairs(self.db.realm.transactions) do
		if transaction["timestamp"] < CutOffEpochTime then
			self.db.realm.transactions[uuid] = nil
		end
	end
end

function AvariceGuildBank:BroadcastTransactionLog()
	AvariceGuildBank:TransmitComm(messagePrefixTransactionLog, self.db.realm.transactions, "GUILD")
end

function AvariceGuildBank:WhisperTransactionLog(Target)
	AvariceGuildBank:TransmitComm(messagePrefixTransactionLog, self.db.realm.transactions, "WHISPER", Target)
end

function AvariceGuildBank:SendSyncRequest()
	AvariceGuildBank:TransmitComm(messagePrefixSyncRequest, "WHISPER", "GUILD")
end

function AvariceGuildBank:BroadcastVersion()
	AvariceGuildBank:TransmitComm(messagePrefixVersion, GetAddOnMetadata("AvariceGuildBank", "version"), "GUILD")
end

function AvariceGuildBank:SendVersion(Target)
	AvariceGuildBank:TransmitComm(messagePrefixVersion, GetAddOnMetadata("AvariceGuildBank", "version"), "WHISPER", Target)
end

function AvariceGuildBank:SendVersionRequest()
	AvariceGuildBank:TransmitComm(messagePrefixVersion_Request, "NA", "GUILD")
end

function AvariceGuildBank:GenerateUUID()
	local random = math.random
	local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
	local uuid, _ = string.gsub(template, '[xy]', function (c)
		local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
		return string.format('%x', v)
	end)
	return uuid
end

function AvariceGuildBank:LogError(ErrorText, TellMalf)
	local tellMalfString = ""
	
	if TellMalf == nil or TellMalf then
		tellMalfString = " (Please tell Malf this happened)"
	end
	
	AvariceGuildBank:Print("|cffff0000ERROR|r " .. ErrorText .. tellMalfString)
end

function AvariceGuildBank:ClearDatabase(input)
	AvariceGuildBankDB = {}
	ReloadUI()
end

function AvariceGuildBank:GenerateTestData()
	for i = 1, 100 do
		local owner = tostring(math.random(100000, 5000000))
		local amount = math.random(1000, 100000)
		local timestamp = GetServerTime() - math.random(0, 1000000)
		
		AvariceGuildBank:AddTransactionToLog(AvariceGuildBank:GenerateUUID(), owner, amount, timestamp)
	end
	AvariceGuildBank:Print("Test data generated")
end

AvariceGuildBank:RegisterEvent("GUILDBANK_UPDATE_WITHDRAWMONEY")
AvariceGuildBank:RegisterEvent("GUILDBANKFRAME_OPENED")
AvariceGuildBank:RegisterEvent("GUILDBANKFRAME_CLOSED")
AvariceGuildBank:RegisterChatCommand("avaricecleardb", "ClearDatabase")
AvariceGuildBank:RegisterChatCommand("avaricereqver", "SendVersionRequest")
AvariceGuildBank:RegisterChatCommand("avaricegeneratetest", "GenerateTestData")
AvariceGuildBank:RegisterChatCommand("avaricegb", "ShowMainFrame")
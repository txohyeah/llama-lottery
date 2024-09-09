-- LlamaCoinProcessId: pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY
LlamaCoinProcessId = LlamaCoinProcessId or "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY"
LlamaCoinDenomination = 12
OneLlamaCoin = 10 ^ LlamaCoinDenomination
LlamaLotteryNpc = LlamaLotteryNpc or "uz0638BJBobQ-spyrAXPIaOcFTOLR9X1J046cP5An2w"

local json = require("json")
local crypto  = require(".crypto")
local sqlite3 = require("lsqlite3")
local dbAdmin = require("DbAdmin")
if DbAdmin == nil then
  local db = sqlite3.open_memory()
  -- Create a new dbAdmin instance
  DbAdmin = dbAdmin.new(db)
end

DrawTimestamp = DrawTimestamp or 0
StartPeriod = StartPeriod or false
LlamaCoinBalance = LlamaCoinBalance or 0
Participants = Participants or {}

--[[
    init
]]
DbAdmin:execSql([[
    CREATE TABLE IF NOT EXISTS participants (
      participant_id TEXT,
      seq_no INTEGER
    );
]])

DbAdmin:execSql([[
    CREATE TABLE IF NOT EXISTS reward_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      round INTEGER,
      total_reward INTEGER,
      participant_ids TEXT,
      winner_ids TEXT,
      created_at INTEGER
    );
]])

--[[
    tool function
]]
local function getRandomNumber(seed, len)
    local numbers = ""
    for i = 1, len or 1 do
      local n = crypto.cipher.issac.random(0, 9, tostring(i)..seed..numbers)
      numbers = numbers .. n
    end
    return numbers
end

local function rejectToken(msg)
    assert(msg.Sender ~= nil, "Missed Sender.")
    assert(msg.Quantity ~= nil and tonumber(msg.Quantity) > 0, "Missed Quantity.")
    local message = {
      Target = msg.From,
      Action = "Transfer",
      Recipient = msg.Sender,
      Quantity = msg.Quantity,
      Tags = {["X-Transfer-Purpose"] = "Reject-Bet" }
    }
    ao.send(message)
end

function SendReward(winner_id, reward)
    print(type(winner_id))
    print(type(reward))
    assert(winner_id ~= nil, "Missed winner.")
    assert(reward ~= nil and reward > 0, "Reward should be greater than 0.")
    local message = {
      Target = LlamaCoinProcessId,
      Action = "Transfer",
      Recipient = winner_id,
      Quantity = tostring(reward),
      Tags = {["X-Transfer-Purpose"] = "Win-Reward" }
    }
    ao.send(message)
    print(message)
    print("sendReward: " .. winner_id .. ", " .. reward)
end

function GetParticipantCount()
    local total = DbAdmin:count("participants")
    return total
end

local function addParticipant(participant_id, seq_no)
    local sql = string.format("INSERT INTO participants (participant_id, seq_no) VALUES ('%s', %d)", participant_id, seq_no)
    DbAdmin:execSql(sql)
end

function GetParticipants()
    local ids = DbAdmin:execQueryOne("SELECT GROUP_CONCAT(participant_id, ',') FROM participants")
    return ids or ""
end

local function formatPid(pid)
    -- 移除字符串两端的空白字符
    local pid = pid:match("^%s*(.-)%s*$")
    -- 取前三位
    local start = string.sub(pid, 1, 3)
    -- 取后三位
    local end_part = string.sub(pid, -3)
    -- 拼接
    local formatted_id = start .. "..." .. end_part
    return formatted_id
end

function GetFormattedPidFromParticipants(participant_ids) 
  -- 分割字符串
  local ids = string.gmatch(participant_ids, '[^,]+')

  -- 处理并格式化 ID
  local result = ""
  for id in ids do
    local formatted_id = formatPid(id)
    if result == "" then
      result = formatted_id
    else
      result = result .. ",\n" .. formatted_id
    end
  end
  return result
end

function GetParticipantsBySeqNo(seq_no)
    local sql = string.format("SELECT participant_id FROM participants WHERE seq_no = %d", seq_no)
    local participant_id = DbAdmin:execQueryOne(sql)
    return participant_id
end

local function clearParticipants()
    local sql = string.format("DELETE FROM participants")
    DbAdmin:execSql(sql)
end

local function addLogs(round, total_reward, participant_ids, winner_ids, created_at)
    local sql = string.format("INSERT INTO reward_logs (round, total_reward, participant_ids, winner_ids, created_at) VALUES (%d, %d, '%s', '%s', %d)", round, total_reward, participant_ids, winner_ids, created_at)
    DbAdmin:execSql(sql)
end

function GetAllHistoryParticipants()
    local results = DbAdmin:execQuery("SELECT participant_ids FROM reward_logs")
    return results
end

function GetRewardLogs(round)
    local sql = string.format("SELECT * FROM reward_logs WHERE round = %d", round)
    local results = DbAdmin:execQuery(sql)
    return results
end

function GetCurrentRound()
    local sql = string.format("SELECT MAX(round) FROM reward_logs")
    local round = DbAdmin:execQueryOne(sql)
    return round or 0
end

function ExecSql(sql)
    local results = DbAdmin.execQuery(sql)
    return results
end

local function lotteryNotice(sender, data)
    assert(sender ~= nil, "Missed sender.")
    local message = {
      Target = sender,
      Action = "Lottery-Notice",
      Data = data
    }
    ao.send(message)
end


--[[
    handlers
]]
Handlers.add("AttendGame",
  function (msg)
    if msg.From == LlamaCoinProcessId 
      and msg.Tags.Action == "Credit-Notice"
      and msg.Sender ~= LlamaCoinProcessId
      and msg.Sender ~= ao.id
    then
      return true
    else
      return false
    end
  end,
  function (msg)
    if msg.Tags["X-Transfer-Purpose"] == "sponsor"  then
        LlamaCoinBalance = LlamaCoinBalance + tonumber(msg.Quantity)
        local data = "Thanks for the sponsor from " .. msg.Sender .. ", " .. msg.Quantity .. " llama coins."
        print(data)
        lotteryNotice(msg.Sender, data)
        return
    end

    if tonumber(msg.Quantity) < 10 * OneLlamaCoin then
        rejectToken(msg)
        print(
            "Game ticket should be 10 llama coin. But you sent " 
            .. msg.Quantity / OneLlamaCoin 
            .. ", it will be transfer back to " .. msg.Sender .. "."
        )
        return
    end

    local participantCount = GetParticipantCount()
    if participantCount >= 10 then
        rejectToken(msg)
        local result = "Only 10 participants are allowed to play at the same time. Llama coins will be transfer back to " .. msg.Sender .. "."
        print(result)
        ao.send({
            Target = LlamaLotteryNpc,
            Tags = {
                Action = "DrawLotteryResult"
            },
            Data = result
        })
        return
    end

    addParticipant(msg.Sender, participantCount + 1)
    DrawTimestamp = msg.Timestamp + 1 * 60
    LlamaCoinBalance = LlamaCoinBalance + tonumber(msg.Quantity)
    lotteryNotice(msg.Sender, "You have attend lottery successfully.")
    print(msg.Sender .. " attend to lottery.")

    if participantCount >= 10 then
        StartPeriod = false
        print("It is time to draw lottery.")
    end
  end
)

Handlers.add("DrawLottery",
  function (msg)
    if msg.Tags.Action == "Cron" then
      return true
    else
      return false
    end
  end,
  function (msg)
    print("Cron DrawLottery")
    local participantCount = GetParticipantCount()
    if participantCount < 10 then
        print("Not enough participants to draw lottery.")
        return
    end

    if msg.Timestamp < DrawTimestamp then
        print("Not time to draw lottery yet.")
        return
    end
    
    local totalReward = LlamaCoinBalance * 0.9

    local luckyNumber1 = math.random(10)
    local luckyNumber2 = math.random(10)
    print("luckyNumber1:" .. luckyNumber1)
    print("luckyNumber2:" .. luckyNumber2)

    local round = GetCurrentRound() or 0
    round = round + 1
    local participantIds = GetParticipants()
    local winner_ids = ""
    if luckyNumber1 == luckyNumber2 then
        local winner = GetParticipantsBySeqNo(luckyNumber1)
        winner_ids = winner
        local reward = math.floor(totalReward)
        SendReward(winner, reward)

        addLogs(round, totalReward, participantIds, winner, msg.Timestamp)
    else
        local winner1 = GetParticipantsBySeqNo(luckyNumber1)
        local winner2 = GetParticipantsBySeqNo(luckyNumber2)
        local reward = math.floor(totalReward * 0.5)
        winner_ids = winner1 .. " and " .. winner2
        SendReward(winner1, reward)

        SendReward(winner2, reward)

        addLogs(round, totalReward, participantIds, winner1 .. "," .. winner2, msg.Timestamp)
    end
    LlamaCoinBalance = math.floor(LlamaCoinBalance - totalReward)
    SendReward(Owner, LlamaCoinBalance)

    LlamaCoinBalance = 0
    clearParticipants()

    local drawData = "Lottery round " .. round .. " is over. The winner is " .. winner_ids .. ". The reward is " .. totalReward / OneLlamaCoin .. " Llama Coins."
    local message = {
        Target = LlamaLotteryNpc,
        Tags = {
            Action = "DrawLotteryResult"
        },
        Data = drawData
    }
    
    print(message)
    ao.send(message)

    StartPeriod = true
    print("Draw lottery successfully.")
  end
)

Handlers.add("RoundInfo",
  function (msg)
    if msg.Tags.Action == "RoundInfo" then
      return true
    else
      return false
    end
  end,
  function (msg)
    local count = GetParticipantCount()
    local balance = LlamaCoinBalance
    local p_ids = GetParticipants()
    local data = {
      count = count,
      balance = balance,
      p_ids = p_ids
    }

    ao.send({
      Target = msg.From,
      Tags = {
        Action = "RespRoundInfo",
      },
      Data = json.encode(data)
    })
  end
)

Handlers.add("HistoryRoundInfo",
  function (msg)
    if msg.Tags.Action == "HistoryRoundInfo" then
      return true
    else
      return false
    end
  end,
  function (msg)
    assert(msg.Tags.Round~=nil, "missd Round tag")
    local dataMsg = "";

    local currentRound = GetCurrentRound()
    local nextRound = currentRound + 1
    if tonumber(msg.Tags.Round) > currentRound then
      -- round 比现在的大，说明没有这个轮次，返回当前的信息
      print(msg.From .. " query round info for " .. msg.Tags.Round .. ", but it is not exist. Change to query current round info.")
      local p_ids = GetParticipants()
      if p_ids == "" then
        dataMsg = "Next round is " .. nextRound .. ". No one attend lottery yet. Do you want to have a try?"
      else
        dataMsg = "Current round is " .. nextRound .. ". \n The participants is \n" .. GetFormattedPidFromParticipants(p_ids) .. "\n Good Luck!"
      end
    else
      -- 返回对应 round 的信息
      print(msg.From .. " query round info for " .. msg.Tags.Round)
      local roundInfo = GetRewardLogs(msg.Tags.Round)[1]
      dataMsg = "Lottery round " .. msg.Tags.Round .. ". The winner is " .. GetFormattedPidFromParticipants(roundInfo.winner_ids) .. ". The reward is " 
      .. roundInfo.total_reward / OneLlamaCoin .. " Llama Coins. The participants are \n" .. GetFormattedPidFromParticipants(roundInfo.participant_ids) .. "."
    end

    ao.send({
      Target = LlamaLotteryNpc,
      Tags = {
          Action = "DrawLotteryResult"
      },
      Data = dataMsg,
    })
  end
)
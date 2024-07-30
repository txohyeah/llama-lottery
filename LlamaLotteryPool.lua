-- LlamaCoinProcessId: pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY
LlamaCoinProcessId = LlamaCoinProcessId or nil
LlamaCoinDenomination = 12
OneLlamaCoin = 10 ^ LlamaCoinDenomination

local crypto  = crypto or require(".crypto")
local sqlite3 = require("lsqlite3")
local db = sqlite3.open_memory()
local json = require("json")


DrawTimestamp = DrawTimestamp or 0
StartPeriod = StartPeriod or false
LlamaCoinBalance = LlamaCoinBalance or 0
Participants = Participants or {}

--[[
    init
]]
db:exec[[
    CREATE TABLE IF NOT EXISTS participants (
      participant_id TEXT,
      seq_no INTEGER
    );
  ]]

db:exec[[
    CREATE TABLE IF NOT EXISTS reward_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      round INTEGER,
      total_reward INTEGER,
      participant_ids TEXT,
      winner_ids TEXT,
      created_at INTEGER
    );
  ]]

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
      ["X-Transfer-Purpose"] = "Reject-Bet"
    }
    ao.send(message)
end

local function sendReward(winner_id, reward)
    assert(winner_id ~= nil, "Missed winner.")
    assert(reward ~= nil and reward > 0, "Reward should be greater than 0.")
    local message = {
      Target = LlamaCoinProcessId,
      Action = "Transfer",
      Recipient = winner_id,
      Quantity = tostring(reward),
      ["X-Transfer-Purpose"] = "Win-Reward"
    }
    ao.send(message)
    print("sendReward: " .. winner_id .. ", " .. reward)
end

function getParticipantCount()
    local sql = string.format("SELECT COUNT(1) FROM participants")
    local stmt = db:prepare(sql)
    stmt:step()
    local total = stmt:get_value(0)
    stmt:finalize()
    return total
end

local function addParticipant(participant_id, seq_no)
    local sql = string.format("INSERT INTO participants (participant_id, seq_no) VALUES ('%s', %d)", participant_id, seq_no)
    db:exec(sql)
end

function getParticipants()
    local sql = string.format("SELECT GROUP_CONCAT(participant_id, ',') FROM participants")
    local stmt = db:prepare(sql)
    stmt:step()
    local ids = stmt:get_value(0)
    stmt:finalize()
    return ids
end

function getParticipantsBySeqNo(seq_no)
    local sql = string.format("SELECT participant_id FROM participants WHERE seq_no = %d", seq_no)
    local stmt = db:prepare(sql)
    stmt:step()
    local participant_id = stmt:get_value(0)
    stmt:finalize()
    return participant_id
end

local function clearParticipants()
    local sql = string.format("DELETE FROM participants")
    db:exec(sql)
end

local function addLogs(round, total_reward, participant_ids, winner_ids, created_at)
    local sql = string.format("INSERT INTO reward_logs (round, total_reward, participant_ids, winner_ids, created_at) VALUES (%d, %d, '%s', '%s', %d)", round, total_reward, participant_ids, winner_ids, created_at)
    db:exec(sql)
end

function getRewardLogs(round)
    local results = {}
    local sql = string.format("SELECT * FROM reward_logs WHERE round = %d", round)
    for row in db:nrows(sql) do
        table.insert(results, row)
    end
    return results
end

function getCurrentRound()
    local sql = string.format("SELECT MAX(round) FROM reward_logs")
    local stmt = db:prepare(sql)
    stmt:step()
    local round = stmt:get_value(0)
    stmt:finalize()
    return round
end

function execSql(sql)
    local results = {}
    for row in db:nrows(sql) do
        table.insert(results, row)
    end
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

    if tonumber(msg.Quantity) ~= OneLlamaCoin then
        rejectToken(msg)
        print(
            "Game ticket should be 1 llama coin. But you sent " 
            .. msg.Quantity 
            .. ", it will be transfer back to " .. msg.Sender .. "."
        )
        return
    end

    local participantCount = getParticipantCount()
    if participantCount >= 10 then
        rejectToken(msg)
        print("Only 10 participants are allowed to play at the same time. Llama coins will be transfer back to " .. msg.Sender .. ".")
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
    local participantCount = getParticipantCount()
    if participantCount < 10 then
        print("Not enough participants to draw lottery.")
        return
    end

    if msg.Timestamp < DrawTimestamp then
        print("Not time to draw lottery yet.")
        return
    end
    
    local totalReward = 0
    if LlamaCoinBalance > 13 * OneLlamaCoin then
        totalReward = LlamaCoinBalance * 0.8
    else
        totalReward = LlamaCoinBalance
    end

    local luckyNumber1 = getRandomNumber(msg.Timestamp, 1)
    local luckyNumber2 = getRandomNumber(msg.Timestamp .. luckyNumber1, 1)
    print("luckyNumber1:" .. luckyNumber1)
    print("luckyNumber2:" .. luckyNumber2)

    local round = getCurrentRound() or 0
    round = round + 1
    local participantIds = getParticipants()
    if luckyNumber1 == luckyNumber2 then
        local winner = getParticipantsBySeqNo(luckyNumber1 + 1)
        local reward = totalReward
        sendReward(winner, reward)
        addLogs(round, totalReward, participantIds, winner, msg.Timestamp)
    else
        local winner1 = getParticipantsBySeqNo(luckyNumber1 + 1)
        local winner2 = getParticipantsBySeqNo(luckyNumber2 + 1)
        local reward = math.floor(totalReward * 0.5)
        sendReward(winner1, reward)
        sendReward(winner2, reward)
        addLogs(round, totalReward, participantIds, winner1 .. "," .. winner2, msg.Timestamp)
    end
    LlamaCoinBalance = LlamaCoinBalance - totalReward
    clearParticipants()

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
    local count = getParticipantCount()
    local balance = LlamaCoinBalance
    local p_ids = getParticipants()
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
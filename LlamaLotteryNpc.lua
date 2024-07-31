TARGET_WORLD_PID = TARGET_WORLD_PID or "9a_YP6M7iN7b6QUoSvpoV3oe3CqxosyuJnraCucy5ss"
LlamaCoinProcessId = LlamaCoinProcessId or "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY"
POOL = POOL or 'CWmP2C0iAZyFjfdkSZU2nl4kWEDfMIcIn5ESS_2ptw4'
HasReg = HasReg or false

LlamaCoinDenomination = 12
OneLlamaCoin = 10 ^ LlamaCoinDenomination
RecivceMsgTimes = RecivceMsgTimes or 0
LastPaticipantCount = LastPaticipantCount or 0

local json = require("json")

if HasReg == false then
    Register()
end

function Register()
    ao.send({
      Target = TARGET_WORLD_PID,
      Tags = {
        Action = "Reality.EntityCreate",
      },
      Data = json.encode({
        Type = "Avatar",
        Metadata = {
          DisplayName = "Llama lottery",
          SkinNumber = 1,
          Interaction = {
              Type = 'SchemaExternalForm',
              Id = 'Lottery'
          },
        },
      }),
    })

end


function Move()
    ao.send({
      Target = TARGET_WORLD_PID,
      Tags = {
        Action = "Reality.EntityUpdatePosition",
      },
      Data = json.encode({
        Position = {
          math.random(-3, 3),
          math.random(12, 15),
        },
      }),
    })
end

function QueryRoundInfo()
    ao.send({
        Target = POOL,
        Tags = {
            Action = "RoundInfo",
        }
    })
end


function LlamaLotteryAttendSchemaTags()
    return [[
        {
            "type": "object",
            "required": [
                "Action",
                "Recipient",
                "Quantity",
                "X-Transfer-Purpose"
            ],
            "properties": {
                "Action": {
                    "type": "string",
                    "const": "Transfer"
                },
                "Recipient": {
                    "type": "string",
                    "const": "]] .. POOL .. [["
                },
                "Quantity": {
                    "type": "number",
                    "const": ]] .. 1 .. [[,
                    "$comment": "]] .. 1000000000000 .. [["
                },
                "X-Transfer-Purpose":  {
                    "type": "string",
                    "const": "Lottery"
                },
            }
        }
    ]]
end


function ChatToWorld(data)
  ao.send({
    Target = TARGET_WORLD_PID,
    Tags = {
      Action = 'ChatMessage',
      ['Author-Name'] = 'Llama Lottery',
    },
    Data = data
  })
end


Handlers.add(
  'SchemaExternal',
  Handlers.utils.hasMatchingTag('Action', 'SchemaExternal'),
  function(msg)
    ao.send({
        Target = msg.From,
        Tags = { Type = 'SchemaExternal' },
        Data = json.encode({
          Lottery = {
            Target = LlamaCoinProcessId,
            Title = "Attend Llama Lottery?",
            Description = [[
              Pay 1 Llama Coin to enter the Llama Lottery. The winner will share 80% of the prize pool in Llama Coins.
              The winner will be determined when there are 10 participants.
              ]],
            Schema = {
              Tags = json.decode(LlamaLotteryAttendSchemaTags()),
            },
          },
        })
      })
  end
)


Handlers.add(
  "CronTick",
  Handlers.utils.hasMatchingTag("Action", "Cron"),
  function()
    QueryRoundInfo()
    Move()
  end
)

Handlers.add(
    "ShowLottery",
    function (msg)
        if msg.Tags.Action == "RespRoundInfo" and msg.From == POOL then
          return true
        else
          return false
        end
    end,
    function (msg)
        local lotteryInfo = json.decode(msg.Data)
        if lotteryInfo.count <= 0 then
            return
        end

        local balance = lotteryInfo.balance / OneLlamaCoin
        if lotteryInfo.count < 10 then
            if RecivceMsgTimes > 5 or LastPaticipantCount ~= lotteryInfo.count then
              local data = lotteryInfo.count .. " players participated in this round. If there are 10 participants, I will share " 
                .. balance .. " Llama Coins to the winners."
              ChatToWorld(data)
              RecivceMsgTimes = 0
            else
              RecivceMsgTimes = RecivceMsgTimes + 1
              print("RecivceMsgTimes: " .. RecivceMsgTimes)
            end
            return
        end

        if lotteryInfo.count >= 10 then
            ao.send({
                Target = TARGET_WORLD_PID,
                Tags = {
                  Action = 'ChatMessage',
                  ['Author-Name'] = 'Llama Lottery',
                },
                Data = "There are 10 participants. I will share " .. balance .. " Llama Coins to the winners soon.",
            })
        end
        
    end
)

Handlers.add(
    "ShowLotteryResult",
    function (msg)
        if msg.Tags.Action == "DrawLotteryResult" and msg.From == POOL then
          return true
        else
          return false
        end
    end,
    function (msg)
        print("Show lottery result")
        ao.send({
            Target = TARGET_WORLD_PID,
            Tags = {
                Action = 'ChatMessage',
                ['Author-Name'] = 'Llama Lottery',
            },
            Data = msg.Data,
        })
        
    end
)
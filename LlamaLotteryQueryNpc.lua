-- llama land
TARGET_WORLD_PID = TARGET_WORLD_PID or "9a_YP6M7iN7b6QUoSvpoV3oe3CqxosyuJnraCucy5ss"
-- test world
-- TARGET_WORLD_PID = TARGET_WORLD_PID or "79RqpVCa42GZH_jrGcHsCofmZNJN990bV7B7-mWa4bA"
LlamaCoinProcessId = LlamaCoinProcessId or "pazXumQI-HPH7iFGfTC-4_7biSnqz_U67oFAGry5zUY"
POOL = POOL or 'o0VhLDH4P-Acs_Jp2xE5cLonOHbJhbk6yjraHdhxx8M'
HasReg = HasReg or false

LlamaCoinDenomination = 12
OneLlamaCoin = 10 ^ LlamaCoinDenomination
RecivceMsgTimes = RecivceMsgTimes or 0
LastPaticipantCount = LastPaticipantCount or 0

MIN_ROUND_VALUE = 1

local json = require("json")

function Register()
    ao.send({
      Target = TARGET_WORLD_PID,
      Tags = {
        Action = "Reality.EntityCreate",
      },
      Data = json.encode({
        Type = "Avatar",
        Metadata = {
          DisplayName = "Lottery Assistant",
          SkinNumber = 8,
          Interaction = {
              Type = 'SchemaExternalForm',
              Id = 'QueryLottery'
          },
        },
      }),
    })
end

if HasReg == false then
  Register()
  HasReg = true
end

function Move()
  local x = math.random(-3, 3)
  local y = math.random(14, 15)
  -- local x = math.random(50, 55)
  -- local y = math.random(50, 55)
  
  ao.send({
    Target = TARGET_WORLD_PID,
    Tags = {
      Action = "Reality.EntityUpdatePosition",
    },
    Data = json.encode({
      Position = {
        x,
        y,
      },
    }),
  })

  local re_msg = Receive({From = TARGET_WORLD_PID})

  if re_msg.Result ~= 'OK' then
    print("move failed")
  else
    print(re_msg.Data)
  end
end

function LlamaLotteryQuerySchemaTags()
    return [[
        {
            "type": "object",
            "required": [
                "Action",
                "Round",
            ],
            "properties": {
                "Action": {
                    "type": "string",
                    "const": "HistoryRoundInfo",
                },
                "Round": {
                    "type": "number",
                    "default": ]] .. MIN_ROUND_VALUE .. [[,
                    "minimum": ]] .. MIN_ROUND_VALUE .. [[,
                    "title": "Which round do you want to query?",
                }
            }
        }
    ]]
end


function ChatToWorld(data)
  ao.send({
    Target = TARGET_WORLD_PID,
    Tags = {
      Action = 'ChatMessage',
      ['Author-Name'] = 'Lottery Assistant',
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
          QueryLottery = {
            Target = POOL,
            Title = "Lottery History ?",
            Description = [[
              Input round number to see the lottery history.
            ]],
            Schema = {
              Tags = json.decode(LlamaLotteryQuerySchemaTags()),
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
    Move()
  end
)

Handlers.add(
    "ShowAssistantMsg",
    function (msg)
        if msg.Tags.Action == "AssistantMsg" and msg.From == POOL then
          return true
        else
          return false
        end
    end,
    function (msg)
        print("Show Assistant Message")
        ao.send({
            Target = TARGET_WORLD_PID,
            Tags = {
                Action = 'ChatMessage',
                ['Author-Name'] = 'Llama Assistant',
            },
            Data = msg.Data,
        })
        
    end
)
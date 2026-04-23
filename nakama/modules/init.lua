local nk = require("nakama")

-- Register Static Data (forces parsing on boot)
local StaticData = require("core.static_data")

-- Require Modules
local PlayerData = require("core.player_data")
local Units = require("features.units")
local Parties = require("features.parties")
local ClientData = require("features.client_data")
local Combat = require("features.combat")
local Inventory = require("features.inventory")
local Economy = require("features.economy")

-- Register RPC Endpoints
nk.register_rpc(ClientData.get_data_version, "get_data_version")
nk.register_rpc(ClientData.get_game_data, "get_game_data")
nk.register_rpc(ClientData.get_dungeon_missions, "get_dungeon_missions")
nk.register_rpc(ClientData.get_mission_progress, "get_mission_progress")

nk.register_rpc(Units.get_player_units_rpc, "get_player_units")
nk.register_rpc(Units.summon_units, "summon_units")
nk.register_rpc(Units.add_unit_xp, "add_unit_xp")
nk.register_rpc(Units.awaken_unit, "awaken_unit")

nk.register_rpc(Inventory.get_player_items_rpc, "get_player_items")
nk.register_rpc(Inventory.add_item, "add_item")
nk.register_rpc(Inventory.rpc_equip_item, "equip_item")

nk.register_rpc(Economy.add_currency, "add_currency")
nk.register_rpc(Economy.buy_item, "buy_item")

nk.register_rpc(PlayerData.get_player_stats, "get_player_stats")
nk.register_rpc(PlayerData.add_rank_xp, "add_rank_xp")

nk.register_rpc(Combat.start_mission, "start_mission")
nk.register_rpc(Combat.finish_mission, "finish_mission")

nk.register_rpc(Parties.rpc_get_parties, "get_parties")
nk.register_rpc(Parties.rpc_save_parties, "save_parties")

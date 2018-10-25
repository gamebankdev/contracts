
-- 合约初始化
function on_deploy()
	local all_data = contract.get_data()
	all_data.created_table_count = 0
	all_data.finish_table_count = 0
	all_data.unfinish_table_count = 0
	all_data.is_active = false
	all_data.tables = {}
	all_data.table_creators = {}
	--all_data.players_in_table = {} K=player V=table_id
	print("on_deploy")
	contract.emit("deploy", chain.head_block_num(), contract.get_caller() )
end

function add_table_creator(table_creator)
	if(contract.get_creator() ~= contract.get_caller())then
		error("only contract creator can add table_creator")
	end
	if(not chain.is_account(table_creator) )then
		error("error table_creator not a account")
	end
	local all_data = contract.get_data()
	all_data.table_creators[table_creator] = 1
	contract.emit("add_table_creator", table_creator )
end

function remove_table_creator(table_creator)
	if(contract.get_creator() ~= contract.get_caller())then
		error("only contract creator can remove table_creator")
	end
	if(not chain.is_account(table_creator) )then
		error("error table_creator not a account")
	end
	local all_data = contract.get_data()
	all_data.table_creators[table_creator] = nil
	contract.emit("remove_table_creator", table_creator )
end

-- 玩家数据
local function get_user_data(user_name)
	local user_data = contract.get_user_data(user_name)
	if(user_data.balance == nil )then
		user_data.balance = 0
		user_data.table_id = 0
	end
	return user_data
end

-- 充值兑换成筹码(1:1)
function recharge(amount)
	-- todo:检查amount的值范围
	if(amount < 1)then
		error("error amount value")
	end
	local user_data = get_user_data(contract.get_caller())
	contract.transfer(contract.get_caller(), contract.get_name(), amount)
	user_data.balance = user_data.balance + amount
	contract.emit("recharge", {contract.get_caller(), amount, user_data.balance})
	return tostring(user_data.balance)
end

function get_balance(user_name)
	local user_data = get_user_data(user_name)
	return tostring(user_data.balance)
end

-- 提款:筹码兑换成GB(1:1)
function withdraw(amount)
	if(amount < 1)then
		error("error amount value")
	end
	local user_data = get_user_data(contract.get_caller())
	if(user_data.balance < amount)then
		error("not enough balance")
	end
	user_data.balance = user_data.balance - amount
	contract.transfer(contract.get_name(), contract.get_caller(), amount)
	contract.emit("withdraw", {contract.get_caller(), amount, user_data.balance})
end

--[[
	创建桌子
	table_id: todo:检查值范围
	table_option_jsonstr:
		{
			"min_deposit_fee":100, 	-- 押金要求
			"min_balance":10000,	-- 余额要求
			"min_bet_amount":10,	-- 底注
			"inc_bet_amount":10,	-- 单次加注限制
			-- 加注上限?
		}
	players_jsonstr:
		[
			player_nameA,
			player_nameB,
			player_nameC
		]
]]--
function table_create(table_id, table_option_jsonstr, players_jsonstr)
	--[[
	if(table_id < 1)then
		error("error table_id value")
	end]]--
	if(string.len(table_id) < 1)then
		error("error table_id value")
	end
	local all_data = contract.get_data()
	if(all_data.table_creators[contract.get_caller()] == nil)then
		error("not have right to create table")
	end
	local table_option = contract.jsonstr_to_table(table_option_jsonstr)
	local players = contract.jsonstr_to_table(players_jsonstr)
	for i,player_name in ipairs(players) do
		local user_data = get_user_data(player_name)
		if(user_data.balance < table_option.min_deposit_fee + table_option.min_balance)then
			error("player not have enougn balance")
		end
		for j=i+1,#players do
			if(players[i] == players[j])then
				error("duplicate player")
			end
		end
	end
	if(all_data.tables[table_id] ~= nil)then
		error("duplicate table_id")
	end
	local new_table = { table_id = table_id, table_option = table_option, creator = contract.get_caller(), create_time = chain.head_block_num(),
						players = {}, shuffle_decks = {}, bet_pool=0 }
	for i,player_name in ipairs(players) do
		table.insert(new_table.players, {player_name=player_name,is_joined=false})
	end
	all_data.tables[table_id] = new_table
	all_data.created_table_count = all_data.created_table_count + 1
	-- todo:player增加一个状态值,防止一个player同时参加多个牌桌
	-- table增加超时设置,防止游戏服务器停止运行,导致player卡在该状态?
	contract.emit("table_create", {contract.get_caller(), table_id, table_option_jsonstr, players_jsonstr} ) -- jsonstr是否能正确保存???
end

-- 玩家加入牌桌
function table_join(table_id)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	for i,player_data in ipairs(table_data.players) do
		if(player_data.player_name == contract.get_caller())then
			if(not player_data.is_joined)then
				player_data.is_joined = true
				contract.emit("table_join", {contract.get_caller(), table_id})
			end
			return
		end
	end
	error("not find player in this table")
end

local function is_in_table(player_name, table_data)
	for i,player_data in ipairs(table_data.players) do
		if(player_data.player_name == player_name)then
			return true
		end
	end
	return false
end

local function get_player_index(player_name, table_data)
	for i,player_data in ipairs(table_data.players) do
		if(player_data.player_name == player_name)then
			return i
		end
	end
	return nil
end

--[[
	洗牌数据
	encrypted_deck_jsonstr:
	[
		Card1_base58,
		...
		Card52_base58
	]
	pubkeys_jsonstr:
	[
		[pub1_A, pub2_A, pub52_A]
		[pub1_B, pub2_B, pub52_B]
		...
	]
	该接口必须由table.creator调用
]]--
function shuffer_cards(table_id, encrypted_deck_jsonstr, pubkeys_jsonstr)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	if(all_data.table_creators[contract.get_caller()] == nil)then
		error("not have right to shuffer_cards")
	end
	local encrypted_deck = contract.jsonstr_to_table(encrypted_deck_jsonstr)
	if(#encrypted_deck ~= 52)then
		error("error encrypted_deck_jsonstr")
	end
	local player_pubkeys = contract.jsonstr_to_table(pubkeys_jsonstr)
	if(#player_pubkeys ~= #table_data.players)then
		error("error player_num")
	end
	for i,pubkeys in ipairs(player_pubkeys) do
		if(#pubkeys ~= 52)then
			error("error pubkeys")
		end
	end
	contract.emit("shuffer_cards", {contract.get_caller(), table_id, encrypted_deck_jsonstr, pubkeys_jsonstr})
end

-- 扣筹码
function pay(table_id, amount, reason)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	local player_index = get_player_index(contract.get_caller(), table_data)
	if( player_index == nil )then
		error("error table_id")
	end
	-- todo:检查上限
	local user_data = get_user_data(contract.get_caller())
	if(user_data.balance < amount)then
		error("not enough balance")
	end
	user_data.balance = user_data.balance - amount
	table_data.bet_pool = table_data.bet_pool + amount
	contract.emit("pay", {contract.get_caller(), table_id, amount, reason} )
	return user_data.balance
end

--[[
  游戏过程数据
  ops_jsonstr:
  [
	{"type":optype,"index":index,"args":"...","time":time}
	...
  ]
  该接口必须由table.creator调用
]]--
function game_result(table_id, ops_jsonstr, winner_index )
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	local ops = contract.jsonstr_to_table(ops_jsonstr)
	contract.transfer(contract.get_name(), table_data.players[winner_index].player_name, table_data.bet_pool)
	table_data.bet_pool = 0
	contract.emit("game_result", {contract.get_caller(), table_id, ops_jsonstr, winner_index} )
end

-- only for test
function testcommand(cmd, arg)
	print("testcommand cmd="..cmd.." arg="..arg)
	if(cmd == "test")then
		--add_table_creator("fish")
		--recharge(100000)
		local table_id = "1"
		table_create(table_id, "{\"min_deposit_fee\":100,\"min_balance\":10000,\"min_bet_amount\":10,\"inc_bet_amount\":10}", "[\"playerA\",\"playerB\",\"playerC\"]")
		--table_join(table_id)
		--[[
		local encrypted_deck_jsonstr = "["
		for i=1,52 do
			encrypted_deck_jsonstr = encrypted_deck_jsonstr.."\"card"..i.."_base58_"..contract.get_caller().."\""
			if(i < 52)then
				encrypted_deck_jsonstr = encrypted_deck_jsonstr..","
			end
		end
		encrypted_deck_jsonstr = encrypted_deck_jsonstr.."]"
		shuffle_deck(table_id, encrypted_deck_jsonstr)]]--
		
		--[[
		local encrypted_deck_jsonstr = "["
		local pubkeys_jsonstr = "["
		for i=1,52 do
			encrypted_deck_jsonstr = encrypted_deck_jsonstr.."\"enccard"..i.."_base58_"..contract.get_caller().."\""
			pubkeys_jsonstr = pubkeys_jsonstr.."\"pub"..i.."_base58_"..contract.get_caller().."\""
			if(i < 52)then
				encrypted_deck_jsonstr = encrypted_deck_jsonstr..","
				pubkeys_jsonstr = pubkeys_jsonstr..","
			end
		end
		encrypted_deck_jsonstr = encrypted_deck_jsonstr.."]"
		pubkeys_jsonstr = pubkeys_jsonstr.."]"
		encrypt_cards(table_id, encrypted_deck_jsonstr, pubkeys_jsonstr)]]--
		
		--deal(table_id)
		
		--[[
		local prikeys_jsonstr = "["
		prikeys_jsonstr = prikeys_jsonstr.."[],"
		prikeys_jsonstr = prikeys_jsonstr.."[\"prikey1_BA\",\"prikey2_BA\",\"prikey3_BA\"],"
		prikeys_jsonstr = prikeys_jsonstr.."[\"prikey1_CA\",\"prikey2_CA\",\"prikey3_CA\"]"
		prikeys_jsonstr = prikeys_jsonstr.."]"
		set_faceup(table_id, 1, prikeys_jsonstr)]]--
		
		--bet_continue(table_id, 10)
		
		--[[
		local prikeys_jsonstr = "["
		prikeys_jsonstr = prikeys_jsonstr.."[],"
		prikeys_jsonstr = prikeys_jsonstr.."[\"prikey1_AB\",\"prikey2_AB\",\"prikey3_AB\"],"
		prikeys_jsonstr = prikeys_jsonstr.."[\"prikey1_AC\",\"prikey2_AC\",\"prikey3_AC\"]"
		prikeys_jsonstr = prikeys_jsonstr.."]"
		bet_giveup(table_id,prikeys_jsonstr)]]--
		
		--bet_open(table_id)
		
		--[[
		local prikeys_jsonstr = "["
		prikeys_jsonstr = prikeys_jsonstr.."[\"prikey1_BB\",\"prikey2_BB\",\"prikey3_BB\"],"
		prikeys_jsonstr = prikeys_jsonstr.."[\"prikey1_BC\",\"prikey2_BC\",\"prikey3_BC\"],"
		prikeys_jsonstr = prikeys_jsonstr.."[\"prikey1_CC\",\"prikey2_CC\",\"prikey3_CC\"],"
		prikeys_jsonstr = prikeys_jsonstr.."[\"prikey1_CB\",\"prikey2_CB\",\"prikey3_CB\"]"
		prikeys_jsonstr = prikeys_jsonstr.."]"
		set_open_result(table_id, 2, 3, 2, prikeys_jsonstr)]]--
		
	end
end


--[[
	todo:各种异常情况的处理
]]--

--[[
游戏流程:
	A,B,C支付押金,进行匹配pay_deposit
	匹配成功,进入一桌table_create
	轮流洗牌,加密牌数据finish_shuffle
	
	游戏开始,每人发3张牌(加密数据)
	A看自己手牌,B,C把A1-3的加密因子发给A
	B看自己手牌,A,C把B1-3的加密因子发给B
	C看自己手牌,A,B把C1-3的加密因子发给C
	
	Round1:
	A跟牌,支付跟牌费
	B弃牌,把自己的除手牌外的所有私钥发给剩下的player A,C
	C跟牌,支付跟牌费
	
	Round2:
	A跟牌,支付跟牌费
	C开牌,支付开牌费,C把C1-3的加密因子发给A,A把A1-3的加密因子发给C
	A,C的手牌都公开了,比较大小,游戏结算
	table_finish(args)
	
合约:
	A支付押金 pay_deposit(A)
	B支付押金 pay_deposit(B)
	C支付押金 pay_deposit(C)
	
	creator创建牌桌table_create(table_id,A,B,C),把A,B,C匹配到一桌
	A加入牌桌 join_table(A,table_id)
	B加入牌桌 join_table(B,table_id)
	C加入牌桌 join_table(C,table_id)
	A洗牌shuffle_deck(deckA)
	B洗牌shuffle_deck(deckAB)
	C洗牌shuffle_deck(deckABC)
	A换因子shuffle_deck(deckABC,pubkeysA)
	B换因子shuffle_deck(deckABC,pubkeysB)
	C换因子shuffle_deck(deckABC,pubkeysC)
	creator给A,B,C各发3张牌A1,A2,A3 B1,B2,B3 C1,C2,C3
	B把A1,A2,A3的加密因子发给A (A看自己手牌)
	C把A1,A2,A3的加密因子发给A (A看自己手牌)
	A把B1,B2,B3的加密因子发给B (B看自己手牌)
	C把B1,B2,B3的加密因子发给B (B看自己手牌)
	A把C1,C2,C3的加密因子发给C (C看自己手牌)
	B把C1,C2,C3的加密因子发给C (C看自己手牌)
	
	(Round1)A跟牌,支付跟牌费follow(A)
	
	(Round1)B弃牌,把自己的除自己手牌外的私钥公开 give_key_pass(B,prikeysB)
	
	(Round1)C跟牌,支付跟牌费follow(C)
	
	(Round2)A跟牌,支付跟牌费follow(A)
	
	(Round2)C开牌,支付开牌费,把C1,C2,C3的私钥公开 pay_open_cards(C,prikeysC)
	
	(Round2)A把A1,A2,A3的私钥公开 open_cards(A,prikeysA)
	
	creator可以看到A,C的牌了,比较大小,游戏结算,钱给赢家 table_result(winner,cardsA,cardsC)
	
]]--

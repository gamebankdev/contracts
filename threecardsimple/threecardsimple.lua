
-- 合约初始化
function on_deploy()
	local all_data = contract.get_data()
	all_data.created_table_count = 0
	all_data.finish_table_count = 0
	all_data.unfinish_table_count = 0
	all_data.last_table_id = 0
	all_data.is_active = true
	all_data.tables = {} -- 正在进行中的牌桌
	all_data.table_creators = {}
	print("on_deploy")
	contract.emit("deploy", {chain.head_block_num(), contract.get_caller()} )
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
	contract.emit("add_table_creator", {table_creator} )
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
	contract.emit("remove_table_creator", {table_creator} )
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
		error("error amount value:"..amount)
	end
	local user_data = get_user_data(contract.get_caller())
	contract.transfer(contract.get_caller(), contract.get_name(), amount)
	user_data.balance = user_data.balance + amount
	contract.emit("recharge", {contract.get_caller(), amount, user_data.balance})
	return tostring(user_data.balance)
end

-- 获取用户筹码余额
function get_balance(user_name)
	local user_data = get_user_data(user_name)
	return tostring(user_data.balance)
end

-- 提款:筹码兑换成GB(1:1)
function withdraw(amount)
	if(amount < 1)then
		error("error amount value:"..amount)
	end
	local user_data = get_user_data(contract.get_caller())
	if(user_data.balance < amount)then
		error("not enough balance:"..contract.get_caller().." balance:"..user_data.balance.." amount:"..amount)
	end
	user_data.balance = user_data.balance - amount
	contract.transfer(contract.get_name(), contract.get_caller(), amount)
	contract.emit("withdraw", {contract.get_caller(), amount, user_data.balance})
	return tostring(user_data.balance)
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
	local all_data = contract.get_data()
	local int_table_id = math.tointeger(table_id)
	if(int_table_id <= all_data.last_table_id)then
		error("error table_id value:"..table_id)
	end
	
	if(all_data.table_creators[contract.get_caller()] == nil)then
		error("not have right to create table")
	end
	local table_option = contract.jsonstr_to_table(table_option_jsonstr)
	local players = contract.jsonstr_to_table(players_jsonstr)
	for i,player_name in ipairs(players) do
		local user_data = get_user_data(player_name)
		if(user_data.balance < table_option.min_deposit_fee + table_option.min_balance)then
			error("player not have enougn balance:"..player_name.." "..user_data.balance.." "..table_option.min_deposit_fee.." "..table_option.min_balance)
		end
		for j=i+1,#players do
			if(players[i] == players[j])then
				error("duplicate player")
			end
		end
	end
	if(all_data.tables[table_id] ~= nil)then
		error("duplicate table_id:"..table_id)
	end
	local new_table = { table_id = table_id, table_option = table_option, creator = contract.get_caller(), create_time = chain.head_block_num(),
						players = {}, shuffle_decks = {}, bet_pool=0 }
	for i,player_name in ipairs(players) do
		table.insert(new_table.players, {player_name=player_name,is_joined=false})
	end
	all_data.tables[table_id] = new_table
	all_data.last_table_id = int_table_id
	all_data.created_table_count = all_data.created_table_count + 1
	-- todo:player增加一个状态值,防止一个player同时参加多个牌桌
	-- table增加超时设置,防止游戏服务器停止运行,导致player卡在该状态?
	-- todo: players分成多列写日志,便于浏览器通过username查找对战记录
	contract.emit("table_create", {contract.get_caller(), table_id, table_option, players} )
end

-- 玩家加入牌桌
function table_join(table_id)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id:"..table_id)
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
	error("not find player in this table:"..table_id.." "..contract.get_caller())
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
		error("error table_id:"..table_id)
	end
	if(table_data.creator ~= contract.get_caller())then
		error("only table creator can do this method")
	end
	local encrypted_deck = contract.jsonstr_to_table(encrypted_deck_jsonstr)
	if(#encrypted_deck ~= 52)then
		error("error encrypted_deck_jsonstr:"..#encrypted_deck)
	end
	local player_pubkeys = contract.jsonstr_to_table(pubkeys_jsonstr)
	if(#player_pubkeys ~= #table_data.players)then
		error("error player_num:"..#player_pubkeys)
	end
	for i,pubkeys in ipairs(player_pubkeys) do
		if(#pubkeys ~= 52)then
			error("error pubkeys:"..#pubkeys)
		end
	end
	contract.emit("shuffer_cards", {contract.get_caller(), table_id, encrypted_deck, player_pubkeys})
end

--[[
	扣筹码
	reason: 0:底注 1:跟注 2:开牌
]]--
function pay(table_id, amount, reason)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id:"..table_id)
	end
	local player_index = get_player_index(contract.get_caller(), table_data)
	if( player_index == nil )then
		error("you are not in this table:"..table_id.." "..contract.get_caller())
	end
	-- todo:检查上限
	local user_data = get_user_data(contract.get_caller())
	if(user_data.balance < amount)then
		error("not enough balance:"..contract.get_caller().." balance:"..user_data.balance.." amount:"..amount)
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
	{"type":optype,"args":"...","time":time}
	...
  ]
  该接口必须由table.creator调用
  准备 num:底注金额
	type:"ready",name:user_name,args:{num:num}
  发初始牌
	type:"draw",name:user_name,args:{[cardindex1,cardindex2,cardindex3]}
  看自己手牌
	type:"watch",name:user_name,args:{
	}
  跟注 num:跟注金额
	type:"stake",name:user_name,args:{num:num}
  弃牌
	type:"pass",name:user_name,args:{}
  开牌
	type:"open",name:user_name,args:{
		target:whoseCard,
		winner:whoWin,
		cost:pay
	}
  游戏结果
	type:"result",name:winner_name,args:
	{
		winner:winner_name,
		money:win_money,
		cards:
		[
			{
				name:whoseCard,
				cards:
				[
					{
						index:card_index,
						keys:
						[
							{
								name:key_owner,
								key:prikey
							}
						]
					},
					...other two cards...
				]
			},
			...other users...
		]
	}
]]--
function game_result(table_id, ops_jsonstr, winner_name )
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id:"..table_id)
	end
	if(table_data.creator ~= contract.get_caller())then
		error("only table creator can do this method")
	end
	local ops = contract.jsonstr_to_table(ops_jsonstr)
	-- todo:合约收取一定的手续费
	local winner_index = get_player_index(winner_name, table_data)
	if(winner_index == nil)then
		error("error winner_name:"..table_id.." winner_name:"..winner_name)
	end
	local user_data = get_user_data(winner_name)
	user_data.balance = user_data.balance + table_data.bet_pool
	table_data.bet_pool = 0
	all_data.finish_table_count = all_data.finish_table_count + 1
	all_data.tables[table_id] = nil
	contract.emit("game_result", {contract.get_caller(), table_id, ops, winner_name} )
	return user_data.balance
end

--[[
  牌桌非正常结束(玩家掉线或恶意退出)
  args_jsonstr:
  [
  ]
  reason:
	玩家人数不齐 退还底注
	玩家掉线或恶意退出 退还每个玩家押的钱 剩下的钱平分
	玩家操作超时 退还每个玩家押的钱 剩下的钱平分
  该接口必须由table.creator调用
]]--
function game_abort(table_id, args_jsonstr, reason )
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id:"..table_id)
	end
	if(table_data.creator ~= contract.get_caller())then
		error("only table creator can do this method")
	end
end

-- only for test
function testcommand(cmd, arg)
	print("testcommand cmd="..cmd.." arg="..arg)
	if(cmd == "test")then
		--add_table_creator("fish")
		--recharge(100000)
		--local table_id = "1"
		--table_create(table_id, "{\"min_deposit_fee\":100,\"min_balance\":10000,\"min_bet_amount\":10,\"inc_bet_amount\":10}", "[\"playerA\",\"playerB\",\"playerC\"]")
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
	
合约:
	
]]--

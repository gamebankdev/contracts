
-- 配置
local Options =
{
	TableConfigs =
	{
		[1] = {deposit_fee=1000 }
	}
}

local EState = 
{
	Join = 0,			-- 加入牌桌
	Shuffle = 1,		-- 顺序洗牌
	EncryptCards = 2,	-- 给每张牌加密
	Deal = 3,			-- 发牌
	Playing = 4,		-- 打牌过程
	WaitResult = 5,		-- 等待结算结果
	End  = 6,
}

-- 合约初始化
function on_deploy()
	local all_data = contract.get_data()
	all_data.created_table_count = 0
	all_data.finish_table_count = 0
	all_data.unfinish_table_count = 0
	all_data.is_active = false
	all_data.deposit_map = {}
	all_data.tables = {}
	all_data.table_creators = {}
	--all_data.players_in_table = {} K=player V=table_id
	print("on_deploy")
	contract.emit("deploy" )
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

-- 参与匹配
function pay_deposit(deposit_fee)
	-- todo:检查deposit_fee的值范围
	--deposit_fee = math.floor(deposit_fee)
	if(deposit_fee < 1)then
		error("error deposit_fee value")
	end
	-- deposit_map 押金表
	local all_data = contract.get_data()
	local old_deposit_fee = all_data.deposit_map[contract.get_caller()]
	local pay_value = 0
	local back_value = 0
	if(old_deposit_fee == nil)then
		pay_value = deposit_fee
	else
		if(deposit_fee == old_deposit_fee)then
			error("error deposit_fee value")
		elseif(deposit_fee > old_deposit_fee)then
			pay_value = deposit_fee - old_deposit_fee
		else
			-- todo:是否在游戏中,游戏中无法减小押金
			back_value = old_deposit_fee - deposit_fee
		end
	end
	if(pay_value > 0)then
		contract.transfer(contract.get_caller(), contract.get_name(), pay_value)
	end
	if(back_value > 0)then
		contract.transfer(contract.get_name(), contract.get_caller(), back_value)
	end
	all_data.deposit_map[contract.get_caller()] = deposit_fee
	contract.emit("pay_deposit", contract.get_caller(), deposit_fee, old_deposit_fee)
end

--[[
	创建桌子
	table_id: todo:检查值范围
	table_option_jsonstr:
		{
			min_deposit_fee = 100, 	-- 押金要求
			min_bet_amount = 10,	-- 底注
			inc_bet_amount = 10,	-- 单次加注限制
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
	--table_id = math.floor(table_id)
	if(deposit_fee < 1)then
		error("error table_id value")
	end
	local all_data = contract.get_data()
	if(all_data.table_creators[contract.get_caller()] == nil)then
		error("not have right to create table")
	end
	local table_option = contract.jsonstr_to_table(table_option_jsonstr)
	local players = contract.jsonstr_to_table(players_jsonstr)
	for i,player_name in ipairs(players) do
		if(all_data.deposit_map[player_name] == nil)then
			error("player not in deposit_map")
		end
		if(all_data.deposit_map[player_name] < table_option.min_deposit_fee)then
			error("player not have enougn deposit_fee")
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
	local new_table = { table_id = table_id, table_option = table_option, creator = contract.get_caller(), create_time = chain.head_block_num(), play_state = EState.Join,
						players = {}, deck={}, shuffle_decks = {}, current_player_index=1, current_bet_amount=table_option.min_bet_amount, bet_pool=0 }
	for i,player_name in ipairs(players) do
		table.insert(new_table.players, {player_name=player_name,is_joined=false,is_facedown=true,is_giveup=false})
	end
	all_data.tables[table_id] = new_table
	all_data.created_table_count = all_data.created_table_count + 1
	-- todo:player增加一个状态值,防止一个player同时参加多个牌桌
	-- table增加超时设置,防止游戏服务器停止运行,导致player卡在该状态?
	contract.emit("table_create", contract.get_caller(), table_id, table_option_jsonstr, players_jsonstr) -- jsonstr是否能正确保存???
end

-- 玩家加入牌桌
function table_join(table_id)
	--table_id = math.floor(table_id)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	if(table_data.play_state ~= EState.Join)then
		error("error table state")
	end
	for i,player_data in ipairs(table_data.players) do
		if(player_data.player_name == contract.get_caller())then
			if(not player_data.is_joined)then
				player_data.is_joined = true
				contract.emit("table_join", contract.get_caller(), table_id)
				local is_all_joined = true
				for j,player_data2 in ipairs(table_data.players) do
					if(not player_data2.is_joined)then
						is_all_joined = false
						break
					end
				end
				if(is_all_joined)then
					table_data.play_state = EState.Shuffle
				end
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

-- 洗牌
-- todo:怎么防止玩家直接调用合约接口,而发来错误数据?
function shuffle_deck(table_id, encrypted_deck_jsonstr)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	if(table_data.play_state ~= EState.Shuffle)then
		error("error table state")
	end
	local player_index = get_player_index(contract.get_caller(), table_data)
	if( player_index == nil )then
		error("error table_id")
	end
	if(table_data.current_player_index ~= player_index)then
		error("not your turn")
	end
	local encrypted_deck = contract.jsonstr_to_table(encrypted_deck_jsonstr)
	if(#encrypted_deck ~= 52)then
		error("error encrypted_deck_jsonstr")
	end
	-- todo: check encrypted_deck
	table_data.current_encrypted_deck = encrypted_deck
	table_data.current_player_index = table_data.current_player_index + 1
	contract.emit("shuffle_deck", contract.get_caller(), table_id, encrypted_deck_jsonstr)
	if(table_data.current_player_index > #table_data.players)then
		table_data.play_state = EState.EncryptCards
		table_data.current_player_index = 1
	end
end

-- 给每张牌加密
function encrypt_cards(table_id, encrypted_deck_jsonstr, pubkeys_jsonstr)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	if(table_data.play_state ~= EState.EncryptCards)then
		error("error table state")
	end
	local player_index = get_player_index(contract.get_caller(), table_data)
	if( player_index == nil )then
		error("error table_id")
	end
	if(table_data.current_player_index ~= player_index)then
		error("not your turn")
	end
	local encrypted_deck = contract.jsonstr_to_table(encrypted_deck_jsonstr)
	if(#encrypted_deck ~= 52)then
		error("error encrypted_deck_jsonstr")
	end
	local pubkeys = contract.jsonstr_to_table(pubkeys_jsonstr)
	if(#pubkeys ~= 52)then
		error("error pubkeys_jsonstr")
	end
	-- todo: check pubkeys
	-- todo: check encrypted_deck
	table_data.players[player_index].pubkeys = pubkeys
	table_data.current_encrypted_deck = encrypted_deck
	table_data.current_player_index = table_data.current_player_index + 1
	contract.emit("encrypt_cards", contract.get_caller(), table_id, encrypted_deck_jsonstr, pubkeys_jsonstr)
	if(table_data.current_player_index > #table_data.players)then
		table_data.play_state = EState.Deal
		table_data.current_player_index = 1
	end
end

-- 发牌
-- 该接口必须由table.creator调用
function deal(table_id)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	if(contract.get_caller() ~= table_data.creator)then
		error("you are not the table's creator")
	end
	if(table_data.play_state ~= EState.Deal)then
		error("error table state")
	end
	for i=1,#table_data.players do
		table_data.players[i].hand_cards = {}
		for j=1,3 do
			local card_index = (i-1)*3+j
			local card_data = { card_index=card_index, prikeys={} }
			table_data.players[i].hand_cards[j] = card_data
		end
	end
	table_data.play_state = EState.Playing
	contract.emit("deal", contract.get_caller(), table_id )
end

--[[
  玩家看自己的手牌
  prikeys_jsonstr:其他玩家的对该玩家手牌的私钥
  [
	{}, -- 假设A看牌,自己的私钥不公开
	[prikey1_BA,prikey2_BA,prikey3_BA],
	[prikey1_CA,prikey2_CA,prikey3_CA],
	[...],
  ]
  该接口必须由table.creator调用
]]--
function set_faceup(table_id, player_index, prikeys_jsonstr)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	if(contract.get_caller() ~= table_data.creator)then
		error("you are not the table's creator")
	end
	if(table_data.play_state ~= EState.Playing)then
		error("error table state")
	end
	if( table_data.players[player_index] == nil )then
		error("error player_index")
	end
	if(table_data.players[player_index].is_giveup)then
		error("already giveup")
	end
	if(not table_data.players[player_index].is_facedown )then
		error("already faceup")
	end
	-- todo: check prikeys
	local prikeys = contract.jsonstr_to_table(prikeys_jsonstr)
	if(#prikeys ~= #table_data.players )then
		error("error prikeys")
	end
	for i,prikey3 in ipairs(prikeys) do
		if(i ~= player_index and #prikey3 ~= 3 )then
			error("error prikeys")
		end
		for j=1,3 do
			if(i == player_index)then
				table_data.players[player_index].hand_cards[j].prikeys[i] = "" -- 自己的私钥不公开
			else
				-- todo: check prikey3[j]
				-- card_index = table_data.players[player_index].hand_cards[j].card_index
				-- pubkey = table_data.players[i].pubkeys[card_index]
				-- pubkey prikey3[j] keypair?
				table_data.players[player_index].hand_cards[j].prikeys[i] = prikey3[j]
			end
		end
	end
	table_data.players[player_index].is_facedown = false
	contract.emit("set_faceup", contract.get_caller(), table_id, player_index, prikeys_jsonstr )
end

-- 下注
function bet_continue(table_id, bet_amount)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	if(table_data.play_state ~= EState.Playing)then
		error("error table state")
	end
	local player_index = get_player_index(contract.get_caller(), table_data)
	if( player_index == nil )then
		error("error table_id")
	end
	if(table_data.players[player_index].is_giveup)then
		error("already giveup")
	end
	if(table_data.current_player_index ~= player_index)then
		error("not your turn")
	end
	local min_bet_amount = table_data.current_bet_amount
	if(table_data.players[player_index].is_facedown)then
		min_bet_amount = min_bet_amount // 2 -- 安排只需要一半的注
	end
	if(bet_amount < min_bet_amount)then
		error("error bet_amount value")
	end
	-- todo:检查上限
	contract.transfer(contract.get_caller(), contract.get_name(), bet_amount)
	table_data.current_bet_amount = (table_data.players[player_index].is_facedown and bet_amount*2 or bet_amount)
	table_data.bet_pool = table_data.bet_pool + bet_amount
	local next_player_index = 0
	for i=1,#table_data.players-1 do
		local check_index = (player_index+i) % #table_data.players
		if(not table_data.players[check_index].is_giveup)then
			next_player_index = i
			table_data.current_player_index = next_player_index
			break
		end
	end
	contract.emit("bet_continue", contract.get_caller(), table_id, bet_amount )
end

local function set_winner(all_data, table_data, table_id, winner_index)
	table_data.winner_index = winner_index
	table_data.play_state = EState.End
	-- 
	contract.transfer(contract.get_name(), table_data.players[winner_index], table_data.bet_pool)
end

--[[
	弃牌
	prikeys_jsonstr:该玩家掌握的其他玩家的手牌的私钥
	[
		{}, -- 假设A弃牌,自己的私钥不公开
		[prikey1_AB,prikey2_AB,prikey3_AB],
		[prikey1_AC,prikey2_AC,prikey3_AC],
		[...],
	]
]]--
function bet_giveup(table_id,prikeys_jsonstr)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	if(table_data.play_state ~= EState.Playing)then
		error("error table state")
	end
	local player_index = get_player_index(contract.get_caller(), table_data)
	if( player_index == nil )then
		error("error table_id")
	end
	if(table_data.players[player_index].is_giveup)then
		error("already giveup")
	end
	if(table_data.current_player_index ~= player_index)then
		error("not your turn")
	end
	table_data.players[player_index].is_giveup = true
	local prikeys = contract.jsonstr_to_table(prikeys_jsonstr)
	if(#prikeys ~= #table_data.players)then
		error("error prikeys_jsonstr")
	end
	for i,prikey3 in ipairs(prikeys) do
		if(i ~= player_index and #prikey3 ~= 3 )then
			error("error prikeys")
		end
		if(i ~= player_index)then
			for j=1,3 do
				-- todo: check prikey3[j]
				-- card_index = table_data.players[i].hand_cards[j].card_index
				-- pubkey = table_data.players[player_index].pubkeys[card_index]
				-- pubkey prikey3[j] keypair?
				table_data.players[i].hand_cards[j].prikeys[player_index] = prikey3[j]
			end
		end
	end
	contract.emit("bet_giveup", contract.get_caller(), table_id, prikeys_jsonstr )
	
	-- 找下一个还没弃牌的玩家 1234 2 345%4 3 0(4) 1 
	local next_player_index = 0
	for i=1,#table_data.players-1 do
		local check_index = (player_index+i) % #table_data.players
		if(check_index == 0)then
			check_index = #table_data.players
		end
		if(not table_data.players[check_index].is_giveup)then
			next_player_index = i
			table_data.current_player_index = next_player_index
			break
		end
	end
	-- todo:检查是否只剩下一名玩家了,如果只有一名玩家了,则游戏结束
	local remain_player_count = 0
	local remain_player_index = 0
	for i=1,#table_data.players do
		if(not table_data.players[i].is_giveup)then
			remain_player_count = remain_player_count + 1
			remain_player_index = i
		end
	end
	if(remain_player_count == 1)then
		set_winner(all_data, table_data, table_id, remain_player_index)
	end
end

-- 开牌
function bet_open(table_id)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	if(table_data.play_state ~= EState.Playing)then
		error("error table state")
	end
	local player_index = get_player_index(contract.get_caller(), table_data)
	if( player_index == nil )then
		error("error table_id")
	end
	if(table_data.players[player_index].is_giveup)then
		error("already giveup")
	end
	if(table_data.current_player_index ~= player_index)then
		error("not your turn")
	end
	local remain_player_count = 0
	for i=1,#table_data.players do
		if(not table_data.players[i].is_giveup)then
			remain_player_count = remain_player_count + 1
		end
	end
	if(remain_player_count ~= 2)then
		error("only can do when there is 2 players remain")
	end
	local bet_amount = table_data.current_bet_amount
	if(not table_data.players[player_index].is_facedown)then
		bet_amount = bet_amount * 2
	end
	contract.transfer(contract.get_caller(), contract.get_name(), bet_amount)
	contract.emit("bet_open", contract.get_caller(), table_id, bet_amount )
	table_data.bet_pool = table_data.bet_pool + bet_amount
	table_data.play_state = EState.WaitResult
end

--[[
  开牌结果
  prikeys_jsonstr:双方玩家的自己的以及对方的私钥
  [ -- 假设A选择和B开牌
	[prikey1_AA,prikey2_AA,prikey3_AA], -- open_index自己的
	[prikey1_AB,prikey2_AB,prikey3_AB], -- open_index持有another_index的
	[prikey1_BB,prikey2_BB,prikey3_BB], -- another_index自己的
	[prikey1_BA,prikey2_BA,prikey3_BA], -- another_index持有open_index的
  ]
  该接口必须由table.creator调用
]]--
function set_open_result(open_index, another_index, winner_index, prikeys_jsonstr)
	local all_data = contract.get_data()
	local table_data = all_data.tables[table_id]
	if(table_data == nil)then
		error("error table_id")
	end
	if(contract.get_caller() ~= table_data.creator)then
		error("you are not the table's creator")
	end
	if(table_data.play_state ~= EState.WaitResult)then
		error("error table state")
	end
	for i=1,2 do
		local player_index = (i==1 and open_index or another_index)
		if( table_data.players[player_index] == nil )then
			error("error player_index")
		end
		if(table_data.players[player_index].is_giveup)then
			error("already giveup")
		end
	end
	if(winner_index ~= open_index and winner_index ~= another_index)then
		error("error winner_index")
	end
	-- todo: check prikeys
	local prikeys = contract.jsonstr_to_table(prikeys_jsonstr)
	if(#prikeys ~= 4 )then
		error("error prikeys")
	end
	for i,prikey3 in ipairs(prikeys) do
		if( #prikey3 ~= 3 )then
			error("error prikeys")
		end
		local hand_index = (i==1 or i==4) and open_index or another_index
		local from_index = (i==1 or i==2) and open_index or another_index
		for j=1,3 do
			-- todo: check prikey3[j]
			-- card_index = table_data.players[hand_index].hand_cards[j].card_index
			-- pubkey = table_data.players[from_index].pubkeys[card_index]
			-- pubkey prikey3[j] keypair?
			table_data.players[hand_index].hand_cards[j].prikeys[from_index] = prikey3[j]
	end
	contract.emit("set_open_result", contract.get_caller(), table_id, open_index, another_index, winner_index, prikeys_jsonstr )
	set_winner(all_data, table_data, table_id, winner_index)
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

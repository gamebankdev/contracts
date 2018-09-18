
local price = 2000 -- 2 GB
local draw_block_num_period = 20*60*24 -- one day
local stop_buy_time_before_draw = 20*10 -- 10 minutes before draw
local lottery_digit_count = 3

local function typeex(obj)
	local simple_type = type(obj)
	if(simple_type == "number" and isinteger(obj))then
		return "integer"
	end
	return simple_type
end

-- 合约初始化
function on_deploy()
	local all_data = contract.get_data()
	all_data.no = 1
	all_data.draw_block_num = chain.head_block_num() + draw_block_num_period
	all_data.prize_pool = 0
	all_data.data = {}
	--print("type(draw_block_num_period):"..typeex(draw_block_num_period))
	--print("type(all_data.draw_block_num):"..typeex(all_data.draw_block_num))
	print("on_deploy all_data.draw_block_num:"..all_data.draw_block_num)
	contract.emit("info", all_data.no, all_data.draw_block_num, all_data.prize_pool)
end

-- 购买N张彩票
-- lotteryNumber 彩票数字
-- lotteryCount 彩票数量
function buy(lotteryNumber,lotteryCount)
	print("lotteryCount:"..lotteryCount)
	lotteryCount = tonumber(lotteryCount)
	if(string.len(lotteryNumber) ~= lottery_digit_count)then
		error("lottery number must be a "..lottery_digit_count.." digit number")
	end
	-- check caller's balance
	-- 
	local all_data = contract.get_data()
	if(chain.head_block_num() >= all_data.draw_block_num - stop_buy_time_before_draw)then
		error("cant buy at 10 minutes before draw time")
	end
	all_data.data[#all_data.data+1] = {contract.get_caller(), lotteryNumber, lotteryCount}
	all_data.prize_pool = all_data.prize_pool + price*lotteryCount
	contract.transfer(contract.get_caller(), contract.get_name(), price)
	contract.emit("buy", contract.get_caller(), lotteryNumber, lotteryCount)
	print("all_data.prize_pool:"..all_data.prize_pool)
end

-- 开奖
function draw()
	local all_data = contract.get_data()
	if(chain.head_block_num() < all_data.draw_block_num)then
		error("not the right time")
	end
	-- generate random prize number
	local block_hash = chain.get_block_hash(all_data.draw_block_num, 10, 10)
	print("block_hash : "..block_hash)
	local hash_5 = string.sub(block_hash,string.len(block_hash)-(lottery_digit_count-1), string.len(block_hash)) -- last lottery_digit_count char
	local hash_number = tostring(tonumber(hash_5, 16)) -- convert to number
	print("hash_number : "..hash_number)
	local strlen = string.len(hash_number)
	if(strlen > lottery_digit_count)then
		hash_number = string.sub(hash_number, string.len(hash_number)-(lottery_digit_count-1), string.len(hash_number)) -- last lottery_digit_count digit
	else
		for i=strlen+1,lottery_digit_count do
			hash_number = "0"..hash_number
		end
	end
	local prize_number = hash_number
	print("prize_number : "..prize_number)
	
	local prize_lottery_count = 0 -- 中奖票数
	local prize_map = {}
	for idx,lottery_data in ipairs(all_data.data) do
		if(lottery_data[2] == prize_number)then
			prize_lottery_count = prize_lottery_count + lottery_data[3]
			prize_map[lottery_data[1]] = (prize_map[lottery_data[1]] or 0 ) + lottery_data[3]
		end
	end
	if(prize_lottery_count > 0)then
		local left_prize_pool = 0
		for user_name,lottery_count in pairs(prize_map) do
			local remainder = (all_data.prize_pool*lottery_count)%prize_lottery_count -- 除不尽的余数累积到下个奖池
			left_prize_pool = left_prize_pool + remainder
			local cur_prize = (all_data.prize_pool*lottery_count-remainder)//prize_lottery_count
			cur_prize = math.floor(cur_prize)
			print("cur_prize:"..cur_prize)
			contract.transfer(contract.get_name(), user_name, cur_prize)
			contract.emit("win", all_data.no, user_name, cur_prize, lottery_count )
			print("draw "..user_name..":"..cur_prize)
		end
		all_data.prize_pool = left_prize_pool
	end
	all_data.no = all_data.no + 1
	all_data.data = {}
	all_data.draw_block_num = chain.head_block_num() + draw_block_num_period
	contract.emit("draw", all_data.no-1, prize_number, contract.get_caller(), prize_lottery_count )
	contract.emit("info", all_data.no, all_data.draw_block_num, all_data.prize_pool)
end

-- only for test
function testcommand(cmd, arg)
	if(cmd == "setdrawblocknumsetdrawblocknum")then
		local block_num = math.floor(tonumber(arg))
		local all_data = contract.get_data()
		--print("type(all_data.draw_block_num):"..typeex(all_data.draw_block_num))
		all_data.draw_block_num = chain.head_block_num() + block_num
		--print("type(all_data.draw_block_num):"..typeex(all_data.draw_block_num))
		print("all_data.draw_block_num:"..all_data.draw_block_num)
		contract.emit("info", all_data.no, all_data.draw_block_num, all_data.prize_pool)
	elseif(cmd == "addprizepool")then
		local add_prize = math.floor(tonumber(arg))
		if(add_prize < 1)then
			error("arg must be integer")
		end
		contract.transfer(contract.get_caller(), contract.get_name(), add_prize)
		local all_data = contract.get_data()
		all_data.prize_pool = all_data.prize_pool + add_prize
		contract.emit("info", all_data.no, all_data.draw_block_num, all_data.prize_pool)
	end
end

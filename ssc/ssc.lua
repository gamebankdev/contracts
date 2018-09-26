
local init_options =
{
	price = 2000, -- 2 GB,
	min_contract_balance = 100000*2,
	draw_block_num_period = 20*10,  -- 10 minutes
	stop_buy_time_before_draw = 10, -- 30 seconds before draw
	lottery_digit_count = 5
}

local enum_daxiaodanshuang =
{
	da = 1,
	xiao = 2,
	dan = 3,
	shuang = 4
}

local items = {}

-- 阶乘
local function factorial(n)
	if( n <= 0)then
		return 1
	else
		return n * factorial(n-1)
	end
end

-- 直选或通选
local function get_lottery_count_zhixuan( digits_table )
	local lottery_count = 1
	for _i,digit_array in ipairs(digits_table) do
		lottery_count = lottery_count * (#digit_array)
	end
	return lottery_count
end

-- 组三
local function get_lottery_count_zhu3( digits_table )
	-- C(x,2) = (x!)/(2!)((x-2)!)
	local x = #digits_table[1]
	local lottery_count = ( factorial(x) // (2*(factorial(x-2))) ) * 2
	return lottery_count
end

-- 组六
local function get_lottery_count_zhu6( digits_table )
	-- C(x,3) = (x!)/(3!)((x-3)!)
	local x = #digits_table[1]
	local lottery_count = ( factorial(x) // (6*(factorial(x-3))) )
	return lottery_count
end

-- 二星组选
local function get_lottery_count_zhu2( digits_table )
	-- C(x,2) = (x!)/(2!)((x-2)!)
	local x = #digits_table[1]
	local lottery_count = ( factorial(x) // (2*(factorial(x-2))) )
	return lottery_count
end

-- 大小单双
local function get_lottery_count_daxiaodanshuang( digits_table )
	return 1
end

-- 检查前几位或后几位数字是否相同
local function check_same_digit(lottery_data, prize_numbers, check_digit_count, is_front)
	local buyer = lottery_data[1]
	local item_id = lottery_data[2]
	local digits_table = lottery_data[3]
	local begin_idx = is_front and (#digits_table-check_digit_count+1) or 1
	local match_digit_count = 0
	local match_number = ""
	for i=begin_idx,begin_idx+check_digit_count-1 do
		for _j,digit in ipairs(digits_table[i])do
			if(digit == prize_numbers[i])then
				match_digit_count = match_digit_count + 1
				match_number = digit..match_number
				break
			end
		end
	end
	if(match_digit_count == check_digit_count)then
		contract.transfer(contract.get_name(), buyer, items[check_digit_count].prize)
		contract.emit("win", buyer, item_id, items[check_digit_count].prize, check_digit_count )
		print("win check_same_digit:"..lottery_data[1].." "..match_number.."("..(is_front and "front)" or "back)"))
	end
end

-- 直选
local function check_zhixuan(lottery_data, prize_numbers )
	local buyer = lottery_data[1]
	local item_id = lottery_data[2]
	local digits_table = lottery_data[3]
	local group_count = #digits_table
	local match_digit_count = 0
	local match_number = ""
	for i=1,group_count do
		for _j,digit in ipairs(digits_table[i])do
			if(digit == prize_numbers[i])then
				match_digit_count = match_digit_count + 1
				match_number = digit..match_number
				break
			end
		end
	end
	if(match_digit_count == group_count)then
		contract.transfer(contract.get_name(), buyer, items[item_id].prize)
		contract.emit("win", buyer, item_id, items[item_id].prize )
		print("win zhixuan:"..buyer.." "..match_number)
	end
end

-- 五星通选
local function check_tongxuan5(lottery_data, prize_numbers )
	local buyer = lottery_data[1]
	local item_id = lottery_data[2]
	local digits_table = lottery_data[3]
	local group_count = #digits_table
	local match_digit_count = 0
	local match_number = ""
	for i=1,group_count do
		for _j,digit in ipairs(digits_table[i])do
			if(digit == prize_numbers[i])then
				match_digit_count = match_digit_count + 1
				match_number = digit..match_number
				break
			end
		end
	end
	if(match_digit_count == group_count)then
		contract.transfer(contract.get_name(), buyer, items[item_id].prize)
		contract.emit("win", buyer, item_id, items[item_id].prize )
		print("win tongxuan5:"..buyer.." "..match_number)
	end
	check_same_digit(lottery_data, prize_numbers, 3, true)
	check_same_digit(lottery_data, prize_numbers, 3, false)
	check_same_digit(lottery_data, prize_numbers, 2, true)
	check_same_digit(lottery_data, prize_numbers, 2, false)
	match_digit_count = 0
	match_number = ""
	for i=1,group_count do
		if(i ~= 3)then
			for _j,digit in ipairs(digits_table[i])do
				if(digit == prize_numbers[i])then
					match_digit_count = match_digit_count + 1
					match_number = digit..match_number
					break
				end
			end
		end
	end
	if(match_digit_count == 4)then
		contract.transfer(contract.get_name(), buyer, items[item_id].extra_prize[4])
		contract.emit("win", buyer, item_id, items[item_id].extra_prize[4])
		print("win tongxuan4:"..buyer.." "..match_number)
	end
end

-- 三星组三
local function check_zhu3(lottery_data, prize_numbers )
	local buyer = lottery_data[1]
	local item_id = lottery_data[2]
	local digits_table = lottery_data[3]
	
	local digit_array = {}
	for i=1,3 do
		local is_exist = false
		for j,digit in ipairs(digit_array) do
			if(prize_numbers[i] == digit)then
				is_exist = true
				break
			end
		end
		if(not is_exist)then
			table.insert(digit_array, prize_numbers[i])
		end
	end
	if(#digit_array ~= 2 )then
		return false
	end
	--print("digit_array:"..digit_array[2]..digit_array[1])

	for i=1,#digits_table[1] do
		local match_digits = {}
		local match_digit_count = 0
		local match_number = ""
		if(digits_table[1][i] == digit_array[1] or digits_table[1][i] == digit_array[2])then
			match_digit_count = match_digit_count + 1
			table.insert(match_digits, digits_table[1][i])
			match_number = digits_table[1][i]..match_number
			for j=i+1,#digits_table[1] do
				if(digits_table[1][j] == digit_array[1] or digits_table[1][j] == digit_array[2])then
					if(digits_table[1][j] ~= match_digits[1] )then
						match_digit_count = match_digit_count + 1
						match_number = digits_table[1][j]..match_number
						break
					end
				end
			end
			if(match_digit_count == 2)then
				contract.transfer(contract.get_name(), buyer, items[item_id].prize)
				contract.emit("win", buyer, item_id, items[item_id].prize )
				print("win zhu3:"..buyer.." "..match_number)
			end
		end
	end
end

-- 三星组六
local function check_zhu6(lottery_data, prize_numbers )
	local buyer = lottery_data[1]
	local item_id = lottery_data[2]
	local digits_table = lottery_data[3]
	
	local digit_array = {}
	for i=1,3 do
		local is_exist = false
		for j,digit in ipairs(digit_array) do
			if(prize_numbers[i] == digit)then
				is_exist = true
				break
			end
		end
		if(not is_exist)then
			table.insert(digit_array, prize_numbers[i])
		end
	end
	if(#digit_array ~= 3 )then
		return false
	end
	
	for i=1,#digits_table[1] do
		for j=2,#digits_table[1] do
			for k=3,#digits_table[1] do
				local match_digit_count = 0
				local match_number = ""
				for _,digit in ipairs(digit_array) do
					if(digits_table[1][i] == digit
						or digits_table[1][j] == digit
						or digits_table[1][k] == digit )then
						match_digit_count = match_digit_count + 1
						match_number = digit..match_number
					end
				end
				if(match_digit_count == 3)then
					contract.transfer(contract.get_name(), buyer, items[item_id].prize)
					contract.emit("win", buyer, item_id, items[item_id].prize )
					print("win zhu6:"..buyer.." "..match_number)
					return
				end
			end
		end
	end
end

-- 二星组选
local function check_zhu2(lottery_data, prize_numbers )
	local buyer = lottery_data[1]
	local item_id = lottery_data[2]
	local digits_table = lottery_data[3]
	
	local digit_array = {}
	for i=1,2 do
		local is_exist = false
		for j,digit in ipairs(digit_array) do
			if(prize_numbers[i] == digit)then
				is_exist = true
				break
			end
		end
		if(not is_exist)then
			table.insert(digit_array, prize_numbers[i])
		end
	end
	if(#digit_array ~= 2 )then
		return false
	end
	
	for i=1,#digits_table[1] do
		for j=2,#digits_table[1] do
			local match_digit_count = 0
			for _,digit in ipairs(digit_array) do
				if(digits_table[1][i] == digit
					or digits_table[1][j] == digit )then
					match_digit_count = match_digit_count + 1
				end
			end
			if(match_digit_count == 2)then
				contract.transfer(contract.get_name(), buyer, items[item_id].prize)
				contract.emit("win", buyer, item_id, items[item_id].prize )
				print("win zhu2:"..buyer.." "..digits_table[1][i]..digits_table[1][j])
				return
			end
		end
	end
end

-- 是否匹配大小单双
local function is_match_daxiaodanshuang(digit, compare_num)
	if(compare_num == enum_daxiaodanshuang.da)then
		return (digit >= 5)
	elseif(compare_num == enum_daxiaodanshuang.xiao)then
		return (digit <= 4)
	elseif(compare_num == enum_daxiaodanshuang.dan)then
		return (digit % 2) == 1
	elseif(compare_num == enum_daxiaodanshuang.shuang)then
		return (digit % 2) == 0
	end
end


-- 大小单双
local function check_daxiaodanshuang(lottery_data, prize_numbers )
	local buyer = lottery_data[1]
	local item_id = lottery_data[2]
	local digits_table = lottery_data[3]
	
	for _i,ten in ipairs(digits_table[2]) do
		if( is_match_daxiaodanshuang(prize_numbers[2], ten) )then
			for _j,ge in ipairs(digits_table[1]) do
				if( is_match_daxiaodanshuang(prize_numbers[1], ge) )then
					print("win daxiaodanshuang:"..buyer.." "..ten..ge)
				end
			end
		end
	end
end

items =
{
	-- [1]五星直选
	{
		group_count = 5,
		digit_count_min = 1,
		digit_count_max = 10,
		get_lottery_count = get_lottery_count_zhixuan,
		check_prize = check_zhixuan,
		prize = 100000
	},
	-- [2]五星通选
	{
		group_count = 5,
		digit_count_min = 1,
		digit_count_max = 10,
		get_lottery_count = get_lottery_count_zhixuan,
		check_prize = check_tongxuan5,
		prize = 20440,
		extra_prize = {0,20,220,40}
	},
	-- [3]三星直选
	{
		group_count = 3,
		digit_count_min = 1,
		digit_count_max = 10,
		get_lottery_count = get_lottery_count_zhixuan,
		check_prize = check_zhixuan,
		prize = 1000
	},
	-- [4]三星组三
	{
		group_count = 1,
		digit_count_min = 2,
		digit_count_max = 10,
		get_lottery_count = get_lottery_count_zhu3,
		check_prize = check_zhu3,
		prize = 320
	},
	-- [5]三星组六
	{
		group_count = 1,
		digit_count_min = 3,
		digit_count_max = 10,
		get_lottery_count = get_lottery_count_zhu6,
		check_prize = check_zhu6,
		prize = 160
	},
	-- [6]二星直选
	{
		group_count = 2,
		digit_count_min = 1,
		digit_count_max = 10,
		get_lottery_count = get_lottery_count_zhixuan,
		check_prize = check_zhixuan,
		prize = 100
	},
	-- [7]二星组选
	{
		group_count = 1,
		digit_count_min = 2,
		digit_count_max = 10,
		get_lottery_count = get_lottery_count_zhu2,
		check_prize = check_zhu2,
		prize = 50
	},
	-- [8]一星
	{
		group_count = 1,
		digit_count_min = 1,
		digit_count_max = 10,
		get_lottery_count = get_lottery_count_zhixuan,
		check_prize = check_zhixuan,
		prize = 10
	},
	-- [9]大小单双
	{
		group_count = 2,
		digit_count_min = 1,
		digit_count_max = 1,
		get_lottery_count = get_lottery_count_daxiaodanshuang,
		check_prize = check_daxiaodanshuang,
		prize = 4
	}
}

local function get_options()
	return init_options
end

local function new_data(all_data)
	all_data.no = all_data.no + 1
	all_data.draw_block_num = chain.head_block_num() + get_options().draw_block_num_period
	all_data.lottery_count = 0
	all_data.prize_pool = 0
	all_data.data = {}
	all_data.items = {}
	for i,item in ipairs(items) do
		table.insert(all_data.items, { lottery_count = 0 } )
	end
end

-- 合约初始化
function on_deploy()
	local all_data = contract.get_data()
	all_data.no = 0
	all_data.is_active = false
	new_data(all_data)
	print("on_deploy all_data.draw_block_num:"..all_data.draw_block_num)
	contract.emit("info", all_data.no, all_data.draw_block_num, all_data.prize_pool)
end

-- 购买彩票
-- item_id 类型
-- numbers 购买的数字,json数组格式 [[1,2,3,4],[2,3,5],[0,2,3]]
function buy(item_id, json_args)
	local item = items[item_id]
	if(item == nil)then
		error("error item_id value")
	end
	--[个十百千万][0123456789]
	local digits_table = contract.jsonstr_to_table(json_args)
	if(digits_table == nil)then
		error("error json_args")
	end
	if( #digits_table ~= item.group_count)then
		error("error group count")
	end
	for _i,digit_array in ipairs(digits_table) do
		if(#digit_array < item.digit_count_min or #digit_array > item.digit_count_max )then
			error("error digit count")
		end
	end
	local lottery_count = item.get_lottery_count(digits_table)
	if(lottery_count < 1)then
		error("error lottery_count:"..lottery_count)
	end
	
	-- check caller's balance
	-- 
	local all_data = contract.get_data()
	if( not all_data.is_active)then
		error("not active yet")
	end
	if(chain.head_block_num() >= all_data.draw_block_num - get_options().stop_buy_time_before_draw)then
		error("cant buy at "..(get_options().stop_buy_time_before_draw*3).." seconds before draw time")
	end
	all_data.data[#all_data.data+1] = {contract.get_caller(), item_id, digits_table}
	all_data.lottery_count = all_data.lottery_count + lottery_count
	all_data.items[item_id].lottery_count = all_data.items[item_id].lottery_count + lottery_count
	contract.transfer(contract.get_caller(), contract.get_name(), lottery_count*get_options().price)
	contract.emit("buy", contract.get_caller(), json_args, lottery_count, lottery_count*get_options().price)
	print("all_data.lottery_count:"..all_data.lottery_count)
end

-- 生成开奖号码
local function generate_prize_number(all_data)
	-- generate random prize number
	local block_hash = chain.get_block_hash(all_data.draw_block_num, 10, 1) -- 30 seconds
	print("block_hash : "..block_hash)
	local hash_5 = string.sub(block_hash,string.len(block_hash)-(get_options().lottery_digit_count-1), string.len(block_hash)) -- last lottery_digit_count char
	local hash_number = tonumber(hash_5, 16) % 100000 -- convert to number
	-- test
	hash_number = 12580
	local prize_numbers = {
		[1] = (hash_number%10),
		[2] = ((hash_number%100) // 10),
		[3] = ((hash_number%1000) // 100),
		[4] = ((hash_number%10000) // 1000),
		[5] = ((hash_number) // 10000)
	}
	local prize_number = ""..prize_numbers[5]..prize_numbers[4]..prize_numbers[3]..prize_numbers[2]..prize_numbers[1]
	print("prize_number : "..prize_number)
	return prize_numbers,prize_number
end

-- 开奖
function draw()
	local all_data = contract.get_data()
	if(chain.head_block_num() < all_data.draw_block_num)then
		error("not the right time")
	end
	local prize_numbers,prize_number = generate_prize_number(all_data)
	
	local prize_lottery_count = 0 -- 中奖票数
	local prize_map = {}
	for idx,lottery_data in ipairs(all_data.data) do
		local item_id = lottery_data[2]
		local item = items[item_id]
		item.check_prize(lottery_data, prize_numbers)
	end
	
	new_data(all_data)
	contract.emit("draw", all_data.no-1, prize_number, contract.get_caller(), prize_lottery_count )
	contract.emit("info", all_data.no, all_data.draw_block_num, all_data.prize_pool)
end


--[[----------------------------------------------------------------------------------------------
											T E S T
--]]----------------------------------------------------------------------------------------------
local function test_lottery_count_zhixuan5()
	local item_id = 1
	local item = items[item_id]
	for ge=0,9 do
		for shi=0,9 do
			for bai=0,9 do
				for qian=0,9 do
					for wan=0,9 do
						local digits_table = {}
						digits_table[1] = {}
						for x=0,ge do
							table.insert(digits_table[1],x)
						end
						digits_table[2] = {}
						for x=0,shi do
							table.insert(digits_table[2],x)
						end
						digits_table[3] = {}
						for x=0,bai do
							table.insert(digits_table[3],x)
						end
						digits_table[4] = {}
						for x=0,qian do
							table.insert(digits_table[4],x)
						end
						digits_table[5] = {}
						for x=0,wan do
							table.insert(digits_table[5],x)
						end
						local lottery_count = item.get_lottery_count(digits_table)
						print(""..(ge).."*"..(shi).."*"..(bai).."*"..(qian).."*"..(wan).." -> "..lottery_count)
					end
				end
			end
		end
	end
end

local function test_lottery_count_zhuxuan3()
	local item_id = 4
	local item = items[item_id]
	for i=2,10 do
		local digits_table = {}
		digits_table[1] = {}
		for j=1,i do
			table.insert(digits_table[1],j-1)
		end
		local lottery_count = item.get_lottery_count(digits_table)
		print("x="..i.." -> "..lottery_count)
	end
end

local function test_lottery_count_zhuxuan6()
	local item_id = 5
	local item = items[item_id]
	for i=3,10 do
		local digits_table = {}
		digits_table[1] = {}
		for j=1,i do
			table.insert(digits_table[1],j-1)
		end
		local lottery_count = item.get_lottery_count(digits_table)
		print("x="..i.." -> "..lottery_count)
	end
end

local function test_lottery_count_zhuxuan2()
	local item_id = 7
	local item = items[item_id]
	for i=2,10 do
		local digits_table = {}
		digits_table[1] = {}
		for j=1,i do
			table.insert(digits_table[1],j-1)
		end
		local lottery_count = item.get_lottery_count(digits_table)
		print("x="..i.." -> "..lottery_count)
	end
end

local function test_buy_tongxuan5()
	local all_data = contract.get_data()
	all_data.is_active = true
	all_data.draw_block_num = 10000000
	buy(2,"[[0,1,2,3,4,5,6,7,8,9],[0,1,2,3,4,5,6,7,8,9],[0,1,2,3,4,5,6,7,8,9],[0,1,2,3,4,5,6,7,8,9],[0,1,2,3,4,5,6,7,8,9]]")
	all_data.draw_block_num = 100
	draw()
end

local function test_buy_zhu3()
	local all_data = contract.get_data()
	all_data.is_active = true
	all_data.draw_block_num = 10000000
	buy(4,"[[0,1,2,3,4,5,6,7,8,9]]")
	all_data.draw_block_num = 100
	draw()
end

local function test_buy_zhu6()
	local all_data = contract.get_data()
	all_data.is_active = true
	all_data.draw_block_num = 10000000
	buy(5,"[[0,1,2,3,4,5,6,7,8,9]]")
	all_data.draw_block_num = 100
	draw()
end

local function test_buy_zhu2()
	local all_data = contract.get_data()
	all_data.is_active = true
	all_data.draw_block_num = 10000000
	buy(5,"[[0,1,2,3,4,5,6,7,8,9]]")
	all_data.draw_block_num = 100
	draw()
end

-- only for test
function testcommand(cmd, arg)
	print("testcommand cmd="..cmd.." arg="..arg)
	if(cmd == "test")then
		--test_lottery_count_zhixuan5()
		--test_lottery_count_zhuxuan3()
		--test_lottery_count_zhuxuan6()
		--test_lottery_count_zhuxuan2()
		--test_buy_tongxuan5()
		--test_buy_zhu3()
		--test_buy_zhu6()
		test_buy_zhu2()
	end
end

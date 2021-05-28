address 0x7257c2417e4d1038e1817c8f283ace2e {
    
    module ViolasAAVE {
	use 0x1::Vector;
	use 0x1::DiemTimestamp;

	const SECONDS_PER_YEAR: u64 = 365;
	const MANTISSA_ONE: u64 = 4294967296;

	const TOKEN_ATOKEN: u64 = 1;
	const TOKEN_STABLE_DEBT: u64 = 2;
	const TOKEN_VARIABLE_DEBT: u64 = 3;
	
	
	// ================================================================================================
	
	resource struct ReserveData {
	    liquidity_index: u64,
	    variable_borrow_index: u64,
	    current_liquidity_rate: u64,
	    current_variable_borrow_rate: u64,
	    current_stable_borrow_rate: u64,
	    last_update_timestamp: u64,
	    id: u64,
	}

	resource struct AToken {
	    index: u64,
	    value: u64,
	}

	resource struct VariableDebtToken {
	    index: u64,
	    value: u64,
	}

	resource struct StableDebtToken {
	    index: u64,
	    value: u64,
	}
	
	resource struct ATokenInfo {
	    total_supply: u64,
	}

	resource struct VariableDebtTokenInfo {
	    total_supply: u64,
	}

	resource struct StableDebtTokenInfo {
	    total_supply: u64,
	    total_supply_timestamp: u64,
	    average_rate: u64,
	}
	
	resource struct GlobalData {
	    reserves: vector<ReserveData>,
	    atoken_infos: vector<ATokenInfo>,
	    variable_debt_token_infos: vector<VariableDebtTokenInfo>,
	    stable_debt_token_infos: vector<StableDebtTokenInfo>,
	}

	// ================================================================================================

	fun contract_address() : address {
	    0x7257c2417e4d1038e1817c8f283ace2e
	}

	// ================================================================================================
	
	fun get_total_supply(idx: u64, tidx: u64) : u64 acquires GlobalData {
	    let gd = borrow_global<GlobalData>(contract_address());
	    if(tidx == TOKEN_ATOKEN) {
		return Vector::borrow(& gd.atoken_infos, idx).total_supply
	    }; 
	    if(tidx == TOKEN_VARIABLE_DEBT) {
		return Vector::borrow(& gd.variable_debt_token_infos, idx).total_supply
	    };
	    if(tidx == TOKEN_STABLE_DEBT) {
		return Vector::borrow(& gd.stable_debt_token_infos, idx).total_supply
	    };
	    0
	}

	fun set_total_supply(idx: u64, tidx: u64, value: u64) acquires GlobalData {
	    let gd = borrow_global_mut<GlobalData>(contract_address());
	    if(tidx == TOKEN_ATOKEN) {
		Vector::borrow_mut(&mut gd.atoken_infos, idx).total_supply = value;
	    };
	    if(tidx == TOKEN_VARIABLE_DEBT) {
		Vector::borrow_mut(&mut gd.variable_debt_token_infos, idx).total_supply = value;
	    };
	    if(tidx == TOKEN_STABLE_DEBT) {
		Vector::borrow_mut(&mut gd.stable_debt_token_infos, idx).total_supply = value;
	    };
	}

	fun calc_stable_debt_token_total_supply(idx: u64, avgrate: u64) : u64 acquires GlobalData {
	    let gd = borrow_global_mut<GlobalData>(contract_address());
	    let timestamp = Vector::borrow(& gd.stable_debt_token_infos, idx).total_supply_timestamp;
	    
	    let principal = get_total_supply(idx, TOKEN_STABLE_DEBT);
	    let cumulated = math_utils_calculate_compounded_interest(avgrate, timestamp, DiemTimestamp::now_microseconds());
	    mantissa_mul(principal, cumulated)
	}
	
	// ================================================================================================
	
	public fun reserve_logic_get_normalized_income(reserve: &ReserveData) : u64 {
	    let timestamp =  reserve.last_update_timestamp;
	    let interest  = math_utils_calculate_linear_interest(reserve.current_liquidity_rate, timestamp);
	    let cumulated = mantissa_mul(reserve.liquidity_index, interest);
	    cumulated
	}

	public fun reserve_logic_get_normalized_debt(reserve: &ReserveData) : u64 {
	    let last_timestamp =  reserve.last_update_timestamp;
	    let curr_timestamp = DiemTimestamp::now_microseconds();
	    if(last_timestamp == curr_timestamp) {
		return reserve.variable_borrow_index
	    };
	    let interest = math_utils_calculate_compounded_interest(reserve.current_variable_borrow_rate, last_timestamp, curr_timestamp);
	    let cumulated = mantissa_mul(reserve.variable_borrow_index, interest);
	    cumulated
	}
	
	fun reserve_logic_update_state(reserve: &mut ReserveData) acquires GlobalData {
	    let scaled_var_debt: u64 = get_total_supply(reserve.id, TOKEN_VARIABLE_DEBT);
	    let prev_var_borrow_idx = reserve.variable_borrow_index;
	    let prev_liquidity_idx = reserve.liquidity_index;
	    let last_timestamp = reserve.last_update_timestamp;
	    
	    let (new_liquidity_idx, new_var_borrow_idx) = update_indexes(reserve, scaled_var_debt, prev_liquidity_idx, prev_var_borrow_idx, last_timestamp);
	    mint_to_treasury(reserve, scaled_var_debt, prev_var_borrow_idx, new_liquidity_idx, new_var_borrow_idx, last_timestamp);
	}

	fun update_indexes(reserve: &mut ReserveData,
			   scaled_var_debt: u64,
			   prev_liquidity_idx: u64,
			   prev_var_borrow_idx: u64,
			   last_timestamp: u64) : ( u64, u64) {
	    if(reserve.current_liquidity_rate > 0) {
		let cumulated = math_utils_calculate_linear_interest(reserve.current_liquidity_rate, last_timestamp);
		reserve.liquidity_index = mantissa_mul(prev_liquidity_idx, cumulated);
	    };

	    if(scaled_var_debt != 0) {
		let cumulated = math_utils_calculate_compounded_interest(reserve.current_variable_borrow_rate, last_timestamp, DiemTimestamp::now_microseconds());
		reserve.variable_borrow_index = mantissa_mul(prev_var_borrow_idx, cumulated);
	    };

	    reserve.last_update_timestamp = DiemTimestamp::now_microseconds();
	    (reserve.liquidity_index, reserve.variable_borrow_index) 
	}

	fun mint_to_treasury(_reserve: &ReserveData,
			     _scaled_var_debt: u64,
			     _prev_var_borrow_idx: u64,
			     _new_liquidity_idx: u64,
			     _new_var_borrow_idx: u64,
			     _last_timestamp: u64) {
	    
	}
	
	// ================================================================================================
	
	fun new_mantissa(a: u64, b: u64) : u64 {
	    let c = (a as u128) << 64;
	    let d = (b as u128) << 32;
	    let e = c / d;
	    //assert(e != 0 || a == 0, 101);
	    (e as u64)
	}
	
	fun mantissa_div(a: u64, b: u64) : u64 {
	    let c = (a as u128) << 32;
	    let d = c / (b as u128);
	    (d as u64)
	}

	fun mantissa_mul(a: u64, b: u64) : u64 {
	    let c = (a as u128) * (b as u128);
	    let d = c >> 32;
	    (d as u64)
	}

	fun safe_sub(a: u64, b: u64): u64 {
	    if(a < b) { 0 } else { a - b }
	}
	
	// ================================================================================================
	
	public fun math_utils_calculate_linear_interest(rate: u64, timestamp: u64) : u64 {
	    DiemTimestamp::now_microseconds()/(60*1000*1000);
	    let seconds = safe_sub(DiemTimestamp::now_microseconds(), timestamp)/(1000*1000);
	    let s = new_mantissa(seconds, SECONDS_PER_YEAR);
	    let r = mantissa_mul(rate, s);
	    r + MANTISSA_ONE
	}

	public fun math_utils_calculate_compounded_interest(rate: u64, last_timestamp: u64, curr_timestamp: u64) : u64 {
	    let exp = safe_sub(curr_timestamp, last_timestamp) / (1000*1000);
	    if (exp == 0) {
		return MANTISSA_ONE
	    };
	    
	    let exp1 = exp-1;
	    let exp2 = safe_sub(exp, 2);
	    let rate_persecond = rate / SECONDS_PER_YEAR;
	    let base_pow2 = mantissa_mul(rate_persecond, rate_persecond);
	    let base_pow3 = mantissa_mul(base_pow2, rate_persecond);
	    let term2 = exp*exp1*base_pow2/2;
	    let term3 = exp*exp1*exp2*base_pow3/6;
	    MANTISSA_ONE + rate_persecond*exp + term2 + term3
	}

	// ================================================================================================
	
    }
}

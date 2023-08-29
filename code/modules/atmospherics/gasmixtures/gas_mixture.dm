
GLOBAL_LIST_INIT(gaslist_cache, init_gaslist_cache())

/proc/init_gaslist_cache()
	var/list/gases = list()
	for(var/id in GLOB.gas_data.ids)
		var/list/cached_gas = new(3)

		gases[id] = cached_gas

		cached_gas[MOLES] = 0
		cached_gas[ARCHIVE] = 0
		cached_gas[GAS_META] = GLOB.gas_data.specific_heats[id]
	return gases


/*
What are the archived variables for?
	Calculations are done using the archived variables with the results merged into the regular variables.
	This prevents race conditions that arise based on the order of tile processing.
*/
#define QUANTIZE(variable)		(round(variable,0.0000001))/*I feel the need to document what happens here. Basically this is used to catch most rounding errors, however it's previous value made it so that
															once gases got hot enough, most procedures wouldnt occur due to the fact that the mole counts would get rounded away. Thus, we lowered it a few orders of magnititude */

/datum/gas_mixture
	var/list/gases
	var/temperature = 0 //kelvins
	var/tmp/temperature_archived = 0
	var/volume = CELL_VOLUME //liters
	var/last_share = 0
	var/list/reaction_results
	var/list/analyzer_results //used for analyzer feedback - not initialized until its used

/datum/gas_mixture/New(volume)
	gases = new
	if (!isnull(volume))
		src.volume = volume
	reaction_results = new

//listmos procs
//use the macros in performance intensive areas. for their definitions, refer to code/__DEFINES/atmospherics.dm

	//assert_gas(gas_id) - used to guarantee that the gas list for this id exists in gas_mixture.gases.
	//Must be used before adding to a gas. May be used before reading from a gas.
/datum/gas_mixture/proc/assert_gas(gas_id)
	ASSERT_GAS(gas_id, src)

	//assert_gases(args) - shorthand for calling ASSERT_GAS() once for each gas type.
/datum/gas_mixture/proc/assert_gases()
	for(var/id in args)
		ASSERT_GAS(id, src)

	//add_gas(gas_id) - similar to assert_gas(), but does not check for an existing
		//gas list for this id. This can clobber existing gases.
	//Used instead of assert_gas() when you know the gas does not exist. Faster than assert_gas().
/datum/gas_mixture/proc/add_gas(gas_id)
	ADD_GAS(gas_id, gases)

	//add_gases(args) - shorthand for calling add_gas() once for each gas_type.
/datum/gas_mixture/proc/add_gases()
	var/cached_gases = gases
	for(var/id in args)
		ADD_GAS(id, cached_gases)

	//garbage_collect() - removes any gas list which is empty.
	//If called with a list as an argument, only removes gas lists with IDs from that list.
	//Must be used after subtracting from a gas. Must be used after assert_gas()
		//if assert_gas() was called only to read from the gas.
	//By removing empty gases, processing speed is increased.
/datum/gas_mixture/proc/garbage_collect(list/tocheck)
	var/list/cached_gases = gases
	for(var/id in (tocheck || cached_gases))
		if(QUANTIZE(cached_gases[id][MOLES]) <= 0 && QUANTIZE(cached_gases[id][ARCHIVE]) <= 0)
			cached_gases -= id

	//PV = nRT

/datum/gas_mixture/proc/heat_capacity(data = MOLES) //joules per kelvin
	var/list/cached_gases = gases
	. = 0
	for(var/id in cached_gases)
		var/gas_data = cached_gases[id]
		. += gas_data[data] * gas_data[GAS_META]

/datum/gas_mixture/turf/heat_capacity()
	. = ..()
	if(!.)
		. += HEAT_CAPACITY_VACUUM //we want vacuums in turfs to have the same heat capacity as space

/datum/gas_mixture/proc/total_moles()
	var/cached_gases = gases
	TOTAL_MOLES(cached_gases, .)

/datum/gas_mixture/proc/return_pressure() //kilopascals
	if(volume > 0) // to prevent division by zero
		var/cached_gases = gases
		TOTAL_MOLES(cached_gases, .)
		. *= R_IDEAL_GAS_EQUATION * temperature / volume
		return
	return 0

/datum/gas_mixture/proc/return_temperature() //kelvins
	return temperature

/datum/gas_mixture/proc/return_volume() //liters
	return max(0, volume)

/datum/gas_mixture/proc/get_gases()
	return assoc_list_strip_value(gases)

/datum/gas_mixture/proc/set_volume(vol)
	volume = vol

/datum/gas_mixture/proc/adjust_moles(gastype, moles)
	ASSERT_GAS(gastype, src)
	gases[gastype][MOLES] += moles

/datum/gas_mixture/proc/set_moles(gastype, moles)
	ASSERT_GAS(gastype, src)
	gases[gastype][MOLES] = moles

/datum/gas_mixture/proc/get_moles(gastype)
	ASSERT_GAS(gastype, src)
	return gases[gastype][MOLES]

/datum/gas_mixture/proc/set_temperature(temperature)
	src.temperature = temperature

/datum/gas_mixture/proc/transfer_to(datum/gas_mixture/other, moles)
	other.merge(remove(moles))

/datum/gas_mixture/proc/adjust_heat(joules)
	var/cap = heat_capacity()
	temperature = ((cap * temperature) + joules) / cap

	return THERMAL_ENERGY(src) //see code/__DEFINES/atmospherics.dm; use the define in performance critical areas

/**
 * Counts how much pressure will there be if we impart MOLAR_ACCURACY amounts of our gas to the output gasmix.
 * We do all of this without actually transferring it so dont worry about it changing the gasmix.
 * Returns: Resulting pressure (number).
 * Args:
 * - output_air (gasmix).
 */
/datum/gas_mixture/proc/gas_pressure_minimum_transfer(datum/gas_mixture/output_air)
	var/resulting_energy = THERMAL_ENERGY(output_air) + (MOLAR_ACCURACY / total_moles() * THERMAL_ENERGY(src))
	var/resulting_capacity = output_air.heat_capacity() + (MOLAR_ACCURACY / total_moles() * heat_capacity())
	return (output_air.total_moles() + MOLAR_ACCURACY) * R_IDEAL_GAS_EQUATION * (resulting_energy / resulting_capacity) / output_air.return_volume()

/datum/gas_mixture/proc/scrub_into()
	return // TODO ATMOS

/datum/gas_mixture/proc/transfer_ratio_to()
	return // TODO ATMOS

/datum/gas_mixture/proc/remove_specific_ratio(gas_id, ratio)
	if(ratio <= 0)
		return null
	ratio = min(ratio, 1)

	var/list/cached_gases = gases
	var/datum/gas_mixture/removed = new type
	var/list/removed_gases = removed.gases //accessing datum vars is slower than proc vars

	removed.temperature = temperature
	ADD_GAS(gas_id, removed.gases)
	removed_gases[gas_id][MOLES] = QUANTIZE(cached_gases[gas_id][MOLES] * ratio)
	cached_gases[gas_id][MOLES] -= removed_gases[gas_id][MOLES]

	garbage_collect(list(gas_id))

	return removed

/** Returns the amount of gas to be pumped to a specific container.
 * Args:
 * - output_air. The gas mix we want to pump to.
 * - target_pressure. The target pressure we want.
 * - ignore_temperature. Returns a cheaper form of gas calculation, useful if the temperature difference between the two gasmixes is low or nonexistant.
 */
/datum/gas_mixture/proc/gas_pressure_calculate(datum/gas_mixture/output_air, target_pressure, ignore_temperature = FALSE)
	// So we dont need to iterate the gaslist multiple times.
	var/our_moles = total_moles()
	var/output_moles = output_air.total_moles()
	var/output_pressure = output_air.return_pressure()

	if(our_moles <= 0 || temperature <= 0)
		return FALSE

	var/pressure_delta = 0
	if(output_air.temperature <= 0 || output_moles <= 0)
		ignore_temperature = TRUE
		pressure_delta = target_pressure
	else
		pressure_delta = target_pressure - output_pressure

	if(pressure_delta < 0.01 || gas_pressure_minimum_transfer(output_air) > target_pressure)
		return FALSE

	if(ignore_temperature)
		return (pressure_delta*output_air.volume)/(temperature * R_IDEAL_GAS_EQUATION)

	// Lower and upper bound for the moles we must transfer to reach the pressure. The answer is bound to be here somewhere.
	var/pv = target_pressure * output_air.volume
	/// The PV/R part in the equation we will use later. Counted early because pv/(r*t) might not be equal to pv/r/t, messing our lower and upper limit.
	var/pvr = pv / R_IDEAL_GAS_EQUATION
	// These works by assuming our gas has extremely high heat capacity
	// and the resultant gasmix will hit either the highest or lowest temperature possible.

	/// This is the true lower limit, but numbers still can get lower than this due to floats.
	var/lower_limit = max((pvr / max(temperature, output_air.temperature)) - output_moles, 0)
	var/upper_limit = (pvr / min(temperature, output_air.temperature)) - output_moles // In theory this should never go below zero, the pressure_delta check above should account for this.

	lower_limit = max(lower_limit -  0.01, 0)
	upper_limit +=  0.01

	/*
	 * We have PV=nRT as a nice formula, we can rearrange it into nT = PV/R
	 * But now both n and T can change, since any incoming moles also change our temperature.
	 * So we need to unify both our n and T, somehow.
	 *
	 * We can rewrite T as (our old thermal energy + incoming thermal energy) divided by (our old heat capacity + incoming heat capacity)
	 * T = (W1 + n/N2 * W2) / (C1 + n/N2 * C2). C being heat capacity, W being work, N being total moles.
	 *
	 * In total we now have our equation be: (N1 + n) * (W1 + n/N2 * W2) / (C1 + n/N2 * C2) = PV/R
	 * Now you can rearrange this and find out that it's a quadratic equation and pretty much solvable with the formula. Will be a bit messy though.
	 *
	 * W2/N2n^2 +
	 * (N1*W2/N2)n + W1n - ((PV/R)*C2/N2)n +
	 * (-(PV/R)*C1) + N1W1 = 0
	 *
	 * We will represent each of these terms with A, B, and C. A for the n^2 part, B for the n^1 part, and C for the n^0 part.
	 * We then put this into the famous (-b +/- sqrt(b^2-4ac)) / 2a formula.
	 *
	 * Oh, and one more thing. By "our" we mean the gasmix in the argument. We are the incoming one here. We are number 2, target is number 1.
	 * If all this counting fucks up, we revert first to Newton's approximation, then the old simple formula.
	 */

	// Our thermal energy and moles
	var/w2 = THERMAL_ENERGY(src)
	var/n2 = our_moles
	var/c2 = heat_capacity()

	// Target thermal energy and moles
	var/w1 = THERMAL_ENERGY(output_air)
	var/n1 = output_moles
	var/c1 = output_air.heat_capacity()

	/// x^2 in the quadratic
	var/a_value = w2/n2
	/// x^1 in the quadratic
	var/b_value = ((n1*w2)/n2) + w1 - (pvr*c2/n2)
	/// x^0 in the quadratic
	var/c_value = (-1*pvr*c1) + n1 * w1

	. = gas_pressure_quadratic(a_value, b_value, c_value, lower_limit, upper_limit)
	if(.)
		return
	. = gas_pressure_approximate(a_value, b_value, c_value, lower_limit, upper_limit)
	if(.)
		return
	// Inaccurate and will probably explode but whatever.
	return (pressure_delta*output_air.volume)/(temperature * R_IDEAL_GAS_EQUATION)

/// Actually tries to solve the quadratic equation.
/// Do mind that the numbers can get very big and might hit BYOND's single point float limit.
/datum/gas_mixture/proc/gas_pressure_quadratic(a, b, c, lower_limit, upper_limit)
	var/solution
	if(IS_FINITE(a) && IS_FINITE(b) && IS_FINITE(c))
		solution = max(SolveQuadratic(a, b, c))
		if(solution > lower_limit && solution < upper_limit) //SolveQuadratic can return empty lists so be careful here
			return solution
	stack_trace("Failed to solve pressure quadratic equation. A: [a]. B: [b]. C:[c]. Current value = [solution]. Expected lower limit: [lower_limit]. Expected upper limit: [upper_limit].")
	return FALSE

/// Approximation of the quadratic equation using Newton-Raphson's Method.
/// We use the slope of an approximate value to get closer to the root of a given equation.
/datum/gas_mixture/proc/gas_pressure_approximate(a, b, c, lower_limit, upper_limit)
	var/solution
	if(IS_FINITE(a) && IS_FINITE(b) && IS_FINITE(c))
		// We start at the extrema of the equation, added by a number.
		// This way we will hopefully always converge on the positive root, while starting at a reasonable number.
		solution = (-b / (2 * a)) + 200
		for (var/iteration in 1 to 20)
			var/diff = (a*solution**2 + b*solution + c) / (2*a*solution + b) // f(sol) / f'(sol)
			solution -= diff // xn+1 = xn - f(sol) / f'(sol)
			if(abs(diff) < MOLAR_ACCURACY && (solution > lower_limit) && (solution < upper_limit))
				return solution
	stack_trace("Newton's Approximation for pressure failed after 20 iterations. A: [a]. B: [b]. C:[c]. Current value: [solution]. Expected lower limit: [lower_limit]. Expected upper limit: [upper_limit].")
	return FALSE

/datum/gas_mixture/proc/remove_specific(gas_id, amount)
	var/list/cached_gases = gases
	amount = min(amount, cached_gases[gas_id][MOLES])
	if(amount <= 0)
		return null
	var/datum/gas_mixture/removed = new type
	var/list/removed_gases = removed.get_gases()
	removed.temperature = return_temperature()
	ADD_GAS(gas_id, removed.gases)
	removed_gases[gas_id][MOLES] = amount
	cached_gases[gas_id][MOLES] -= amount

	garbage_collect(list(gas_id))
	return removed

/proc/equalize_all_gases_in_list()
	return // TODO ATMOS

/datum/gas_mixture/proc/multiply()
	return // TODO ATMOS

/datum/gas_mixture/proc/clear()
	return // TODO ATMOS

/datum/gas_mixture/proc/archive()
	//Update archived versions of variables
	//Returns: 1 in all cases

/datum/gas_mixture/proc/merge(datum/gas_mixture/giver)
	//Merges all air from giver into self. Does NOT delete the giver.
	//Returns: 1 if we are mutable, 0 otherwise

/datum/gas_mixture/proc/remove(amount)
	//Proportionally removes amount of gas from the gas_mixture
	//Returns: gas_mixture with the gases removed

/datum/gas_mixture/proc/remove_ratio(ratio)
	//Proportionally removes amount of gas from the gas_mixture
	//Returns: gas_mixture with the gases removed

/datum/gas_mixture/proc/copy()
	//Creates new, identical gas mixture
	//Returns: duplicate gas mixture

/datum/gas_mixture/proc/copy_from(datum/gas_mixture/sample)
	//Copies variables from sample
	//Returns: 1 if we are mutable, 0 otherwise

/datum/gas_mixture/proc/copy_from_turf(turf/model)
	//Copies all gas info from the turf into the gas list along with temperature
	//Returns: 1 if we are mutable, 0 otherwise

/datum/gas_mixture/proc/parse_gas_string(gas_string)
	//Copies variables from a particularly formatted string.
	//Returns: 1 if we are mutable, 0 otherwise

/datum/gas_mixture/proc/share(datum/gas_mixture/sharer)
	//Performs air sharing calculations between two gas_mixtures assuming only 1 boundary length
	//Returns: amount of gas exchanged (+ if sharer received)

/datum/gas_mixture/proc/after_share(datum/gas_mixture/sharer)
	//called on share's sharer to let it know it just got some gases

/datum/gas_mixture/proc/temperature_share(datum/gas_mixture/sharer, conduction_coefficient)
	//Performs temperature sharing calculations (via conduction) between two gas_mixtures assuming only 1 boundary length
	//Returns: new temperature of the sharer

/datum/gas_mixture/proc/compare(datum/gas_mixture/sample)
	//Compares sample to self to see if within acceptable ranges that group processing may be enabled
	//Returns: a string indicating what check failed, or "" if check passes

/datum/gas_mixture/proc/react(turf/open/dump_location)
	//Performs various reactions such as combustion or fusion (LOL)
	//Returns: 1 if any reaction took place; 0 otherwise

/datum/gas_mixture/archive()
	var/list/cached_gases = gases
	temperature_archived = temperature
	for(var/id in cached_gases)
		cached_gases[id][ARCHIVE] = cached_gases[id][MOLES]
	return 1

/datum/gas_mixture/merge(datum/gas_mixture/giver)
	if(!giver)
		return 0

	//heat transfer
	if(abs(temperature - giver.temperature) > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
		var/self_heat_capacity = heat_capacity()
		var/giver_heat_capacity = giver.heat_capacity()
		var/combined_heat_capacity = giver_heat_capacity + self_heat_capacity
		if(combined_heat_capacity)
			temperature = (giver.temperature * giver_heat_capacity + temperature * self_heat_capacity) / combined_heat_capacity

	var/list/cached_gases = gases //accessing datum vars is slower than proc vars
	var/list/giver_gases = giver.gases
	//gas transfer
	for(var/giver_id in giver_gases)
		ASSERT_GAS(giver_id, src)
		cached_gases[giver_id][MOLES] += giver_gases[giver_id][MOLES]

	return 1

/datum/gas_mixture/remove(amount)
	var/sum
	var/list/cached_gases = gases
	TOTAL_MOLES(cached_gases, sum)
	amount = min(amount, sum) //Can not take more air than tile has!
	if(amount <= 0)
		return null
	var/datum/gas_mixture/removed = new type
	var/list/removed_gases = removed.gases //accessing datum vars is slower than proc vars

	removed.temperature = temperature
	for(var/id in cached_gases)
		ADD_GAS(id, removed.gases)
		removed_gases[id][MOLES] = QUANTIZE((cached_gases[id][MOLES] / sum) * amount)
		cached_gases[id][MOLES] -= removed_gases[id][MOLES]
	garbage_collect()

	return removed

/datum/gas_mixture/remove_ratio(ratio)
	if(ratio <= 0)
		return null
	ratio = min(ratio, 1)

	var/list/cached_gases = gases
	var/datum/gas_mixture/removed = new type
	var/list/removed_gases = removed.gases //accessing datum vars is slower than proc vars

	removed.temperature = temperature
	for(var/id in cached_gases)
		ADD_GAS(id, removed.gases)
		removed_gases[id][MOLES] = QUANTIZE(cached_gases[id][MOLES] * ratio)
		cached_gases[id][MOLES] -= removed_gases[id][MOLES]

	garbage_collect()

	return removed

/datum/gas_mixture/copy()
	var/list/cached_gases = gases
	var/datum/gas_mixture/copy = new type
	var/list/copy_gases = copy.gases

	copy.temperature = temperature
	for(var/id in cached_gases)
		ADD_GAS(id, copy.gases)
		copy_gases[id][MOLES] = cached_gases[id][MOLES]

	return copy

/datum/gas_mixture/copy_from(datum/gas_mixture/sample)
	var/list/cached_gases = gases //accessing datum vars is slower than proc vars
	var/list/sample_gases = sample.gases

	temperature = sample.temperature
	for(var/id in sample_gases)
		ASSERT_GAS(id,src)
		cached_gases[id][MOLES] = sample_gases[id][MOLES]

	//remove all gases not in the sample
	cached_gases &= sample_gases

	return 1

/datum/gas_mixture/copy_from_turf(turf/model)
	parse_gas_string(model.initial_gas_mix)
	//acounts for changes in temperature
	var/turf/model_parent = model.parent_type
	if(model.temperature != initial(model.temperature) || model.temperature != initial(model_parent.temperature))
		temperature = model.temperature

	return 1

/datum/gas_mixture/parse_gas_string(gas_string)
	var/list/gases = src.gases
	var/list/gas = params2list(gas_string)
	if(gas["TEMP"])
		temperature = text2num(gas["TEMP"])
		gas -= "TEMP"
	gases.Cut()
	for(var/id in gas)
		ADD_GAS(id, gases)
		gases[id][MOLES] = text2num(gas[id])
	return 1

/datum/gas_mixture/share(datum/gas_mixture/sharer, atmos_adjacent_turfs = 4)

	var/list/cached_gases = gases
	var/list/sharer_gases = sharer.gases

	var/temperature_delta = temperature_archived - sharer.temperature_archived
	var/abs_temperature_delta = abs(temperature_delta)

	var/old_self_heat_capacity = 0
	var/old_sharer_heat_capacity = 0
	if(abs_temperature_delta > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
		old_self_heat_capacity = heat_capacity()
		old_sharer_heat_capacity = sharer.heat_capacity()

	var/heat_capacity_self_to_sharer = 0 //heat capacity of the moles transferred from us to the sharer
	var/heat_capacity_sharer_to_self = 0 //heat capacity of the moles transferred from the sharer to us

	var/moved_moles = 0
	var/abs_moved_moles = 0

	//GAS TRANSFER
	for(var/id in sharer_gases - cached_gases) // create gases not in our cache
		ADD_GAS(id, gases)
	for(var/id in cached_gases) // transfer gases
		ASSERT_GAS(id, sharer)

		var/gas = cached_gases[id]
		var/sharergas = sharer_gases[id]

		var/delta = QUANTIZE(gas[ARCHIVE] - sharergas[ARCHIVE])/(atmos_adjacent_turfs+1) //the amount of gas that gets moved between the mixtures

		if(delta && abs_temperature_delta > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
			var/gas_heat_capacity = delta * gas[GAS_META]
			if(delta > 0)
				heat_capacity_self_to_sharer += gas_heat_capacity
			else
				heat_capacity_sharer_to_self -= gas_heat_capacity //subtract here instead of adding the absolute value because we know that delta is negative.

		gas[MOLES]			-= delta
		sharergas[MOLES]	+= delta
		moved_moles			+= delta
		abs_moved_moles		+= abs(delta)

	last_share = abs_moved_moles

	//THERMAL ENERGY TRANSFER
	if(abs_temperature_delta > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
		var/new_self_heat_capacity = old_self_heat_capacity + heat_capacity_sharer_to_self - heat_capacity_self_to_sharer
		var/new_sharer_heat_capacity = old_sharer_heat_capacity + heat_capacity_self_to_sharer - heat_capacity_sharer_to_self

		//transfer of thermal energy (via changed heat capacity) between self and sharer
		if(new_self_heat_capacity > MINIMUM_HEAT_CAPACITY)
			temperature = (old_self_heat_capacity*temperature - heat_capacity_self_to_sharer*temperature_archived + heat_capacity_sharer_to_self*sharer.temperature_archived)/new_self_heat_capacity

		if(new_sharer_heat_capacity > MINIMUM_HEAT_CAPACITY)
			sharer.temperature = (old_sharer_heat_capacity*sharer.temperature-heat_capacity_sharer_to_self*sharer.temperature_archived + heat_capacity_self_to_sharer*temperature_archived)/new_sharer_heat_capacity
		//thermal energy of the system (self and sharer) is unchanged

			if(abs(old_sharer_heat_capacity) > MINIMUM_HEAT_CAPACITY)
				if(abs(new_sharer_heat_capacity/old_sharer_heat_capacity - 1) < 0.1) // <10% change in sharer heat capacity
					temperature_share(sharer, OPEN_HEAT_TRANSFER_COEFFICIENT)

	if(length(cached_gases ^ sharer_gases)) //if all gases were present in both mixtures, we know that no gases are 0
		garbage_collect(cached_gases - sharer_gases) //any gases the sharer had, we are guaranteed to have. gases that it didn't have we are not.
		sharer.garbage_collect(sharer_gases - cached_gases) //the reverse is equally true
	sharer.after_share(src, atmos_adjacent_turfs)
	if(temperature_delta > MINIMUM_TEMPERATURE_TO_MOVE || abs(moved_moles) > MINIMUM_MOLES_DELTA_TO_MOVE)
		var/our_moles
		TOTAL_MOLES(cached_gases,our_moles)
		var/their_moles
		TOTAL_MOLES(sharer_gases,their_moles)
		return (temperature_archived*(our_moles + moved_moles) - sharer.temperature_archived*(their_moles - moved_moles)) * R_IDEAL_GAS_EQUATION / volume

/datum/gas_mixture/after_share(datum/gas_mixture/sharer, atmos_adjacent_turfs = 4)
	return

/datum/gas_mixture/temperature_share(datum/gas_mixture/sharer, conduction_coefficient, sharer_temperature, sharer_heat_capacity)
	//transfer of thermal energy (via conduction) between self and sharer
	if(sharer)
		sharer_temperature = sharer.temperature_archived
	var/temperature_delta = temperature_archived - sharer_temperature
	if(abs(temperature_delta) > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
		var/self_heat_capacity = heat_capacity(ARCHIVE)
		sharer_heat_capacity = sharer_heat_capacity || sharer.heat_capacity(ARCHIVE)

		if((sharer_heat_capacity > MINIMUM_HEAT_CAPACITY) && (self_heat_capacity > MINIMUM_HEAT_CAPACITY))
			var/heat = conduction_coefficient*temperature_delta* \
				(self_heat_capacity*sharer_heat_capacity/(self_heat_capacity+sharer_heat_capacity))

			temperature = max(temperature - heat/self_heat_capacity, TCMB)
			sharer_temperature = max(sharer_temperature + heat/sharer_heat_capacity, TCMB)
			if(sharer)
				sharer.temperature = sharer_temperature
	return sharer_temperature
	//thermal energy of the system (self and sharer) is unchanged

/datum/gas_mixture/compare(datum/gas_mixture/sample)
	var/list/sample_gases = sample.gases //accessing datum vars is slower than proc vars
	var/list/cached_gases = gases

	for(var/id in cached_gases | sample_gases) // compare gases from either mixture
		var/gas_moles = cached_gases[id]
		gas_moles = gas_moles ? gas_moles[MOLES] : 0
		var/sample_moles = sample_gases[id]
		sample_moles = sample_moles ? sample_moles[MOLES] : 0
		var/delta = abs(gas_moles - sample_moles)
		if(delta > MINIMUM_MOLES_DELTA_TO_MOVE && \
			delta > gas_moles * MINIMUM_AIR_RATIO_TO_MOVE)
			return id

	var/our_moles
	TOTAL_MOLES(cached_gases, our_moles)
	if(our_moles > MINIMUM_MOLES_DELTA_TO_MOVE)
		var/temp = temperature
		var/sample_temp = sample.temperature

		var/temperature_delta = abs(temp - sample_temp)
		if(temperature_delta > MINIMUM_TEMPERATURE_DELTA_TO_SUSPEND)
			return "temp"

	return ""

/datum/gas_mixture/react(datum/holder)
	. = NO_REACTION
	var/list/cached_gases = gases
	if(!cached_gases.len)
		return
	var/possible
	for(var/I in cached_gases)
		if(GLOB.nonreactive_gases[I])
			continue
		possible = TRUE
		break
	if(!possible)
		return
	reaction_results = new
	var/temp = temperature
	var/ener = THERMAL_ENERGY(src)

	reaction_loop:
		for(var/r in SSair.gas_reactions)
			var/datum/gas_reaction/reaction = r

			var/list/min_reqs = reaction.min_requirements
			if((min_reqs["TEMP"] && temp < min_reqs["TEMP"]) \
			|| (min_reqs["ENER"] && ener < min_reqs["ENER"]))
				continue

			for(var/id in min_reqs)
				if (id == "TEMP" || id == "ENER")
					continue
				if(!cached_gases[id] || cached_gases[id][MOLES] < min_reqs[id])
					continue reaction_loop
			//at this point, all minimum requirements for the reaction are satisfied.

			/*	currently no reactions have maximum requirements, so we can leave the checks commented out for a slight performance boost
				PLEASE DO NOT REMOVE THIS CODE. the commenting is here only for a performance increase.
				enabling these checks should be as easy as possible and the fact that they are disabled should be as clear as possible
			var/list/max_reqs = reaction.max_requirements.Copy()
			if((max_reqs["TEMP"] && temp > max_reqs["TEMP"]) \
			|| (max_reqs["ENER"] && ener > max_reqs["ENER"]))
				continue
			max_reqs -= "TEMP"
			max_reqs -= "ENER"
			for(var/id in max_reqs)
				if(cached_gases[id] && cached_gases[id][MOLES] > max_reqs[id])
					continue reaction_loop
			//at this point, all requirements for the reaction are satisfied. we can now react()
			*/

			. |= reaction.react(src, holder)
			if (. & STOP_REACTIONS)
				break
	if(.)
		garbage_collect()
		if(temperature < TCMB) //just for safety
			temperature = TCMB

//Takes the amount of the gas you want to PP as an argument
//So I don't have to do some hacky switches/defines/magic strings
//eg:
//Tox_PP = get_partial_pressure(gas_mixture.toxins)
//O2_PP = get_partial_pressure(gas_mixture.oxygen)

/datum/gas_mixture/proc/get_breath_partial_pressure(gas_pressure)
	return (gas_pressure * R_IDEAL_GAS_EQUATION * temperature) / BREATH_VOLUME
//inverse
/datum/gas_mixture/proc/get_true_breath_pressure(partial_pressure)
	return (partial_pressure * BREATH_VOLUME) / (R_IDEAL_GAS_EQUATION * temperature)

//Mathematical proofs:
/*
get_breath_partial_pressure(gas_pp) --> gas_pp/total_moles()*breath_pp = pp
get_true_breath_pressure(pp) --> gas_pp = pp/breath_pp*total_moles()

10/20*5 = 2.5
10 = 2.5/5*20
*/
/// Pumps gas from src to output_air. Amount depends on target_pressure
/datum/gas_mixture/proc/pump_gas_to(datum/gas_mixture/output_air, target_pressure, specific_gas = null)
	var/temperature_delta = abs(temperature - output_air.temperature)
	var/datum/gas_mixture/removed
	var/transfer_moles

	if(specific_gas)
		// This is necessary because the specific heat capacity of a gas might be different from our gasmix.
		var/datum/gas_mixture/temporary = remove_specific_ratio(specific_gas, 1)
		transfer_moles = temporary.gas_pressure_calculate(output_air, target_pressure, temperature_delta <= 5)
		removed = temporary.remove_specific(specific_gas, transfer_moles)
		merge(temporary)
	else
		transfer_moles = gas_pressure_calculate(output_air, target_pressure, temperature_delta <= 5)
		removed = remove(transfer_moles)

	if(!removed)
		return FALSE

	output_air.merge(removed)
	return removed

/// Releases gas from src to output air. This means that it can not transfer air to gas mixture with higher pressure.
/datum/gas_mixture/proc/release_gas_to(datum/gas_mixture/output_air, target_pressure, rate=1)
	var/output_starting_pressure = output_air.return_pressure()
	var/input_starting_pressure = return_pressure()

	//Need at least 10 KPa difference to overcome friction in the mechanism
	if(output_starting_pressure >= min(target_pressure,input_starting_pressure-10))
		return FALSE

	//Can not have a pressure delta that would cause output_pressure > input_pressure
	target_pressure = output_starting_pressure + min(target_pressure - output_starting_pressure, (input_starting_pressure - output_starting_pressure)/2)
	var/temperature_delta = abs(temperature - output_air.temperature)

	var/transfer_moles = gas_pressure_calculate(output_air, target_pressure, temperature_delta <= 5)

	//Actually transfer the gas
	var/datum/gas_mixture/removed = remove(transfer_moles * rate)

	if(!removed)
		return FALSE

	output_air.merge(removed)
	return TRUE

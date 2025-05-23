class_name PokerHands extends Node

enum HandTypes {
	ROYAL_FLUSH,     # A, K, Q, J, 10 of same suit
	STRAIGHT_FLUSH,  # Five cards in sequence of same suit
	FOUR_OF_A_KIND,  # Four cards of same rank
	FULL_HOUSE,      # Three of a kind plus a pair
	FLUSH,          # Five cards of same suit
	STRAIGHT,       # Five cards in sequence
	THREE_OF_A_KIND, # Three cards of same rank
	TWO_PAIR,       # Two different pairs
	ONE_PAIR,       # One pair
	HIGH_CARD       # Highest card
}

# Constants for card representation
const CARDS_IN_DECK: int = 52
const CARDS_IN_HAND: int = 5
const RANKS_IN_SUIT: int = 13

var monte_godot: MonteGodot
# Ensure this path points to your actual JobConfig resource for poker hands
var poker_hands_job = preload("res://examples/poker_hands/poker_hands_job.tres") 

func _ready() -> void:
	monte_godot = MonteGodot.new()
	monte_godot.all_jobs_completed.connect(_final_post_process)
	print("Starting poker hand simulation via MonteGodot job system...")
	_start_simulation()

func _start_simulation() -> void:
	# Make sure the callables are correctly assigned
	poker_hands_job.preprocess_callable = Callable(self, "_poker_hands_preprocess")
	poker_hands_job.run_callable = Callable(self, "_poker_hands_run")
	poker_hands_job.postprocess_callable = Callable(self, "_poker_hands_postprocess")
	
	var job_array: Array[JobConfig] = [poker_hands_job]
	monte_godot.run_simulations(job_array)

func _poker_hands_preprocess(case_data: Case) -> Array[int]:
	var cards_to_evaluate: Array[int] = []
	# Get the InVal by index, assuming the CardSampler InVar is the first (or only) one in the job config
	var drawn_cards_inval: InVal = case_data.get_input_value(0) 

	if drawn_cards_inval == null:
		push_error("PokerHands preprocess: InVal at index 0 is null. Check InVar setup in JobConfig and if InVar.get_value() returned null.")
		# cards_to_evaluate remains empty, will be handled in _run
	elif not drawn_cards_inval.raw_value is Array:
		push_error("PokerHands preprocess: InVal.raw_value from InVal at index 0 is not an Array. Value: %s" % str(drawn_cards_inval.raw_value))
		# cards_to_evaluate remains empty
	else:
		cards_to_evaluate = drawn_cards_inval.raw_value

	# You could also access drawn_cards_inval.mapped_val if you wanted the card names (e.g., ["2C", "KD"])
	# print("Preprocess: Case %d, Raw Card Indices: %s, Mapped Cards: %s" % [case_data.case_id, str(drawn_cards_inval.raw_value), str(drawn_cards_inval.mapped_value)])
	return cards_to_evaluate

func _poker_hands_run(cards_array: Array[int]) -> Array[PokerHands.HandTypes]:
	var hand_type_result: PokerHands.HandTypes = HandTypes.HIGH_CARD # Default
	var error_message: String = ""

	if cards_array.is_empty():
		push_error("PokerHands run: Invalid or empty card data received. Evaluating as HIGH_CARD.")
		return []
	
	if cards_array.size() != CARDS_IN_HAND:
		push_error("PokerHands run: Incorrect number of cards (%d) received. Expected %d." % [cards_array.size(), CARDS_IN_HAND])
		return []

	hand_type_result = PokerHandEvaluator.evaluate_hand(cards_array)
	return [hand_type_result]

func _poker_hands_postprocess(case_data: Case, hand_types: Array[PokerHands.HandTypes]) -> void:
	var hand_type_to_log: PokerHands.HandTypes = HandTypes.HIGH_CARD # Default
	var error_message: String = ""

	if hand_types.is_empty():
		push_error("Case %d: Empty run_output received by postprocess." % case_data.case_id)
		return
	else:
		if hand_types[0] is PokerHands.HandTypes:
			hand_type_to_log = hand_types[0]
		else:
			push_warning("Case %d: First element of run_output in postprocess is not HandTypes. Value: %s" % [case_data.case_id, str(hand_types[0])])
		

	# Create an OutVal. For simple enum/int output, raw_val and mapped_val can be the same.
	# The OutVal constructor is OutVal.new(p_name: String, p_raw_val: Variant, p_mapped_val: Variant = null, p_metadata: Dictionary = {})
	# We need a name for the OutVar implicitly created. Let's use "HandTypeResult".
	var out_val_instance = OutVal.new("HandTypeResult", hand_type_to_log, hand_type_to_log)
	case_data.add_output_value(out_val_instance)

func _final_post_process(all_job_results: Dictionary) -> void:
	print("\n--- Poker Hand Simulation Results ---")
	var hand_counts: Dictionary = {}
	for hand_type_enum_value_init in HandTypes.values():
		hand_counts[hand_type_enum_value_init] = 0

	var total_valid_hands_counted: int = 0

	# Get results for the specific poker job
	if not all_job_results.has(poker_hands_job.job_name):
		print("ERROR: Results for job '%s' not found in all_job_results." % poker_hands_job.job_name)
		return
	
	var poker_job_data: Dictionary = all_job_results[poker_hands_job.job_name]
	# The structure from MonteGodot signal all_jobs_completed is:
	# { "job_name": {"results": Array[Case], "stats": Dictionary, "output_vars": Dictionary} }
	# We need the "results" array which contains the Case objects.
	if not poker_job_data.has("results"):
		print("ERROR: 'results' array (of Case objects) not found in data for job '%s'." % poker_hands_job.job_name)
		return

	var case_results_array: Array = poker_job_data["results"] # This should be Array[Case]
	
	print("DEBUG: poker_hands_job.n_cases (from JobConfig): %d" % poker_hands_job.n_cases)
	print("DEBUG: case_results_array.size() (received in _final_post_process): %d" % case_results_array.size())


	if not case_results_array is Array:
		push_error("ERROR: 'results' for job '%s' is not an Array. Type: %s" % [poker_hands_job.job_name, typeof(case_results_array)])
		return
	
	if case_results_array.is_empty():
		print("No cases were processed or returned for job: '%s'" % poker_hands_job.job_name)
		return

	const HAND_TYPE_OUTVAL_NAME: StringName = &"HandTypeResult"

	for case_object in case_results_array:
		if not case_object is Case:
			push_warning("Item in results array is not a Case object for job '%s'. Skipping." % poker_hands_job.job_name)
			continue

		var output_values_from_case: Array[OutVal] = case_object.get_output_values()
		var found_hand_type_outval: bool = false
		for out_val_instance in output_values_from_case:
			if out_val_instance.name == HAND_TYPE_OUTVAL_NAME:
				found_hand_type_outval = true
				var hand_type_val: Variant = out_val_instance.get_value() # Or get_raw_data() if that's more appropriate

				if hand_type_val is PokerHands.HandTypes:
					if hand_counts.has(hand_type_val):
						hand_counts[hand_type_val] += 1
						total_valid_hands_counted += 1
				elif hand_type_val is int and HandTypes.values().has(hand_type_val):
					var enum_key_from_int = HandTypes.values()[hand_type_val]
					if hand_counts.has(enum_key_from_int):
						hand_counts[enum_key_from_int] += 1
						total_valid_hands_counted += 1
				else:
					push_warning("Case %d: OutVal '%s' had unexpected value type: %s, value: %s" % [case_object.id, HAND_TYPE_OUTVAL_NAME, typeof(hand_type_val), str(hand_type_val)])
				break # Found the OutVal we care about for this case
		
		if not found_hand_type_outval:
			push_warning("Case %d: Did not find OutVal with name '%s'." % [case_object.id, HAND_TYPE_OUTVAL_NAME])


	if total_valid_hands_counted == 0:
		print("No valid poker hands were successfully processed and counted from OutVar data.")
		return

	print("Total Valid Hands Counted: %d" % total_valid_hands_counted)
	for hand_type_enum_value_display in HandTypes.values(): 
		var hand_name: String = HandTypes.keys()[hand_type_enum_value_display] 
		var count: int = hand_counts.get(hand_type_enum_value_display, 0) 
		var percentage: float = 0.0
		if total_valid_hands_counted > 0:
			percentage = (float(count) / total_valid_hands_counted) * 100.0
		
		var one_in_x_str: String = ""
		if count > 0 and total_valid_hands_counted > 0:
			var one_in_x_val: float = float(total_valid_hands_counted) / count
			if one_in_x_val >= 1.0:
				one_in_x_str = " (1 in %.0f)" % one_in_x_val
			else: # Should ideally not happen if count <= total_valid_hands_counted
				one_in_x_str = " (High Frequency)" 
		elif count == 0:
			one_in_x_str = " (0)"

		print("%s: %d (%.4f%%%s)" % [hand_name, count, percentage, one_in_x_str])
	
	print("------------------------------------")
	get_tree().quit()

# --- Static Hand Evaluation Logic (Copied from previous version, now namespaced) ---
# We should consider moving this to its own PokerHandEvaluator.gd script/class resource
# to keep this file focused on the MonteGodot job setup.
class PokerHandEvaluator:
	static func card_to_rank_and_suit(card_index: int) -> Dictionary:
		var rank = card_index % PokerHands.RANKS_IN_SUIT
		var suit = card_index / PokerHands.RANKS_IN_SUIT
		return {"rank": rank, "suit": suit}

	static func _count_ranks(ranks: Array[int]) -> Dictionary:
		var rank_counts: Dictionary = {}
		for rank in ranks:
			if not rank_counts.has(rank):
				rank_counts[rank] = 0
			rank_counts[rank] += 1
		return rank_counts

	static func _is_same_suit(suits: Array[int]) -> bool:
		if suits.is_empty(): return false
		var first_suit = suits[0]
		for suit in suits:
			if suit != first_suit:
				return false
		return true

	static func _is_straight(ranks: Array[int]) -> bool:
		if ranks.size() != PokerHands.CARDS_IN_HAND: return false # Ensure 5 cards for a poker straight
		var sorted_ranks = ranks.duplicate()
		sorted_ranks.sort()
		# Remove duplicates for straight check (e.g. [7,7,8,9,10] is not a straight)
		var unique_ranks: Array[int] = []
		if not sorted_ranks.is_empty():
			unique_ranks.append(sorted_ranks[0])
			for i in range(1, sorted_ranks.size()):
				if sorted_ranks[i] != sorted_ranks[i-1]:
					unique_ranks.append(sorted_ranks[i])
		
		if unique_ranks.size() < PokerHands.CARDS_IN_HAND : # Must be 5 unique ranks for a straight if original hand had pairs etc.
			#This check is more nuanced. A hand like [2,2,3,4,5] is not a straight.
			#If the original hand has pairs, it can't be a straight of 5 unique cards.
			#The card evaluation logic calls this on the 5 cards given, so if there are pairs, it won't be a straight.
			#This unique_ranks check is more for a generic "is there a 5-card straight within these N unique ranks"
			#For 5 cards, if unique_ranks.size() < 5, it implies pairs, so not a 5-card straight.
			if ranks.size() == PokerHands.CARDS_IN_HAND and unique_ranks.size() < PokerHands.CARDS_IN_HAND:
				return false


		# Check for Ace-low straight (A,2,3,4,5) -> (0,1,2,3,12) after sorting
		# Ranks: 0(2), 1(3), 2(4), 3(5), 4(6), 5(7), 6(8), 7(9), 8(T), 9(J), 10(Q), 11(K), 12(A)
		var is_ace_low_straight = true
		var ace_low_pattern = [0,1,2,3,12] # 2,3,4,5,A
		if unique_ranks.size() == PokerHands.CARDS_IN_HAND: # Must be 5 unique ranks
			for i in range(PokerHands.CARDS_IN_HAND):
				if unique_ranks[i] != ace_low_pattern[i]:
					is_ace_low_straight = false
					break
			if is_ace_low_straight: return true
		
		# Check for regular straight
		if unique_ranks.size() < PokerHands.CARDS_IN_HAND: return false # Not enough unique cards for a 5-card straight

		for i in range(1, unique_ranks.size()):
			if unique_ranks[i] != unique_ranks[i-1] + 1:
				# If we are checking exactly 5 cards, and they are not ace-low, then this means no straight
				if ranks.size() == PokerHands.CARDS_IN_HAND and unique_ranks.size() == PokerHands.CARDS_IN_HAND: # check for 5 distinct cards
					return false 
				# If we are checking more than 5 cards (e.g. 7 cards for Texas Hold'em best hand)
				# then we need to see if a subsequence of 5 cards forms a straight.
				# This simple loop isn't enough for that more complex case.
				# However, for this 5-card evaluator, this is sufficient.
		# If we check 5 unique cards and the ace-low failed, and they are sequential, it's a straight.
		# e.g. unique_ranks = [8,9,10,11,12] (T,J,Q,K,A)
		# e.g. unique_ranks = [0,1,2,3,4] (2,3,4,5,6)
		if unique_ranks.size() == PokerHands.CARDS_IN_HAND: # Only true if 5 unique sequential cards
			return true
		
		return false # Default for other cases (e.g. < 5 unique cards)


	static func _is_royal_flush(ranks: Array[int], suits: Array[int]) -> bool:
		if not _is_same_suit(suits):
			return false
		var sorted_ranks = ranks.duplicate()
		sorted_ranks.sort()
		# Ace, King, Queen, Jack, Ten
		var required_ranks = [PokerHands.RANKS_IN_SUIT - 5, PokerHands.RANKS_IN_SUIT - 4, PokerHands.RANKS_IN_SUIT - 3, PokerHands.RANKS_IN_SUIT - 2, PokerHands.RANKS_IN_SUIT - 1] 
		# Corrected: Ranks are 0-12. 10,J,Q,K,A are 8,9,10,11,12
		required_ranks = [8,9,10,11,12]
		return sorted_ranks == required_ranks

	static func _is_straight_flush(ranks: Array[int], suits: Array[int]) -> bool:
		return _is_same_suit(suits) and _is_straight(ranks)

	static func _is_four_of_a_kind(ranks: Array[int]) -> bool:
		var rank_counts = _count_ranks(ranks)
		return rank_counts.values().has(4)

	static func _is_full_house(ranks: Array[int]) -> bool:
		var rank_counts = _count_ranks(ranks)
		return rank_counts.values().has(3) and rank_counts.values().has(2)

	static func _is_flush(suits: Array[int]) -> bool:
		return _is_same_suit(suits)

	static func _is_three_of_a_kind(ranks: Array[int]) -> bool:
		var rank_counts = _count_ranks(ranks)
		# Must not also be a full house (which is better) or four of a kind
		if rank_counts.values().has(3) and not rank_counts.values().has(2) and not rank_counts.values().has(4):
			return true
		return false
		
	static func _is_two_pair(ranks: Array[int]) -> bool:
		var rank_counts = _count_ranks(ranks)
		var pair_count = 0
		for count in rank_counts.values():
			if count == 2:
				pair_count += 1
		return pair_count == 2

	static func _is_one_pair(ranks: Array[int]) -> bool:
		var rank_counts = _count_ranks(ranks)
		# Must be exactly one pair, and no three_of_a_kind (which would make it a full house or just three_of_a_kind)
		var pair_count = 0
		var has_three_of_a_kind = false
		for count in rank_counts.values():
			if count == 2:
				pair_count +=1
			if count == 3:
				has_three_of_a_kind = true
		
		return pair_count == 1 and not has_three_of_a_kind and not rank_counts.values().has(4)


	static func evaluate_hand(card_indices: Array[int]) -> PokerHands.HandTypes:
		if card_indices.size() != PokerHands.CARDS_IN_HAND:
			return PokerHands.HandTypes.HIGH_CARD
			
		var ranks: Array[int] = []
		var suits: Array[int] = []
		for card_idx in card_indices:
			var card_info = PokerHandEvaluator.card_to_rank_and_suit(card_idx)
			ranks.append(card_info.rank)
			suits.append(card_info.suit)
		
		if PokerHandEvaluator._is_royal_flush(ranks, suits):
			return PokerHands.HandTypes.ROYAL_FLUSH
		if PokerHandEvaluator._is_straight_flush(ranks, suits):
			return PokerHands.HandTypes.STRAIGHT_FLUSH
		if PokerHandEvaluator._is_four_of_a_kind(ranks):
			return PokerHands.HandTypes.FOUR_OF_A_KIND
		if PokerHandEvaluator._is_full_house(ranks):
			return PokerHands.HandTypes.FULL_HOUSE
		if PokerHandEvaluator._is_flush(suits): # Must be after full house
			return PokerHands.HandTypes.FLUSH
		if PokerHandEvaluator._is_straight(ranks): # Must be after flush and straight flush
			return PokerHands.HandTypes.STRAIGHT
		if PokerHandEvaluator._is_three_of_a_kind(ranks):
			return PokerHands.HandTypes.THREE_OF_A_KIND
		if PokerHandEvaluator._is_two_pair(ranks):
			return PokerHands.HandTypes.TWO_PAIR
		if PokerHandEvaluator._is_one_pair(ranks):
			return PokerHands.HandTypes.ONE_PAIR
		
		return PokerHands.HandTypes.HIGH_CARD
